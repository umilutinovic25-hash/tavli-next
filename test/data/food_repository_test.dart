import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/food_repository.dart';
import 'package:tavli/domain/food.dart';
import 'package:tavli/sync/synced_writer.dart';

const scope = AccountScope(userId: 'u1', householdId: 'h1');

void main() {
  late AppDatabase db;
  late FoodRepository foods;
  var n = 0;

  setUp(() async {
    n = 0;
    db = AppDatabase(NativeDatabase.memory());
    foods = FoodRepository(
      db,
      scope: scope,
      writer: SyncedWriter(db, accountId: 'u1'),
      newId: () => 'id-${++n}',
    );
    // Zajednički katalog kao posle preuzimanja + tuđa sopstvena namirnica.
    Future<void> food(String id, String name, String? hid) => db
        .into(db.foods)
        .insert(
          FoodsCompanion.insert(
            id: id,
            name: name,
            category: 'ostalo',
            baseUnit: 'kom',
            householdId: Value(hid),
          ),
        );
    Future<void> alias(String foodId, String alias, String? hid) => db
        .into(db.foodAliases)
        .insert(
          FoodAliasesCompanion.insert(
            id: '$foodId:$alias',
            foodId: foodId,
            alias: alias,
            householdId: Value(hid),
          ),
        );
    await food('f_jaje', 'jaje', null);
    await alias('f_jaje', 'jaje', null);
    await alias('f_jaje', 'jaja', null);
    await food('tudja', 'tuđe', 'h2');
    await alias('tudja', 'pitaja', 'h2');
    await db
        .into(db.foodConversions)
        .insert(
          FoodConversionsCompanion.insert(
            id: 'c1',
            foodId: 'f_jaje',
            unit: 'tuce',
            factorMicros: 12000000,
          ),
        );
    await db
        .into(db.foodAllergens)
        .insert(
          FoodAllergensCompanion.insert(
            id: 'g1',
            foodId: 'f_jaje',
            allergenCode: 'eggs',
          ),
        );
  });
  tearDown(() => db.close());

  Future<List<String>> outbox() async => [
    for (final r in await db.select(db.syncOutbox).get())
      '${r.entity}:${r.recordId}',
  ];

  test('katalog: zajedničko i svoje domaćinstvo, ne tuđe', () async {
    final c = await foods.catalog();
    expect(c.match('Jaja'), 'f_jaje');
    expect(c.match('pitaja'), isNull);
    expect(c.byId('tudja'), isNull);
    expect(c.conversion('f_jaje', 'tuce')?.factorMicros, 12000000);
    expect(c.allergens('f_jaje'), {'eggs'});
    expect(c.byId('f_jaje')!.baseUnit, BaseUnit.kom);
  });

  test('createOwn upisuje namirnicu, aliase, alergene i outbox', () async {
    final id = await foods.createOwn(
      const FoodDraft(
        name: 'Zmajevo voće',
        category: 'voće i povrće',
        baseUnit: 'g',
      ).validate(),
      aliases: const ['Pitaja', 'zmajevo   voće'],
      allergens: const {'sulphites'},
    );
    expect(id, 'id-1');
    final c = await foods.catalog();
    expect(c.byId(id)!.householdId, 'h1');
    expect(c.byId(id)!.name, 'zmajevo voće');
    expect(c.match('pitaja'), id);
    expect(c.match('Zmajevo voće'), id);
    expect(c.allergens(id), {'sulphites'});
    expect(
      [for (final a in await db.select(db.foodAliases).get()) a.alias]..sort(),
      ['jaja', 'jaje', 'pitaja', 'pitaja', 'zmajevo voće'],
    );
    expect(await outbox(), [
      'food:id-1',
      'food_alias:id-2',
      'food_alias:id-3',
      'food_allergen:id-4',
    ]);
  });

  test('zauzet alias: izuzetak i ništa se ne upisuje', () async {
    await expectLater(
      foods.createOwn(
        const FoodDraft(
          name: 'domaće jaje',
          category: 'ostalo',
          baseUnit: 'kom',
        ).validate(),
        aliases: const ['Jaja'],
      ),
      throwsA(
        isA<FoodAliasTakenException>().having((e) => e.alias, 'alias', 'jaja'),
      ),
    );
    expect(await db.select(db.foods).get(), hasLength(2));
    expect(await outbox(), isEmpty);
  });

  test('nepoznat alergen se odbija pre upisa', () async {
    await expectLater(
      foods.createOwn(
        const FoodDraft(
          name: 'mango',
          category: 'ostalo',
          baseUnit: 'g',
        ).validate(),
        allergens: const {'orasi'},
      ),
      throwsArgumentError,
    );
    expect(await outbox(), isEmpty);
  });

  test(
    'izmena sopstvene: naziv postaje i alias; zajednička se ne menja',
    () async {
      final id = await foods.createOwn(
        const FoodDraft(
          name: 'mango',
          category: 'ostalo',
          baseUnit: 'g',
        ).validate(),
      );
      await foods.update(id, name: 'Mango Alfonso', category: 'voće i povrće');
      final c = await foods.catalog();
      expect(c.byId(id)!.name, 'mango alfonso');
      expect(c.byId(id)!.category, 'voće i povrće');
      expect(c.match('mango'), id);
      expect(c.match('mango alfonso'), id);
      await expectLater(foods.update('f_jaje', name: 'x'), throwsStateError);
      await expectLater(
        foods.update(id, category: 'egzotika'),
        throwsFormatException,
      );
    },
  );

  test('watchCatalog javlja novu namirnicu', () async {
    final seen = <bool>[];
    final sub = foods.watchCatalog().listen(
      (c) => seen.add(c.match('mango') != null),
    );
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await foods.createOwn(
      const FoodDraft(
        name: 'mango',
        category: 'ostalo',
        baseUnit: 'g',
      ).validate(),
    );
    await pumpEventQueue();
    expect(seen.first, isFalse);
    expect(seen.last, isTrue);
  });

  test(
    'katalog nosi nutritivne vrednosti i izvor, ili ništa (nepoznato)',
    () async {
      await db
          .into(db.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'f_nutri_jaje',
              name: 'jaje',
              category: 'mlečni proizvodi i jaja',
              baseUnit: 'kom',
              kcal100: const Value(143),
              protein100: const Value(12.56),
              fat100: const Value(9.51),
              carbs100: const Value(0.72),
              nutritionSource: const Value('usda-sr-legacy-2018-04'),
              nutritionRef: const Value('171287'),
              unitGrams: const Value(50),
              unitGramsSource: const Value(
                'usda-sr-legacy-2018-04:171287:large',
              ),
            ),
          );
      await db
          .into(db.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'f_nutri_bez',
              name: 'kajmak',
              category: 'mlečni proizvodi i jaja',
              baseUnit: 'g',
            ),
          );
      final catalog = await foods.catalog();
      final egg = catalog.byId('f_nutri_jaje')!.nutrition!;
      expect(
        (egg.kcal, egg.protein, egg.fat, egg.carbs),
        (143, 12.56, 9.51, 0.72),
      );
      expect(egg.source, 'usda-sr-legacy-2018-04');
      expect(egg.ref, '171287');
      expect(catalog.byId('f_nutri_bez')!.nutrition, isNull);
      expect(catalog.byId('f_nutri_jaje')!.unitGrams, 50);
      expect(catalog.byId('f_nutri_bez')!.unitGrams, isNull);
    },
  );
}
