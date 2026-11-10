import 'package:drift/drift.dart';

import '../data/database.dart';

/// Vrste izmena u redu za slanje.
abstract final class OutboxOp {
  static const upsert = 'upsert';
  static const delete = 'delete';
  static const photoUpload = 'photoUpload';
  static const photoDelete = 'photoDelete';

  static const data = [upsert, delete];
  static const photo = [photoUpload, photoDelete];
}

abstract final class OutboxState {
  static const pending = 'pending';

  /// Upravo se šalje: nova izmena istog zapisa dobija novi red (ne spaja se
  /// sa ovim), da ne bi bila izgubljena kad se ovaj obriše posle slanja.
  static const sending = 'sending';
  static const rejected = 'rejected';
}

/// Upisuje izmene u red za slanje (outbox). Repozitorijumi ga zovu unutar
/// iste drift transakcije u kojoj menjaju red, pa ili postoje i red i
/// izmena, ili nijedno (FR-013). Red čuva samo šta je promenjeno; sadržaj se
/// čita iz tabele u trenutku slanja.
class SyncedWriter {
  SyncedWriter(
    this._db, {
    required this.accountId,
    DateTime Function()? clock,
    this._onChange,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final String accountId;
  final DateTime Function() _clock;
  final void Function()? _onChange;

  /// Novo ili izmenjeno. Ako izmena tog zapisa već čeka, ostaje ta (raniji
  /// redni broj), pa roditelj uvek ide pre deteta.
  Future<void> upsert(String entity, String id) async {
    if (await _hasPending(entity, id, OutboxOp.upsert)) return _changed();
    await _add(entity, id, OutboxOp.upsert);
  }

  /// Kao [upsert], ali izmena ide na kraj reda: za dete koje je upravo
  /// prevezano na novog roditelja (npr. doprinos na novu stavku), da ne bi
  /// otišlo na server pre tog roditelja.
  Future<void> upsertLast(String entity, String id) async {
    await _remove(entity, id, OutboxOp.upsert);
    await _add(entity, id, OutboxOp.upsert);
  }

  /// Brisanje: izmene tog zapisa koje čekaju više nisu potrebne.
  Future<void> delete(String entity, String id) async {
    await _remove(entity, id, OutboxOp.upsert, includeRejected: true);
    await _add(entity, id, OutboxOp.delete);
  }

  /// Nova slika (lokalna relativna putanja).
  Future<void> photoUpload(String localPath) async {
    if (await _hasPending('photo', localPath, OutboxOp.photoUpload)) {
      return _changed();
    }
    await _add('photo', localPath, OutboxOp.photoUpload);
  }

  Future<void> photoDelete(
    String localPath, {
    Duration delay = Duration.zero,
  }) async {
    await _remove('photo', localPath, OutboxOp.photoUpload);
    await _add(
      'photo',
      localPath,
      OutboxOp.photoDelete,
      nextAttemptAt: delay == Duration.zero ? null : _clock().add(delay),
    );
  }

  /// Poništavanje brisanja pre isteka mogućnosti vraćanja stavke.
  Future<void> cancelPhotoDelete(String localPath) =>
      _remove('photo', localPath, OutboxOp.photoDelete);

  /// Izmene ovog naloga koje još nisu na serveru (čekaju, šalju se ili
  /// su odbijene).
  Future<int> unsentCount() async {
    final n = _db.syncOutbox.seq.count();
    final q = _db.selectOnly(_db.syncOutbox)
      ..addColumns([n])
      ..where(_db.syncOutbox.accountId.equals(accountId));
    return (await q.getSingle()).read(n) ?? 0;
  }

  Future<bool> _hasPending(String entity, String id, String op) async =>
      await (_db.select(_db.syncOutbox)
            ..where(
              (t) =>
                  t.accountId.equals(accountId) &
                  t.entity.equals(entity) &
                  t.recordId.equals(id) &
                  t.op.equals(op) &
                  t.state.equals(OutboxState.pending),
            )
            ..limit(1))
          .getSingleOrNull() !=
      null;

  Future<void> _remove(
    String entity,
    String id,
    String op, {
    bool includeRejected = false,
  }) =>
      (_db.delete(_db.syncOutbox)..where(
            (t) =>
                t.accountId.equals(accountId) &
                t.entity.equals(entity) &
                t.recordId.equals(id) &
                t.op.equals(op) &
                (includeRejected
                    ? const Constant(true)
                    : t.state.equals(OutboxState.pending)),
          ))
          .go();

  Future<void> _add(
    String entity,
    String id,
    String op, {
    DateTime? nextAttemptAt,
  }) async {
    await _db
        .into(_db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            accountId: accountId,
            entity: entity,
            recordId: id,
            op: op,
            createdAt: _clock(),
            nextAttemptAt: Value(nextAttemptAt),
          ),
        );
    _changed();
  }

  void _changed() => _onChange?.call();
}
