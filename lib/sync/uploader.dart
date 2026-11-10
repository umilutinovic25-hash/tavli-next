import 'package:drift/drift.dart';

import '../account/auth_controller.dart';
import '../data/database.dart';
import '../data/recipe_photo_store.dart';
import 'entities.dart';
import 'sync_remote.dart';
import 'synced_writer.dart';

/// Ishod jednog slanja.
class UploadResult {
  const UploadResult({this.sent = 0, this.rejected = 0, this.stoppedBy});

  final int sent;
  final int rejected;

  /// Privremena greška (nema mreže) ili odbijena sesija; null = sve poslato.
  final SyncError? stoppedBy;

  bool get offline => stoppedBy is TransientSyncError;
  bool get unauthorized => stoppedBy is UnauthorizedSyncError;
}

/// Šalje red izmena (outbox) na server, redom (research R7):
/// uzastopne izmene istog entiteta i vrste idu zajedno (najviše
/// [batchSize]); trajno odbijena izmena se odlaže i ne blokira ostale;
/// privremena greška zaustavlja slanje; slike idu posle podataka i nikad ih
/// ne zaustavljaju.
class Uploader {
  Uploader({
    required this._db,
    required this._remote,
    required this._photos,
    required this._photoStore,
    required this._scope,
    required this._refreshSession,
    DateTime Function()? clock,
    this.batchSize = 100,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final SyncRemote _remote;
  final PhotoRemote _photos;
  final RecipePhotoStore _photoStore;
  final AccountScope _scope;

  /// Obnavlja sesiju posle 401; false kad je obnova odbijena.
  final Future<bool> Function() _refreshSession;
  final DateTime Function() _clock;
  final int batchSize;

  /// Pauze za sliku koja nije poslata: 5 s, 10 s, pa 30 s.
  static const photoBackoff = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  Future<UploadResult> run() async {
    var sent = 0, rejected = 0;
    var refreshed = false;

    Future<SyncError?> attempt(List<OutboxRow> batch) async {
      while (true) {
        try {
          sent += await _send(batch);
          return null;
        } on UnauthorizedSyncError catch (e) {
          await _release(batch);
          if (refreshed) return e;
          refreshed = true;
          if (!await _refreshSession()) return e;
        } on SyncError catch (e) {
          await _release(batch, e);
          return e;
        }
      }
    }

    // Podaci.
    while (true) {
      final batch = await _nextBatch();
      if (batch.isEmpty) break;
      final error = await attempt(batch);
      if (error == null) continue;
      if (error is! PermanentSyncError) {
        return UploadResult(sent: sent, rejected: rejected, stoppedBy: error);
      }
      // Jedan loš red ne sme da obori ostale iz grupe: šalju se pojedinačno.
      for (final entry in batch) {
        final single = await _reload(entry);
        if (single == null) continue;
        final e = await attempt([single]);
        if (e is PermanentSyncError) {
          await _reject(single, e);
          rejected++;
        } else if (e != null) {
          return UploadResult(sent: sent, rejected: rejected, stoppedBy: e);
        }
      }
    }

    // Slike: greška samo odlaže tu sliku.
    // Odbijena izmena stavke može značiti da server još pokazuje na staru
    // sliku. Ne brišemo fotografije dok se takva izmena ne razreši.
    final rejectedShopping =
        await (_db.select(_db.syncOutbox)..where(
              (t) =>
                  t.accountId.equals(_scope.userId) &
                  t.entity.equals('shopping_item') &
                  t.state.equals(OutboxState.rejected),
            ))
            .get();
    for (final entry in await _photoEntries()) {
      if (entry.op == OutboxOp.photoDelete && rejectedShopping.isNotEmpty) {
        continue;
      }
      try {
        await _sendPhoto(entry);
        sent++;
      } on PermanentSyncError catch (e) {
        await _reject(entry, e);
        rejected++;
      } on SyncError catch (e) {
        await _postpone(entry, e);
        if (e is TransientSyncError) break;
      }
    }
    return UploadResult(sent: sent, rejected: rejected);
  }

  SimpleSelectStatement<$SyncOutboxTable, OutboxRow> _pending(
    List<String> ops,
  ) {
    final now = _clock();
    return _db.select(_db.syncOutbox)
      ..where(
        (t) =>
            t.accountId.equals(_scope.userId) &
            t.state.equals(OutboxState.pending) &
            t.op.isIn(ops) &
            (t.nextAttemptAt.isNull() |
                t.nextAttemptAt.isSmallerOrEqualValue(now)),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.seq)]);
  }

  /// Prva izmena na redu i uzastopne istog entiteta i vrste; označene kao
  /// "šalje se".
  Future<List<OutboxRow>> _nextBatch() async {
    final candidates = await (_pending(OutboxOp.data)..limit(batchSize)).get();
    if (candidates.isEmpty) return const [];
    final first = candidates.first;
    final batch = [
      for (final e in candidates.takeWhile(
        (e) => e.entity == first.entity && e.op == first.op,
      ))
        e,
    ];
    await _mark(batch, OutboxState.sending);
    return batch;
  }

  Future<List<OutboxRow>> _photoEntries() => _pending(OutboxOp.photo).get();

  Future<OutboxRow?> _reload(OutboxRow e) async {
    final row = await (_db.select(
      _db.syncOutbox,
    )..where((t) => t.seq.equals(e.seq))).getSingleOrNull();
    if (row == null || row.state != OutboxState.pending) return null;
    await _mark([row], OutboxState.sending);
    return row;
  }

  Future<void> _mark(List<OutboxRow> entries, String state) =>
      (_db.update(_db.syncOutbox)
            ..where((t) => t.seq.isIn([for (final e in entries) e.seq])))
          .write(SyncOutboxCompanion(state: Value(state)));

  Future<void> _done(List<OutboxRow> entries) => (_db.delete(
    _db.syncOutbox,
  )..where((t) => t.seq.isIn([for (final e in entries) e.seq]))).go();

  /// Vraća grupu na čekanje (posle greške), sa brojem pokušaja.
  Future<void> _release(List<OutboxRow> entries, [SyncError? error]) async {
    for (final e in entries) {
      await (_db.update(
        _db.syncOutbox,
      )..where((t) => t.seq.equals(e.seq))).write(
        SyncOutboxCompanion(
          state: const Value(OutboxState.pending),
          attempts: Value(error == null ? e.attempts : e.attempts + 1),
          lastError: Value(error?.code ?? e.lastError),
        ),
      );
    }
  }

  Future<void> _reject(OutboxRow e, SyncError error) =>
      (_db.update(_db.syncOutbox)..where((t) => t.seq.equals(e.seq))).write(
        SyncOutboxCompanion(
          state: const Value(OutboxState.rejected),
          attempts: Value(e.attempts + 1),
          lastError: Value(error.code),
        ),
      );

  Future<void> _postpone(OutboxRow e, SyncError error) {
    final wait = photoBackoff[e.attempts.clamp(0, photoBackoff.length - 1)];
    return (_db.update(
      _db.syncOutbox,
    )..where((t) => t.seq.equals(e.seq))).write(
      SyncOutboxCompanion(
        attempts: Value(e.attempts + 1),
        nextAttemptAt: Value(_clock().add(wait)),
        lastError: Value(error.code),
      ),
    );
  }

  /// Šalje grupu i briše je iz reda; vraća broj poslatih izmena.
  Future<int> _send(List<OutboxRow> batch) async {
    final first = batch.first;
    if (first.entity == profileEntity) {
      for (final e in batch) {
        final account = await (_db.select(
          _db.accounts,
        )..where((t) => t.userId.equals(e.recordId))).getSingleOrNull();
        final name = account?.displayName;
        if (name != null) await _remote.updateProfileName(e.recordId, name);
      }
      await _done(batch);
      return batch.length;
    }
    final entity = entityByName(first.entity);
    if (entity == null) {
      await _done(
        batch,
      ); // nepoznat entitet (stariji build): nema šta da se pošalje
      return 0;
    }
    if (first.op == OutboxOp.delete) {
      await _remote.delete(entity.remoteTable, [
        for (final e in batch) e.recordId,
      ], idColumn: entity.remoteId);
      await _done(batch);
      return batch.length;
    }
    final rows = <Map<String, Object?>>[];
    final gone = <OutboxRow>[];
    for (final e in batch) {
      final row = await entity.read(_db, e.recordId);
      if (row == null) {
        gone.add(e); // zapis je u međuvremenu obrisan: brisanje sledi
      } else {
        rows.add(entity.toRemote(row));
      }
    }
    if (gone.isNotEmpty) await _done(gone);
    if (rows.isNotEmpty) {
      await _remote.upsert(
        entity.remoteTable,
        rows,
        onConflict: entity.remoteId,
      );
    }
    await _done([
      for (final e in batch)
        if (!gone.contains(e)) e,
    ]);
    return rows.length;
  }

  Future<void> _sendPhoto(OutboxRow e) async {
    final household = await _photoHousehold(e.recordId);
    final key = '$household/${photoFileName(e.recordId)}';
    if (e.op == OutboxOp.photoDelete) {
      await _photos.remove([key]);
      await _photoStore.delete(e.recordId);
    } else {
      final bytes = await _photoStore.read(e.recordId);
      // Fajla više nema (slika zamenjena pa obrisana): nema šta da se pošalje.
      if (bytes != null) await _photos.upload(key, bytes);
    }
    await _done([e]);
  }

  /// Domaćinstvo reda koji koristi sliku (slika napravljena pre prebacivanja
  /// pripada svom domaćinstvu); bez takvog reda — trenutno domaćinstvo.
  Future<String> _photoHousehold(String path) async {
    final recipe = await (_db.select(
      _db.recipes,
    )..where((t) => t.imagePath.equals(path))).getSingleOrNull();
    if (recipe?.householdId case final h?) return h;
    final item = await (_db.select(
      _db.shoppingItems,
    )..where((t) => t.photoPath.equals(path))).getSingleOrNull();
    if (item?.householdId case final h?) return h;
    final version = await (_db.select(
      _db.recipeVersions,
    )..where((t) => t.recipeJson.contains(path))).get();
    if (version.firstOrNull?.householdId case final h?) return h;
    return _scope.householdId;
  }
}
