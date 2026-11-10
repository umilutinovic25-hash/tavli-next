import 'dart:convert';

import 'package:drift/drift.dart';

import '../account/auth_controller.dart';
import '../domain/cook_soon.dart';
import '../domain/ids.dart' as ids;
import '../domain/meal_plan.dart';
import '../domain/recipe.dart';
import '../domain/shopping_source.dart';
import '../sync/synced_writer.dart';
import 'database.dart';
import 'meal_plan_repository.dart';

/// Stavka reda ne postoji u ovom domaćinstvu (npr. već je raspoređena).
class CookSoonItemNotFoundException implements Exception {
  const CookSoonItemNotFoundException();
}

/// Red "Uskoro kuvam" domaćinstva. Stavke se čuvaju sa outbox-om i ne
/// traže kupovinu; raspoređivanje ide kroz [MealPlanRepository.approve].
class CookSoonRepository {
  CookSoonRepository(
    this._db, {
    required this._scope,
    required this._writer,
    required this._plans,
    DateTime Function()? clock,
    String Function()? newId,
  }) : _clock = clock ?? DateTime.now,
       _newId = newId ?? ids.newId;

  final AppDatabase _db;
  final AccountScope _scope;
  final SyncedWriter _writer;
  final MealPlanRepository _plans;
  final DateTime Function() _clock;
  final String Function() _newId;

  static const _entity = 'cook_soon_item';

  SimpleSelectStatement<$CookSoonItemsTable, CookSoonItemRow> _all() =>
      _db.select(_db.cookSoonItems)
        ..where((t) => t.householdId.equals(_scope.householdId))
        ..orderBy([
          (t) => OrderingTerm.asc(t.position),
          (t) => OrderingTerm.asc(t.createdAt),
          (t) => OrderingTerm.asc(t.id),
        ]);

  /// Red, prvo stavke sa manjim redosledom. Pokvaren snimak se preskače.
  Stream<List<CookSoonItem>> watchAll() =>
      _all().watch().map((rows) => rows.map(_fromRow).nonNulls.toList());

  /// Dodaje recept na kraj reda. Isti recept dvaput je dve odvojene namere.
  Future<void> add(Recipe recipe) => _db.transaction(() async {
    final rows = await _all().get();
    final position = rows.isEmpty ? 0 : rows.last.position + 1;
    final id = _newId();
    await _db
        .into(_db.cookSoonItems)
        .insert(
          CookSoonItemsCompanion.insert(
            id: id,
            householdId: Value(_scope.householdId),
            recipeId: Value(recipe.id),
            recipeSnapshotJson: jsonEncode(
              RecipeSnapshot.fromRecipe(recipe).toJson(),
            ),
            servings: cookSoonServings(recipe.servings),
            position: position,
            createdAt: _clock().toUtc(),
          ),
        );
    await _writer.upsert(_entity, id);
  });

  Future<void> remove(String id) => _db.transaction(() async {
    await _find(id);
    await _delete(id);
  });

  /// Premešta stavku na mesto [index]; menjaju se samo pomereni redovi.
  Future<void> move(String id, int index) => _db.transaction(() async {
    final rows = await _all().get();
    if (!rows.any((r) => r.id == id)) {
      throw const CookSoonItemNotFoundException();
    }
    final current = {for (final r in rows) r.id: r.position};
    final order = reorderedIds([for (final r in rows) ?_fromRow(r)], id, index);
    for (final (position, rowId) in order.indexed) {
      if (current[rowId] == position) continue;
      await (_db.update(_db.cookSoonItems)..where((t) => t.id.equals(rowId)))
          .write(CookSoonItemsCompanion(position: Value(position)));
      await _writer.upsert(_entity, rowId);
    }
  });

  /// Stavlja stavku na [slot] plana i uklanja je iz reda, sve ili ništa.
  /// Zastareo plan ili zaključan, skuvan i prošao obrok bacaju
  /// [StaleDraftException]; stavka tada ostaje u redu.
  Future<void> schedule(
    String id, {
    required MealPlan plan,
    required MealSlot slot,
    required PlanBase base,
  }) => _db.transaction(() async {
    final item = _fromRow(await _find(id));
    if (item == null) throw const CookSoonItemNotFoundException();
    await _plans.approve(
      scheduleDraft(item: item, plan: plan, base: base, slot: slot),
    );
    await _delete(id);
  });

  Future<CookSoonItemRow> _find(String id) async {
    final row =
        await (_db.select(_db.cookSoonItems)..where(
              (t) => t.id.equals(id) & t.householdId.equals(_scope.householdId),
            ))
            .getSingleOrNull();
    if (row == null) throw const CookSoonItemNotFoundException();
    return row;
  }

  Future<void> _delete(String id) async {
    await (_db.delete(_db.cookSoonItems)..where((t) => t.id.equals(id))).go();
    await _writer.delete(_entity, id);
  }

  static CookSoonItem? _fromRow(CookSoonItemRow r) {
    try {
      return CookSoonItem(
        id: r.id,
        recipeId: r.recipeId,
        snapshot: RecipeSnapshot.fromJson(
          jsonDecode(r.recipeSnapshotJson) as Map<String, dynamic>,
        ),
        servings: r.servings,
        position: r.position,
        createdAt: r.createdAt,
      );
    } on Object {
      return null;
    }
  }
}
