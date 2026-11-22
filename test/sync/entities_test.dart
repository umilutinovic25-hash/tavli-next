import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/sync/entities.dart';

/// Kako bi red izgledao kad stigne sa servera (JSON + updated_at).
Map<String, Object?> viaServer(Map<String, Object?> remote) =>
    (jsonDecode(jsonEncode(remote)) as Map<String, Object?>)
      ..putIfAbsent('updated_at', () => '2026-10-30T12:00:00.123456+00:00');

void main() {
  late AppDatabase db;
  final t = DateTime.utc(2026, 10, 30, 10, 5, 7);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> roundTrip<R>(
    SyncEntity<Table, R> e,
    Insertable<R> local,
    String id,
    void Function(Map<String, Object?> remote) checkRemote,
  ) async {
    await db.into(e.table(db)).insert(local);
    final row = (await e.read(db, id)) as R;
    final remote = e.toRemote(row);
    checkRemote(remote);
    expect(remote.keys.every((k) => k == k.toLowerCase()), isTrue);

    await e.deleteLocal(db, id);
    expect(await e.read(db, id), isNull);
    await e.write(db, viaServer(remote));
    final back = await e.read(db, id);
    expect(e.toRemote(back as R), remote, reason: e.name);
  }

  test('recept: JSON liste, ime slike bez fascikle, UTC vreme', () async {
    await roundTrip(
      const RecipeEntity(),
      RecipesCompanion.insert(
        id: 'r1',
        title: 'Sarma',
        servings: 4,
        prepMinutes: const Value(60),
        source: 'manual',
        ingredientsJson: '[{"name":"kupus","quantity":0.5}]',
        stepsJson: '["Kuvati."]',
        imagePath: const Value('recipe_photos/a.jpg'),
        createdAt: t,
        updatedAt: t,
        householdId: const Value('h1'),
      ),
      'r1',
      (r) {
        expect(r['household_id'], 'h1');
        expect(r['ingredients'], [
          {'name': 'kupus', 'quantity': 0.5},
        ]);
        expect(r['steps'], ['Kuvati.']);
        expect(r['image_path'], 'a.jpg');
        expect(r['created_at'], '2026-10-30T10:05:07.000Z');
        expect(r.containsKey('updated_at'), isFalse);
      },
    );
    final row = (await db.select(db.recipes).get()).single;
    expect(row.imagePath, 'recipe_photos/a.jpg');
    expect(row.updatedAt.toUtc(), DateTime.utc(2026, 10, 30, 12));
  });

  test(
    'oznake recepta idu tamo i nazad; neoznačen recept šalje null',
    () async {
      await roundTrip(
        const RecipeEntity(),
        RecipesCompanion.insert(
          id: 'r2',
          title: 'Pasulj',
          servings: 4,
          source: 'ai',
          ingredientsJson: '[]',
          stepsJson: '[]',
          createdAt: t,
          updatedAt: t,
          householdId: const Value('h1'),
          mealTypesJson: const Value('["lunch","dinner"]'),
          weight: const Value('hearty'),
          dishKind: const Value('cooked'),
          labelsSource: const Value('user'),
        ),
        'r2',
        (r) {
          expect(r['meal_types'], ['lunch', 'dinner']);
          expect(r['weight'], 'hearty');
          expect(r['dish_kind'], 'cooked');
          expect(r['labels_source'], 'user');
        },
      );
      await roundTrip(
        const RecipeEntity(),
        RecipesCompanion.insert(
          id: 'r3',
          title: 'Stari recept',
          servings: 2,
          source: 'manual',
          ingredientsJson: '[]',
          stepsJson: '[]',
          createdAt: t,
          updatedAt: t,
          householdId: const Value('h1'),
        ),
        'r3',
        (r) {
          expect(r['meal_types'], isNull);
          expect(r['weight'], isNull);
          expect(r['dish_kind'], isNull);
          expect(r['labels_source'], isNull);
        },
      );
    },
  );

  test('nepoznata vrsta jela sa novijeg servera se čuva i vraća '
      'nepromenjena', () async {
    const entity = RecipeEntity();
    await entity.write(db, {
      'id': 'r4',
      'household_id': 'h1',
      'title': 'Brunch tanjir',
      'servings': 2,
      'prep_minutes': null,
      'source': 'ai',
      'ingredients': <Object?>[],
      'steps': <Object?>[],
      'image_path': null,
      'answered_by': null,
      'created_at': '2026-12-01T10:00:00Z',
      'meal_types': ['brunch'],
      'dish_kind': 'bowl',
      'weight': null,
      'labels_source': 'ai',
    });

    final row = (await entity.read(db, 'r4'))!;
    final remote = entity.toRemote(row);
    expect(remote['meal_types'], ['brunch']);
    expect(remote['dish_kind'], 'bowl');
  });

  test('verzija recepta', () async {
    await roundTrip(
      const RecipeVersionEntity(),
      RecipeVersionsCompanion.insert(
        id: 'v1',
        recipeId: 'r1',
        recipeJson: '{"title":"Sarma"}',
        createdAt: t,
        changeKind: const Value('manual'),
        instruction: const Value('posno'),
        householdId: const Value('h1'),
      ),
      'v1',
      (r) {
        expect(r['recipe_json'], {'title': 'Sarma'});
        expect(r['recipe_id'], 'r1');
      },
    );
  });

  test('lista i stavka za kupovinu', () async {
    await roundTrip(
      const ShoppingListEntity(),
      ShoppingListsCompanion.insert(
        id: 'l1',
        name: 'Lista',
        createdAt: t,
        mealPlanId: const Value('p1'),
        week: const Value(2),
        householdId: const Value('h1'),
      ),
      'l1',
      (r) => expect(r['meal_plan_id'], 'p1'),
    );
    await roundTrip(
      const ShoppingItemEntity(),
      ShoppingItemsCompanion.insert(
        id: 'i1',
        listId: 'l1',
        name: 'mleko',
        category: 'ostalo',
        quantity: const Value(1.5),
        isBought: const Value(true),
        fromRecipeIdsJson: const Value('["r1"]'),
        householdId: const Value('h1'),
      ),
      'i1',
      (r) {
        expect(r['from_recipe_ids'], ['r1']);
        expect(r['is_bought'], isTrue);
      },
    );
  });

  test('ostava, plan i stavka plana', () async {
    await roundTrip(
      const PantryItemEntity(),
      PantryItemsCompanion.insert(
        id: 'o1',
        name: 'so',
        category: 'ostalo',
        addedAt: t,
        expiresAt: Value(t.add(const Duration(days: 3))),
        householdId: const Value('h1'),
      ),
      'o1',
      (r) => expect(r['expires_at'], '2026-11-02T10:05:07.000Z'),
    );
    await roundTrip(
      const MealPlanEntity(),
      MealPlansCompanion.insert(
        id: 'p1',
        startDate: t,
        endDate: t,
        mealTypesJson: '["lunch"]',
        createdAt: t,
        householdId: const Value('h1'),
      ),
      'p1',
      (r) => expect(r['meal_types'], ['lunch']),
    );
    await roundTrip(
      const MealPlanEntryEntity(),
      MealPlanEntriesCompanion.insert(
        id: 'e1',
        planId: 'p1',
        date: t,
        mealType: 'lunch',
        recipeId: const Value('r1'),
        householdId: const Value('h1'),
      ),
      'e1',
      (r) => expect(r['plan_id'], 'p1'),
    );
  });

  test('datum bez vremena sa servera čuva isti kalendarski dan', () async {
    const entity = MealPlanEntity();
    await entity.write(db, {
      'id': 'date-only',
      'start_date': '2026-12-31',
      'end_date': '2027-01-06',
      'meal_types': ['lunch'],
      'created_at': '2026-12-01T10:00:00Z',
      'household_id': 'h1',
    });

    final row = await db.select(db.mealPlans).getSingle();
    expect(row.startDate.toUtc(), DateTime.utc(2026, 12, 31));
    expect(row.endDate.toUtc(), DateTime.utc(2027, 1, 6));
  });

  test(
    'datumi perioda nedeljnog spiska čuvaju granice kalendarskog dana',
    () async {
      const entity = ShoppingListEntity();
      await entity.write(db, {
        'id': 'week-date-only',
        'name': 'Nedelja 53',
        'meal_plan_id': null,
        'week': 53,
        'period_start': '2026-12-28',
        'period_end': '2027-01-03',
        'created_at': '2026-12-01T10:00:00Z',
      });

      final row = await db.select(db.shoppingLists).getSingle();
      expect(row.periodStart!.toUtc(), DateTime.utc(2026, 12, 28));
      expect(row.periodEnd!.toUtc(), DateTime.utc(2027, 1, 3));
    },
  );

  test('kalendarski datumi idu na server kao YYYY-MM-DD', () async {
    await db
        .into(db.mealPlans)
        .insert(
          MealPlansCompanion.insert(
            id: 'p-wire',
            startDate: DateTime.utc(2026, 12, 31),
            endDate: DateTime.utc(2027, 1, 6),
            mealTypesJson: '["lunch"]',
            createdAt: DateTime.utc(2026, 12, 1, 10),
            householdId: const Value('h1'),
          ),
        );
    final plan = await const MealPlanEntity().read(db, 'p-wire');
    final remotePlan = const MealPlanEntity().toRemote(plan!);
    expect(remotePlan['start_date'], '2026-12-31');
    expect(remotePlan['end_date'], '2027-01-06');
    expect(remotePlan['created_at'], '2026-12-01T10:00:00.000Z');

    await db
        .into(db.mealPlanEntries)
        .insert(
          MealPlanEntriesCompanion.insert(
            id: 'e-wire',
            planId: 'p-wire',
            date: DateTime.utc(2027, 1, 2),
            mealType: 'lunch',
            householdId: const Value('h1'),
          ),
        );
    final entry = await const MealPlanEntryEntity().read(db, 'e-wire');
    expect(const MealPlanEntryEntity().toRemote(entry!)['date'], '2027-01-02');

    await db
        .into(db.shoppingLists)
        .insert(
          ShoppingListsCompanion.insert(
            id: 'l-wire',
            name: 'Nedelja 1',
            createdAt: DateTime.utc(2026, 12, 1, 10),
            periodStart: Value(DateTime.utc(2026, 12, 28)),
            periodEnd: Value(DateTime.utc(2027, 1, 3)),
            householdId: const Value('h1'),
          ),
        );
    final list = await const ShoppingListEntity().read(db, 'l-wire');
    final remoteList = const ShoppingListEntity().toRemote(list!);
    expect(remoteList['period_start'], '2026-12-28');
    expect(remoteList['period_end'], '2027-01-03');
  });

  test('lista bez perioda šalje null za oba datuma', () async {
    await db
        .into(db.shoppingLists)
        .insert(
          ShoppingListsCompanion.insert(
            id: 'l-none',
            name: 'Recepti',
            createdAt: DateTime.utc(2026, 12, 1, 10),
            householdId: const Value('h1'),
          ),
        );
    final list = await const ShoppingListEntity().read(db, 'l-none');
    final remote = const ShoppingListEntity().toRemote(list!);
    expect(remote['period_start'], isNull);
    expect(remote['period_end'], isNull);
  });

  test('vremenska oznaka sa vremenskom zonom ostaje isti trenutak', () async {
    const entity = RecipeEntity();
    await entity.write(db, {
      'id': 'offset-time',
      'household_id': 'h1',
      'title': 'Sarma',
      'servings': 2,
      'prep_minutes': null,
      'source': 'manual',
      'ingredients': [],
      'steps': [],
      'image_path': null,
      'answered_by': null,
      'created_at': '2026-12-31T01:30:00+02:00',
    });

    final row = await entity.read(db, 'offset-time');
    expect(
      entity.toRemote(row as RecipeRow)['created_at'],
      '2026-12-30T23:30:00.000Z',
    );
  });

  test('ocena i profil ukusa pripadaju osobi', () async {
    await roundTrip(
      const RatingEntity(),
      RatingsCompanion.insert(
        id: 'g1',
        recipeId: 'r1',
        stars: 5,
        cookedAt: t,
        userId: const Value('u1'),
      ),
      'g1',
      (r) {
        expect(r['user_id'], 'u1');
        expect(r.containsKey('household_id'), isFalse);
      },
    );
    await roundTrip(
      const TasteProfileEntity(),
      UserProfilesCompanion.insert(id: 'u1', profileJson: '{"ljuto":true}'),
      'u1',
      (r) => expect(r, {
        'user_id': 'u1',
        'profile': {'ljuto': true},
      }),
    );
  });

  test('v7: zapis kuvanja, potrošnja iz ostave i ručno brojanje', () async {
    await roundTrip(
      const CookedEventEntity(),
      CookedEventsCompanion.insert(
        id: 'k1',
        householdId: const Value('h1'),
        planEntryId: 'e1',
        mealDate: DateTime.utc(2026, 11, 20),
        mealType: 'lunch',
        actorUserId: 'u1',
        servings: 4,
        cookedAt: t,
        undoneAt: Value(t.add(const Duration(hours: 1))),
        undoReason: const Value('user'),
      ),
      'k1',
      (r) {
        expect(r['meal_date'], '2026-11-20');
        expect(r['actor_user_id'], 'u1');
        expect(r['undone_at'], '2026-10-30T11:05:07.000Z');
        expect(r['undo_reason'], 'user');
      },
    );
    await roundTrip(
      const PantryConsumptionEntity(),
      PantryConsumptionsCompanion.insert(
        id: 'c1',
        householdId: const Value('h1'),
        eventId: 'k1',
        pantryItemId: 'o1',
        baseUnit: 'g',
        micros: 250000000,
        createdAt: t,
      ),
      'c1',
      (r) {
        expect(r['event_id'], 'k1');
        expect(r['micros'], 250000000);
      },
    );
    await roundTrip(
      const PantryItemEntity(),
      PantryItemsCompanion.insert(
        id: 'o9',
        name: 'brašno',
        quantity: const Value(600),
        unit: const Value('g'),
        category: 'ostalo',
        addedAt: t,
        quantitySetAt: Value(t),
        householdId: const Value('h1'),
      ),
      'o9',
      (r) => expect(r['quantity_set_at'], '2026-10-30T10:05:07.000Z'),
    );
  });

  test('registar: svi roditelji uvek pre deteta', () {
    final names = [for (final e in syncEntities) e.name];
    for (final e in syncEntities) {
      for (final p in e.parents) {
        expect(names, contains(p), reason: e.name);
        expect(
          names.indexOf(p),
          lessThan(names.indexOf(e.name)),
          reason: '$p pre ${e.name}',
        );
      }
    }
    expect(names, hasLength(16));
    expect(const CookedEventEntity().parents, ['meal_plan_entry']);
    expect(const PantryConsumptionEntity().parents, [
      'cooked_event',
      'pantry_item',
    ]);
    expect(const SupplyAllocationEntity().parents, [
      'shopping_contribution',
      'pantry_item',
      'shopping_item',
    ]);
    expect(const PantryItemEntity().parents, ['shopping_item']);
    expect(entityByName('recipe'), isA<RecipeEntity>());
    expect(entityByName('nema'), isNull);
  });

  test(
    'v5 kolone: porcije, recept obroka, nedelja liste, poreklo, prijem',
    () async {
      await roundTrip(
        const MealPlanEntity(),
        MealPlansCompanion.insert(
          id: 'p1',
          startDate: DateTime.utc(2026, 11, 2),
          endDate: DateTime.utc(2026, 11, 30),
          mealTypesJson: '["lunch"]',
          createdAt: t,
          defaultServings: const Value(4),
          householdId: const Value('h1'),
        ),
        'p1',
        (r) => expect(r['default_servings'], 4),
      );
      await roundTrip(
        const MealPlanEntryEntity(),
        MealPlanEntriesCompanion.insert(
          id: 'e1',
          planId: 'p1',
          date: DateTime.utc(2026, 11, 3),
          mealType: 'lunch',
          servings: const Value(3),
          recipeSnapshotJson: const Value(
            '{"title":"Sarma","servings":4,"ingredients":[]}',
          ),
          householdId: const Value('h1'),
        ),
        'e1',
        (r) {
          expect(r['servings'], 3);
          expect(r['recipe_snapshot'], {
            'title': 'Sarma',
            'servings': 4,
            'ingredients': <Object?>[],
          });
        },
      );
      await roundTrip(
        const ShoppingListEntity(),
        ShoppingListsCompanion.insert(
          id: 'l1',
          name: 'Nedelja 6',
          createdAt: t,
          mealPlanId: const Value('p1'),
          week: const Value(6),
          periodStart: Value(DateTime.utc(2026, 11, 30)),
          periodEnd: Value(DateTime.utc(2026, 11, 30)),
          householdId: const Value('h1'),
        ),
        'l1',
        (r) {
          expect(r['period_start'], '2026-11-30');
          expect(r['week'], 6);
        },
      );
      final list = (await db.select(db.shoppingLists).get()).single;
      expect(list.periodStart!.toUtc(), DateTime.utc(2026, 11, 30));
      await roundTrip(
        const ShoppingItemEntity(),
        ShoppingItemsCompanion.insert(
          id: 'i1',
          listId: 'l1',
          name: 'kupus',
          category: 'voće i povrće',
          isBought: const Value(true),
          purchaseProvenanceJson: const Value(
            '{"sources":[{"title":"Sarma"}]}',
          ),
          householdId: const Value('h1'),
        ),
        'i1',
        (r) => expect(r['purchase_provenance'], {
          'sources': [
            {'title': 'Sarma'},
          ],
        }),
      );
      await roundTrip(
        const PantryItemEntity(),
        PantryItemsCompanion.insert(
          id: 'o1',
          name: 'kupus',
          category: 'voće i povrće',
          addedAt: t,
          confirmedAt: Value(t),
          sourceShoppingItemId: const Value('i1'),
          householdId: const Value('h1'),
        ),
        'o1',
        (r) {
          expect(r['confirmed_at'], '2026-10-30T10:05:07.000Z');
          expect(r['source_shopping_item_id'], 'i1');
        },
      );
    },
  );

  test('izvor, doprinos i raspodela zalihe', () async {
    await roundTrip(
      const ShoppingSourceEntity(),
      ShoppingSourcesCompanion.insert(
        id: 's1',
        listId: 'l1',
        kind: 'recipePreparation',
        recipeSnapshotJson: const Value('{"title":"Sarma","servings":4}'),
        servings: const Value(2),
        recipeId: const Value('r1'),
        originKey: const Value('r1'),
        closedAt: Value(t),
        createdAt: t,
        householdId: const Value('h1'),
      ),
      's1',
      (r) {
        expect(r['kind'], 'recipePreparation');
        expect(r['plan_entry_id'], isNull);
        expect(r['recipe_snapshot'], {'title': 'Sarma', 'servings': 4});
        expect(r['closed_at'], '2026-10-30T10:05:07.000Z');
        expect(r['superseded_at'], isNull);
      },
    );
    await roundTrip(
      const ShoppingContributionEntity(),
      ShoppingContributionsCompanion.insert(
        id: 'c1',
        sourceId: 's1',
        shoppingItemId: const Value('i1'),
        ingredientKey: 'kupus',
        unitGroup: 'mass',
        baseUnit: 'g',
        micros: const Value(1500000000),
        name: 'Kupus',
        category: 'voće i povrće',
        notesJson: const Value('["kiseli"]'),
        householdId: const Value('h1'),
      ),
      'c1',
      (r) {
        expect(r['micros'], 1500000000);
        expect(r['notes'], ['kiseli']);
      },
    );
    await roundTrip(
      const SupplyAllocationEntity(),
      SupplyAllocationsCompanion.insert(
        id: 'a1',
        contributionId: 'c1',
        purchasedShoppingItemId: const Value('i1'),
        micros: const Value(500000000),
        createdAt: t,
        householdId: const Value('h1'),
      ),
      'a1',
      (r) {
        expect(r.containsKey('supply_id'), isFalse);
        expect(r['purchased_shopping_item_id'], 'i1');
        expect(r['covers_whole_unknown'], isFalse);
      },
    );
    expect((await db.select(db.supplyAllocations).get()).single.supplyId, 'i1');
  });
  test('namirnica i alias: server → lokalno → server bez gubitka', () async {
    await roundTrip(
      const FoodEntity(),
      FoodsCompanion.insert(
        id: 'f1',
        slug: 'jaje',
        name: 'jaje',
        category: 'Mlečni proizvodi i jaja',
        baseUnit: 'piece',
        source: const Value('pregled'),
        kcalPer100g: const Value(143),
        proteinGramsPer100g: const Value(12),
        fatGramsPer100g: const Value(9.5),
        carbsGramsPer100g: const Value(0.7),
        nutritionSource: const Value('USDA FoodData Central'),
        nutritionSourceVersion: const Value('SR Legacy 2018-04'),
        nutritionSourceRef: const Value('FDC 172184'),
        reviewedAt: Value(t),
        withdrawnAt: Value(t),
        createdAt: t,
        updatedAt: t,
      ),
      'f1',
      (r) {
        expect(r['household_id'], isNull);
        expect(r['base_unit'], 'piece');
        expect(r['kcal_per_100g'], 143);
        expect(r['protein_grams_per_100g'], 12);
        expect(r['fat_grams_per_100g'], 9.5);
        expect(r['carbs_grams_per_100g'], 0.7);
        expect(r['nutrition_source'], 'USDA FoodData Central');
        expect(r['nutrition_source_version'], 'SR Legacy 2018-04');
        expect(r['nutrition_source_ref'], 'FDC 172184');
        expect(r['withdrawn_at'], '2026-10-30T10:05:07.000Z');
      },
    );
    await roundTrip(
      const FoodAliasEntity(),
      FoodAliasesCompanion.insert(
        id: 'a1',
        foodId: 'f1',
        householdId: const Value('h1'),
        alias: 'Jaja',
        aliasNormalized: 'jaja',
        createdAt: t,
        updatedAt: t,
      ),
      'a1',
      (r) {
        expect(r['food_id'], 'f1');
        expect(r['household_id'], 'h1');
        expect(r['alias_normalized'], 'jaja');
        expect(r['withdrawn_at'], isNull);
      },
    );
  });

  test(
    'entityByName nalazi entitete kataloga, a syncEntities ih ne sadrži',
    () {
      expect(entityByName('food'), isA<FoodEntity>());
      expect(entityByName('food_alias'), isA<FoodAliasEntity>());
      expect(syncEntities.map((e) => e.name), isNot(contains('food')));
      expect(syncEntities.map((e) => e.name), isNot(contains('food_alias')));
      expect(catalogEntities.map((e) => e.name), ['food', 'food_alias']);
    },
  );
}
