import 'package:drift/drift.dart';

import '../account/auth_controller.dart';
import '../domain/day_rules.dart';
import '../domain/ids.dart' as ids;
import '../domain/meal_plan.dart';
import '../sync/synced_writer.dart';
import 'database.dart';

/// Pravila po danima domaćinstva. Pravilo se dodaje ili briše (izmena je
/// novo pravilo), pa izuzetak na obroku uvek važi za tačno to pravilo.
class DayRuleRepository {
  DayRuleRepository(
    this._db, {
    required this._scope,
    required this._writer,
    DateTime Function()? clock,
    String Function()? newId,
  }) : _clock = clock ?? DateTime.now,
       _newId = newId ?? ids.newId;

  final AppDatabase _db;
  final AccountScope _scope;
  final SyncedWriter _writer;
  final DateTime Function() _clock;
  final String Function() _newId;

  static const _entity = 'day_rule';

  SimpleSelectStatement<$DayRulesTable, DayRuleRow> _all() =>
      _db.select(_db.dayRules)
        ..where((t) => t.householdId.equals(_scope.householdId))
        ..orderBy([
          (t) => OrderingTerm.asc(t.weekday),
          (t) => OrderingTerm.asc(t.createdAt),
          (t) => OrderingTerm.asc(t.id),
        ]);

  Stream<List<DayRule>> watchAll() =>
      _all().watch().map((rows) => rows.map(fromRow).nonNulls.toList());

  Future<List<DayRule>> getAll() async =>
      (await _all().get()).map(fromRow).nonNulls.toList();

  /// Dodaje pravilo; baca [ArgumentError] na neispravan unos.
  Future<DayRule> add({
    required int weekday,
    required RuleKind kind,
    MealType? mealType,
    String? value,
    RuleMode mode = RuleMode.required,
  }) async {
    final trimmed = value?.trim();
    final rule = validRule(
      DayRule(
        id: _newId(),
        weekday: weekday,
        kind: kind,
        mealType: mealType,
        value: trimmed == null || trimmed.isEmpty ? null : trimmed,
        mode: mode,
      ),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.dayRules)
          .insert(
            DayRulesCompanion.insert(
              id: rule.id,
              householdId: Value(_scope.householdId),
              weekday: rule.weekday,
              mealType: Value(rule.mealType?.name),
              kind: rule.kind.name,
              value: Value(rule.value),
              mode: Value(rule.mode.name),
              createdAt: _clock().toUtc(),
            ),
          );
      await _writer.upsert(_entity, rule.id);
    });
    return rule;
  }

  Future<void> remove(String id) => _db.transaction(() async {
    final deleted =
        await (_db.delete(_db.dayRules)..where(
              (t) => t.id.equals(id) & t.householdId.equals(_scope.householdId),
            ))
            .go();
    if (deleted > 0) await _writer.delete(_entity, id);
  });

  /// Nepoznata vrsta ili dan (novija verzija) se preskače.
  static DayRule? fromRow(DayRuleRow r) {
    final kind = RuleKind.tryParse(r.kind);
    if (kind == null || r.weekday < 1 || r.weekday > 7) return null;
    if (kind.needsValue && (r.value == null || r.value!.isEmpty)) return null;
    return DayRule(
      id: r.id,
      weekday: r.weekday,
      mealType: MealType.tryParse(r.mealType),
      kind: kind,
      value: kind.needsValue ? r.value : null,
      mode: RuleMode.parse(r.mode),
    );
  }
}
