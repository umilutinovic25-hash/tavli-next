import 'dart:convert';

import 'package:drift/drift.dart';

import '../account/auth_controller.dart';
import '../domain/user_preferences.dart';
import '../sync/synced_writer.dart';
import 'database.dart';

/// Preferencije ishrane domaćinstva: jedan red po domaćinstvu (id je id
/// domaćinstva). Svi članovi vide i menjaju iste preferencije. Upis ide sa
/// outbox-om, pa radi i van mreže.
class PreferencesRepository {
  PreferencesRepository(
    this._db, {
    required this._scope,
    required this._writer,
  });

  final AppDatabase _db;
  final AccountScope _scope;
  final SyncedWriter _writer;

  static const _entity = 'household_preference';

  SimpleSelectStatement<$HouseholdPreferencesTable, HouseholdPreferenceRow>
  _select() =>
      _db.select(_db.householdPreferences)
        ..where((t) => t.id.equals(_scope.householdId));

  /// Trenutne preferencije; bez reda su podrazumevane.
  Stream<UserPreferences> watch() => _select().watchSingleOrNull().map(
    (row) => row == null ? UserPreferences.defaults : _fromRow(row),
  );

  /// Jednokratno čitanje, za AI upite.
  Future<UserPreferences> current() async {
    final row = await _select().getSingleOrNull();
    return row == null ? UserPreferences.defaults : _fromRow(row);
  }

  /// Čuva preferencije (ceo red). Vrednosti su već proverene u
  /// [UserPreferences], pa se ništa neispravno ne upisuje.
  Future<void> save(UserPreferences prefs) {
    final id = _scope.householdId;
    if (id.isEmpty) throw StateError('Nema prijavljenog domaćinstva');
    return _db.transaction(() async {
      await _db
          .into(_db.householdPreferences)
          .insertOnConflictUpdate(
            HouseholdPreferencesCompanion.insert(
              id: id,
              householdId: Value(id),
              dietJson: Value(
                jsonEncode([
                  for (final d in FoodDiet.values)
                    if (prefs.diet.contains(d)) d.name,
                ]),
              ),
              dislikesJson: Value(jsonEncode(prefs.dislikes)),
              allergiesJson: Value(jsonEncode(prefs.allergies)),
              servings: Value(prefs.servings),
            ),
          );
      await _writer.upsert(_entity, id);
    });
  }

  static UserPreferences _fromRow(HouseholdPreferenceRow row) {
    List<String> strings(String json) => [
      for (final v in jsonDecode(json) as List<dynamic>) v as String,
    ];
    return UserPreferences(
      diet: [
        for (final name in strings(row.dietJson))
          for (final d in FoodDiet.values)
            if (d.name == name) d,
      ],
      dislikes: strings(row.dislikesJson),
      allergies: strings(row.allergiesJson),
      servings: row.servings,
    );
  }
}
