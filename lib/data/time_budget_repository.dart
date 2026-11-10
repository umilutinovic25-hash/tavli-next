import 'package:drift/drift.dart';

import '../account/auth_controller.dart';
import '../domain/time_budget.dart';
import '../sync/synced_writer.dart';
import 'database.dart';

/// Raspoloživo vreme po danu u nedelji, za celo domaćinstvo. Upis ide sa
/// outbox-om; dan bez ograničenja se briše.
class TimeBudgetRepository {
  TimeBudgetRepository(this._db, {required this._scope, required this._writer});

  final AppDatabase _db;
  final AccountScope _scope;
  final SyncedWriter _writer;

  static const _entity = 'day_time_budget';

  String _id(int weekday) => '${_scope.householdId}-$weekday';

  Stream<List<DayBudget>> watchAll() =>
      (_db.select(_db.dayTimeBudgets)
            ..where((t) => t.householdId.equals(_scope.householdId))
            ..orderBy([(t) => OrderingTerm.asc(t.weekday)]))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                if (r.weekday >= 1 && r.weekday <= 7)
                  DayBudget(
                    weekday: r.weekday,
                    maxActiveMinutes: r.maxActiveMinutes,
                    windowStart: r.windowStart,
                    windowEnd: r.windowEnd,
                  ),
            ],
          );

  /// Čuva ograničenje dana (prazno ga uklanja). Baca [ArgumentError] na
  /// neispravan unos, pre bilo kakvog upisa.
  Future<void> save(DayBudget budget) {
    validBudget(budget);
    final id = _id(budget.weekday);
    return _db.transaction(() async {
      if (budget.isEmpty) {
        final deleted = await (_db.delete(
          _db.dayTimeBudgets,
        )..where((t) => t.id.equals(id))).go();
        if (deleted > 0) await _writer.delete(_entity, id);
        return;
      }
      await _db
          .into(_db.dayTimeBudgets)
          .insertOnConflictUpdate(
            DayTimeBudgetsCompanion.insert(
              id: id,
              householdId: Value(_scope.householdId),
              weekday: budget.weekday,
              maxActiveMinutes: Value(budget.maxActiveMinutes),
              windowStart: Value(budget.windowStart),
              windowEnd: Value(budget.windowEnd),
            ),
          );
      await _writer.upsert(_entity, id);
    });
  }
}
