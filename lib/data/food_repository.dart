import 'package:drift/drift.dart';

import '../account/auth_controller.dart';
import '../domain/food.dart';
import '../domain/ids.dart' as ids;
import '../domain/shopping_sync.dart';
import '../sync/synced_writer.dart';
import 'database.dart';

/// Alias već postoji u vidljivom katalogu (zajedničkom ili domaćinstva).
class FoodAliasTakenException implements Exception {
  const FoodAliasTakenException(this.alias);

  final String alias;

  @override
  String toString() => 'FoodAliasTakenException($alias)';
}

/// Katalog namirnica na uređaju (036): zajednički deo stiže preuzimanjem i
/// samo se čita; sopstvene namirnice domaćinstva idu kroz outbox.
class FoodRepository {
  FoodRepository(
    this._db, {
    required this._scope,
    required this._writer,
    String Function()? newId,
  }) : _newId = newId ?? ids.newId;

  final AppDatabase _db;
  final AccountScope _scope;
  final SyncedWriter _writer;
  final String Function() _newId;

  Expression<bool> _visible(GeneratedColumn<String> householdId) =>
      householdId.isNull() | householdId.equals(_scope.householdId);

  Future<FoodCatalog> catalog() async {
    final foods = await (_db.select(
      _db.foods,
    )..where((t) => _visible(t.householdId))).get();
    final aliases = await (_db.select(
      _db.foodAliases,
    )..where((t) => _visible(t.householdId))).get();
    final conversions = await (_db.select(
      _db.foodConversions,
    )..where((t) => _visible(t.householdId))).get();
    final allergens = await (_db.select(
      _db.foodAllergens,
    )..where((t) => _visible(t.householdId))).get();
    return FoodCatalog(
      foods: [
        for (final f in foods)
          if (BaseUnit.values.asNameMap()[f.baseUnit] case final unit?)
            Food(
              id: f.id,
              householdId: f.householdId,
              name: f.name,
              category: f.category,
              baseUnit: unit,
            ),
      ],
      aliases: [
        for (final a in aliases)
          FoodAlias(
            foodId: a.foodId,
            householdId: a.householdId,
            alias: a.alias,
          ),
      ],
      conversions: [
        for (final c in conversions)
          FoodConversion(
            foodId: c.foodId,
            unit: c.unit,
            factorMicros: c.factorMicros,
          ),
      ],
      allergens: [
        for (final a in allergens) (foodId: a.foodId, code: a.allergenCode),
      ],
    );
  }

  /// Novi katalog posle svake izmene bilo koje od četiri tabele.
  Stream<FoodCatalog> watchCatalog() => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          _db.foods,
          _db.foodAliases,
          _db.foodConversions,
          _db.foodAllergens,
        },
      )
      .watch()
      .asyncMap((_) => catalog());

  /// Pravi sopstvenu namirnicu domaćinstva. Naziv je uvek i alias. Baca
  /// [FoodAliasTakenException] kad je neki alias zauzet i [ArgumentError] za
  /// alergen van [euAllergens]; tada se ništa ne upisuje.
  Future<String> createOwn(
    ValidFoodDraft draft, {
    Iterable<String> aliases = const [],
    Set<String> allergens = const {},
  }) => _db.transaction(() async {
    for (final a in allergens) {
      if (!euAllergens.containsKey(a)) {
        throw ArgumentError.value(a, 'allergens', 'Nepoznat alergen');
      }
    }
    final names = <String>{
      draft.name,
      for (final a in aliases)
        if (ingredientKey(a).isNotEmpty) ingredientKey(a),
    };
    final current = await catalog();
    for (final a in names) {
      if (current.match(a) != null) throw FoodAliasTakenException(a);
    }
    final id = _newId();
    await _db
        .into(_db.foods)
        .insert(
          FoodsCompanion.insert(
            id: id,
            householdId: Value(_scope.householdId),
            name: draft.name,
            category: draft.category,
            baseUnit: draft.baseUnit.name,
          ),
        );
    await _writer.upsert('food', id);
    for (final a in names) {
      await _addAlias(id, a);
    }
    for (final code in allergens) {
      final aid = _newId();
      await _db
          .into(_db.foodAllergens)
          .insert(
            FoodAllergensCompanion.insert(
              id: aid,
              foodId: id,
              householdId: Value(_scope.householdId),
              allergenCode: code,
            ),
          );
      await _writer.upsert('food_allergen', aid);
    }
    return id;
  });

  /// Menja naziv i kategoriju sopstvene namirnice; novi naziv postaje i
  /// alias (stari ostaje). Zajednička namirnica baca [StateError].
  Future<void> update(String id, {String? name, String? category}) =>
      _db.transaction(() async {
        final row = await (_db.select(
          _db.foods,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (row == null || row.householdId != _scope.householdId) {
          throw StateError('Namirnica nije sopstvena');
        }
        final valid = FoodDraft(
          name: name ?? row.name,
          category: category ?? row.category,
          baseUnit: row.baseUnit,
        ).validate();
        final current = await catalog();
        final owner = current.match(valid.name);
        if (owner != null && owner != id) {
          throw FoodAliasTakenException(valid.name);
        }
        await (_db.update(_db.foods)..where((t) => t.id.equals(id))).write(
          FoodsCompanion(
            name: Value(valid.name),
            category: Value(valid.category),
          ),
        );
        await _writer.upsert('food', id);
        if (owner == null) await _addAlias(id, valid.name);
      });

  Future<void> _addAlias(String foodId, String alias) async {
    final id = _newId();
    await _db
        .into(_db.foodAliases)
        .insert(
          FoodAliasesCompanion.insert(
            id: id,
            foodId: foodId,
            householdId: Value(_scope.householdId),
            alias: alias,
          ),
        );
    await _writer.upsert('food_alias', id);
  }
}
