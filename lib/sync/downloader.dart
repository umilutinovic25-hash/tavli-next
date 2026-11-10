import 'package:drift/drift.dart';

import '../account/auth_controller.dart';
import '../data/database.dart';
import '../data/recipe_photo_store.dart';
import 'entities.dart';
import 'sync_epoch.dart';
import 'sync_remote.dart';
import 'synced_writer.dart';

/// Preuzima podatke naloga sa servera (research R9): po entitetu, strane
/// od [pageSize] redova redom po (updated_at, id); pozicija se čuva posle
/// svake strane, pa se prekinuto preuzimanje nastavlja. Svako pokretanje
/// kreće [overlap] pre sačuvane pozicije (izmene koje su kasno potvrđene);
/// upis po id-ju je idempotentan.
class Downloader {
  Downloader({
    required this._db,
    required this._remote,
    required this._scope,
    this.epoch,
    this.pageSize = 500,
    this.overlap = const Duration(seconds: 60),
    this.photoStore,
  });

  final AppDatabase _db;
  final SyncRemote _remote;
  final AccountScope _scope;

  /// Ako se promeni dok preuzimanje traje, stranica se ne upisuje.
  final SyncEpoch? epoch;
  int? _startEpoch;
  final RecipePhotoStore? photoStore;
  final _staleShoppingPhotos = <String>{};
  final int pageSize;
  final Duration overlap;

  static const _deletions = 'deletions';

  /// Baca [SyncError] (nastavlja se sledeći put od sačuvane pozicije).
  Future<void> run() async {
    _startEpoch = epoch?.value;
    await _pull(key: profileEntity, table: 'profiles', apply: _applyProfile);
    for (final e in syncEntities) {
      await _pull(
        key: e.name,
        table: e.remoteTable,
        idColumn: e.remoteId,
        apply: (row) => _applyRow(e, row),
      );
    }
    await _pull(
      key: _deletions,
      table: _deletions,
      timeColumn: 'deleted_at',
      apply: _applyTombstone,
    );
  }

  Future<void> _pull({
    required String key,
    required String table,
    required Future<void> Function(Map<String, Object?>) apply,
    String timeColumn = 'updated_at',
    String idColumn = 'id',
  }) async {
    final cursor =
        await (_db.select(_db.syncCursors)..where(
              (t) => t.accountId.equals(_scope.userId) & t.entity.equals(key),
            ))
            .getSingleOrNull();
    String? since = cursor == null
        ? null
        : _iso(cursor.updatedAt.subtract(overlap));
    String? afterId;
    while (true) {
      final rows = await _remote.fetchSince(
        table,
        limit: pageSize,
        since: since,
        afterId: afterId,
        timeColumn: timeColumn,
        idColumn: idColumn,
      );
      if (rows.isEmpty) return;
      final last = rows.last;
      since = _iso(DateTime.parse(last[timeColumn]! as String));
      afterId = last[idColumn]! as String;
      try {
        await _db.transaction(() async {
          // Transakcije su redom: osvežavanje naloga koje je obrisalo
          // pozicije je ili pre ove (vidi se nova epoha) ili posle nje.
          if (epoch != null && epoch!.value != _startEpoch) {
            throw const CancelledSyncError();
          }
          for (final r in rows) {
            await apply(r);
          }
          await _db
              .into(_db.syncCursors)
              .insertOnConflictUpdate(
                SyncCursorsCompanion.insert(
                  accountId: _scope.userId,
                  entity: key,
                  updatedAt: DateTime.parse(since!),
                  lastId: afterId!,
                ),
              );
        });
      } catch (_) {
        _staleShoppingPhotos.clear();
        rethrow;
      }
      for (final path in _staleShoppingPhotos.toList()) {
        await photoStore?.delete(path);
        _staleShoppingPhotos.remove(path);
      }
      if (rows.length < pageSize) return;
    }
  }

  static String _iso(DateTime d) => d.toUtc().toIso8601String();

  /// Ima li zapis lokalnu izmenu koja još nije na serveru (čeka, šalje
  /// se ili je odbijena): ona se ne prepisuje (FR-014).
  Future<bool> _hasLocalChange(String entity, String id) async =>
      await (_db.select(_db.syncOutbox)
            ..where(
              (t) =>
                  t.accountId.equals(_scope.userId) &
                  t.entity.equals(entity) &
                  t.recordId.equals(id),
            )
            ..limit(1))
          .getSingleOrNull() !=
      null;

  Future<void> _applyRow(
    SyncEntity<Table, Object?> e,
    Map<String, Object?> row,
  ) async {
    final id = row[e.remoteId]! as String;
    if (await _hasLocalChange(e.name, id)) return;
    if (e.name == 'shopping_item' && photoStore != null) {
      final previous = await const ShoppingItemEntity().read(_db, id);
      final next = photoLocalPath(row['photo_path'] as String?);
      if (previous?.photoPath case final path? when path != next) {
        _staleShoppingPhotos.add(path);
      }
    }
    await e.write(_db, row);
  }

  Future<void> _applyProfile(Map<String, Object?> row) async {
    final id = row['id'] as String?;
    if (id != _scope.userId || await _hasLocalChange(profileEntity, id!)) {
      return;
    }
    await (_db.update(_db.accounts)..where((t) => t.userId.equals(id))).write(
      AccountsCompanion(displayName: Value(row['display_name'] as String?)),
    );
  }

  /// Brisanje sa drugog uređaja: briše se i lokalno, a izmene tog zapisa
  /// koje čekaju se odbacuju (brisanje pobeđuje).
  Future<void> _applyTombstone(Map<String, Object?> row) async {
    final e = entityByName(row['entity']! as String);
    final id = row['record_id']! as String;
    if (e == null) return;
    if (e.name == 'shopping_item') {
      final item = await const ShoppingItemEntity().read(_db, id);
      if (item?.photoPath case final path?) {
        if (photoStore != null) _staleShoppingPhotos.add(path);
        final pending =
            await (_db.select(_db.syncOutbox)..where(
                  (t) =>
                      t.accountId.equals(_scope.userId) &
                      t.entity.equals('photo') &
                      t.recordId.equals(path) &
                      t.op.equals(OutboxOp.photoUpload),
                ))
                .get();
        if (pending.isNotEmpty) {
          await SyncedWriter(_db, accountId: _scope.userId).photoDelete(path);
        }
      }
    }
    await e.deleteLocal(_db, id);
    await (_db.delete(_db.syncOutbox)..where(
          (t) =>
              t.accountId.equals(_scope.userId) &
              t.entity.equals(e.name) &
              t.recordId.equals(id),
        ))
        .go();
  }
}
