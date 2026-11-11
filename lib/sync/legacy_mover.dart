import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../account/auth_controller.dart';
import '../data/database.dart';
import 'entities.dart';
import 'synced_writer.dart';

/// Jednom po uređaju: podaci od pre naloga (householdId/userId = null)
/// prelaze u nalog koji se prvi prijavi i stavljaju se u red za slanje
/// (FR-019). Sve je jedna SQLite transakcija: prekinuto prebacivanje se
/// ili nije desilo ili je celo, pa ponovno pokretanje daje isti rezultat.
class LegacyMover {
  LegacyMover(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Ključ u `AppSettings`: `{accountId, finishedAt}`.
  static const settingKey = 'legacy_move';

  /// Samo za testove: poziva se pred kraj transakcije (simulira prekid).
  @visibleForTesting
  Future<void> Function()? beforeFinish;

  Future<bool> _done() async =>
      await (_db.select(
        _db.appSettings,
      )..where((t) => t.key.equals(settingKey))).getSingleOrNull() !=
      null;

  /// Ima li šta da se prebaci (za traku "Čuvam tvoje podatke…").
  Future<bool> needsMove() async {
    if (await _done()) return false;
    for (final e in syncEntities) {
      if (e is TasteProfileEntity || e.hasSharedRows) continue;
      final col = e.scope == EntityScope.household ? 'household_id' : 'user_id';
      final row = await _db
          .customSelect(
            'SELECT 1 FROM ${e.table(_db).actualTableName} '
            'WHERE $col IS NULL LIMIT 1',
          )
          .getSingleOrNull();
      if (row != null) return true;
    }
    return false;
  }

  /// Prebacuje i vraća broj prebačenih zapisa (0 kad je već urađeno).
  Future<int> moveIfNeeded(AccountScope scope) => _db.transaction(() async {
    if (await _done()) return 0;
    final writer = SyncedWriter(_db, accountId: scope.userId, clock: _clock);
    var moved = 0;
    final photos = <String>{};

    for (final e in syncEntities) {
      if (e is TasteProfileEntity || e.hasSharedRows) continue;
      final household = e.scope == EntityScope.household;
      final col = household ? 'household_id' : 'user_id';
      final value = household ? scope.householdId : scope.userId;
      final table = e.table(_db).actualTableName;
      final rows = await _db
          .customSelect('SELECT id FROM $table WHERE $col IS NULL')
          .get();
      if (rows.isEmpty) continue;
      await _db.customUpdate(
        'UPDATE $table SET $col = ? WHERE $col IS NULL',
        variables: [Variable.withString(value)],
        updates: {e.table(_db)},
      );
      for (final r in rows) {
        final id = r.read<String>('id');
        await writer.upsert(e.name, id);
        moved++;
        if (e is RecipeEntity) {
          final row = await e.read(_db, id);
          if (row?.imagePath case final p?) photos.add(p);
        } else if (e is RecipeVersionEntity) {
          final row = await e.read(_db, id);
          final json = row == null ? null : _decode(row.recipeJson);
          if (json?['imagePath'] case final String p) photos.add(p);
        }
      }
    }

    // Profil ukusa samo ako ga nalog još nema.
    final taste = await _db.select(_db.userProfiles).get();
    final legacy = taste.where((t) => t.id.startsWith('legacy')).toList();
    if (legacy.isNotEmpty && !taste.any((t) => t.id == scope.userId)) {
      await (_db.update(_db.userProfiles)
            ..where((t) => t.id.equals(legacy.first.id)))
          .write(UserProfilesCompanion(id: Value(scope.userId)));
      await writer.upsert(const TasteProfileEntity().name, scope.userId);
      moved++;
    }

    for (final p in photos) {
      await writer.photoUpload(p);
    }
    await beforeFinish?.call();
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: settingKey,
            value: jsonEncode({
              'accountId': scope.userId,
              'finishedAt': _clock().toUtc().toIso8601String(),
            }),
          ),
        );
    return moved;
  });

  static Map<String, Object?>? _decode(String s) {
    try {
      final v = jsonDecode(s);
      return v is Map<String, Object?> ? v : null;
    } on FormatException {
      return null;
    }
  }
}
