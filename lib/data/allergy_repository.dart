import 'dart:convert';

import 'package:drift/drift.dart';

import '../account/auth_controller.dart';
import '../domain/allergy.dart';
import '../domain/food.dart' show euAllergens;
import '../sync/synced_writer.dart';
import 'database.dart';

/// Alergije po osobi (039). Osoba menja samo svoj red (id
/// `domaćinstvo:osoba`); unija svih članova aktivnog domaćinstva važi za
/// svaki obrok. Upis ide sa outbox-om, pa radi i van mreže.
class AllergyRepository {
  AllergyRepository(this._db, {required this._scope, required this._writer});

  final AppDatabase _db;
  final AccountScope _scope;
  final SyncedWriter _writer;

  static const _entity = 'member_allergy';

  String get _myId => memberAllergyId(_scope.householdId, _scope.userId);

  /// Moje alergije u aktivnom domaćinstvu; bez reda su prazne.
  Stream<PersonAllergies> watchMine() =>
      (_db.select(
        _db.memberAllergies,
      )..where((t) => t.id.equals(_myId))).watchSingleOrNull().map(
        (row) => row == null
            ? PersonAllergies(
                householdId: _scope.householdId,
                userId: _scope.userId,
              )
            : _fromRow(row),
      );

  SimpleSelectStatement<$MemberAllergiesTable, MemberAllergyRow> _household() =>
      _db.select(_db.memberAllergies)
        ..where((t) => t.householdId.equals(_scope.householdId));

  /// Unija svih članova aktivnog domaćinstva.
  Stream<HouseholdAllergies> watchHousehold() => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {_db.memberAllergies, _db.householdPreferences},
      )
      .watch()
      .asyncMap((_) => current());

  /// Jednokratno čitanje, za proveru AI recepata.
  Future<HouseholdAllergies> current() async {
    final rows = await _household().get();
    final legacy =
        await (_db.select(_db.householdPreferences)
              ..where((t) => t.householdId.equals(_scope.householdId)))
            .getSingleOrNull();
    return HouseholdAllergies.union(
      rows.map(_fromRow),
      legacy: legacy == null ? const [] : _strings(legacy.allergiesJson),
    );
  }

  /// Čuva moje alergije (ceo red). [PersonAllergies] proverava vrednosti,
  /// pa se ništa neispravno ne upisuje.
  Future<void> saveMine({
    required Iterable<String> codes,
    required Iterable<String> custom,
  }) {
    if (_scope.householdId.isEmpty) {
      throw StateError('Nema prijavljenog domaćinstva');
    }
    final value = PersonAllergies(
      householdId: _scope.householdId,
      userId: _scope.userId,
      codes: codes,
      custom: custom,
    );
    return _db.transaction(() async {
      await _db
          .into(_db.memberAllergies)
          .insertOnConflictUpdate(
            MemberAllergiesCompanion.insert(
              id: value.id,
              householdId: Value(value.householdId),
              userId: value.userId,
              codesJson: Value(
                jsonEncode([
                  for (final c in euAllergens.keys)
                    if (value.codes.contains(c)) c,
                ]),
              ),
              customJson: Value(jsonEncode(value.custom)),
            ),
          );
      await _writer.upsert(_entity, value.id);
    });
  }

  /// Red sa servera: nepoznat kod (noviji klijent) se preskače.
  static PersonAllergies _fromRow(MemberAllergyRow row) {
    return PersonAllergies(
      householdId: row.householdId ?? '',
      userId: row.userId,
      codes: _strings(row.codesJson).where(euAllergens.containsKey),
      custom: _strings(row.customJson),
    );
  }

  static List<String> _strings(String json) => [
    for (final v in jsonDecode(json) as List<dynamic>)
      if (v is String) v,
  ];
}
