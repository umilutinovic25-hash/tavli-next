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
    expect(names, hasLength(12));
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
          expect(r['kind'], 'cook');
          expect(r['away_reason'], isNull);
        },
      );
      await roundTrip(
        const MealPlanEntryEntity(),
        MealPlanEntriesCompanion.insert(
          id: 'e2',
          planId: 'p1',
          date: DateTime.utc(2026, 11, 4),
          mealType: 'lunch',
          kind: const Value('away'),
          awayReason: const Value('restaurant'),
          awayNote: const Value('sa kolegama'),
          householdId: const Value('h1'),
        ),
        'e2',
        (r) {
          expect(r['kind'], 'away');
          expect(r['away_reason'], 'restaurant');
          expect(r['away_note'], 'sa kolegama');
          expect(r['recipe_snapshot'], isNull);
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
          expect(r['period_start'], '2026-11-30T00:00:00.000Z');
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
}
