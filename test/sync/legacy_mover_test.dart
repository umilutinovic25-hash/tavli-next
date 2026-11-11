import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/sync/legacy_mover.dart';

void main() {
  late AppDatabase db;
  late LegacyMover mover;
  const a = AccountScope(userId: 'u1', householdId: 'h1');
  const b = AccountScope(userId: 'u2', householdId: 'h2');
  final t = DateTime.utc(2026);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mover = LegacyMover(db, clock: () => t);
  });
  tearDown(() => db.close());

  Future<void> seedLegacy() async {
    for (final id in ['r1', 'r2']) {
      await db
          .into(db.recipes)
          .insert(
            RecipesCompanion.insert(
              id: id,
              title: id,
              servings: 1,
              source: 'manual',
              ingredientsJson: '[]',
              stepsJson: '[]',
              createdAt: t,
              updatedAt: t,
              imagePath: Value(id == 'r1' ? 'recipe_photos/r1.jpg' : null),
            ),
          );
    }
    await db
        .into(db.recipeVersions)
        .insert(
          RecipeVersionsCompanion.insert(
            id: 'v1',
            recipeId: 'r1',
            recipeJson: jsonEncode({'imagePath': 'recipe_photos/stara.jpg'}),
            createdAt: t,
          ),
        );
    await db
        .into(db.shoppingLists)
        .insert(
          ShoppingListsCompanion.insert(id: 'l1', name: 'L', createdAt: t),
        );
    await db
        .into(db.shoppingItems)
        .insert(
          ShoppingItemsCompanion.insert(
            id: 'i1',
            listId: 'l1',
            name: 'mleko',
            category: 'ostalo',
          ),
        );
    await db
        .into(db.ratings)
        .insert(
          RatingsCompanion.insert(
            id: 'g1',
            recipeId: 'r1',
            stars: 5,
            cookedAt: t,
          ),
        );
    await db
        .into(db.userProfiles)
        .insert(UserProfilesCompanion.insert(id: 'legacy', profileJson: '{}'));
  }

  Future<List<String>> outbox() async => [
    for (final e in await (db.select(
      db.syncOutbox,
    )..orderBy([(t) => OrderingTerm.asc(t.seq)])).get())
      '${e.entity}:${e.recordId}:${e.op}',
  ];

  test('prebacuje sve u nalog, roditelj pre deteta, pa slike', () async {
    await seedLegacy();
    expect(await mover.needsMove(), isTrue);
    expect(await mover.moveIfNeeded(a), 7);

    expect(
      (await db.select(db.recipes).get()).every((r) => r.householdId == 'h1'),
      isTrue,
    );
    expect((await db.select(db.recipeVersions).get()).single.householdId, 'h1');
    expect((await db.select(db.shoppingItems).get()).single.householdId, 'h1');
    expect((await db.select(db.ratings).get()).single.userId, 'u1');
    expect((await db.select(db.userProfiles).get()).single.id, 'u1');
    expect(await outbox(), [
      'recipe:r1:upsert',
      'recipe:r2:upsert',
      'recipe_version:v1:upsert',
      'shopping_list:l1:upsert',
      'shopping_item:i1:upsert',
      'rating:g1:upsert',
      'taste_profile:u1:upsert',
      'photo:recipe_photos/r1.jpg:photoUpload',
      'photo:recipe_photos/stara.jpg:photoUpload',
    ]);
    final record = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals(LegacyMover.settingKey))).getSingle();
    expect(jsonDecode(record.value), containsPair('accountId', 'u1'));
  });

  test('drugi put i drugi nalog ne prebacuju ništa', () async {
    await seedLegacy();
    await mover.moveIfNeeded(a);
    final before = await outbox();
    expect(await mover.needsMove(), isFalse);
    expect(await mover.moveIfNeeded(a), 0);
    expect(await mover.moveIfNeeded(b), 0);
    expect(await outbox(), before);
    expect(
      (await db.select(db.recipes).get()).every((r) => r.householdId == 'h1'),
      isTrue,
    );
  });

  test('profil ukusa se prebacuje samo ako ga nalog nema', () async {
    await seedLegacy();
    await db
        .into(db.userProfiles)
        .insert(UserProfilesCompanion.insert(id: 'u1', profileJson: '{"x":1}'));
    await mover.moveIfNeeded(a);
    final profiles = await db.select(db.userProfiles).get();
    expect(profiles.map((p) => p.id), unorderedEquals(['legacy', 'u1']));
    expect(profiles.firstWhere((p) => p.id == 'u1').profileJson, '{"x":1}');
    expect(await outbox(), isNot(contains(startsWith('taste_profile'))));
  });

  test('prekid u sredini ne menja ništa; ponovo se završi celo', () async {
    await seedLegacy();
    mover.beforeFinish = () async => throw StateError('aplikacija ugašena');
    await expectLater(mover.moveIfNeeded(a), throwsStateError);
    expect(
      (await db.select(db.recipes).get()).every((r) => r.householdId == null),
      isTrue,
    );
    expect(await outbox(), isEmpty);
    expect(await mover.needsMove(), isTrue);

    mover.beforeFinish = null;
    expect(await mover.moveIfNeeded(a), 7);
    expect(await outbox(), hasLength(9));
  });

  test('bez lokalnih podataka: 0', () async {
    expect(await mover.needsMove(), isFalse);
    expect(await mover.moveIfNeeded(a), 0);
    expect(await outbox(), isEmpty);
  });

  test('stara lista ostaje cela: kupljeno i ručno, bez nedelja i izvora; '
      'obrok pre liste', () async {
    await db
        .into(db.mealPlans)
        .insert(
          MealPlansCompanion.insert(
            id: 'p1',
            startDate: t,
            endDate: t,
            mealTypesJson: '["lunch"]',
            createdAt: t,
          ),
        );
    await db
        .into(db.mealPlanEntries)
        .insert(
          MealPlanEntriesCompanion.insert(
            id: 'e1',
            planId: 'p1',
            date: t,
            mealType: 'lunch',
          ),
        );
    await db
        .into(db.shoppingLists)
        .insert(
          ShoppingListsCompanion.insert(
            id: 'l1',
            name: 'Stara',
            createdAt: t,
            mealPlanId: const Value('p1'),
            week: const Value(5),
          ),
        );
    for (final (id, bought, manual) in [
      ('kupljeno', true, false),
      ('rucno', false, true),
    ]) {
      await db
          .into(db.shoppingItems)
          .insert(
            ShoppingItemsCompanion.insert(
              id: id,
              listId: 'l1',
              name: id,
              category: 'ostalo',
              isBought: Value(bought),
              isManual: Value(manual),
            ),
          );
    }
    expect(await mover.moveIfNeeded(a), 5);

    final list = (await db.select(db.shoppingLists).get()).single;
    expect(list.id, 'l1');
    expect(list.week, 5);
    expect(list.periodStart, isNull);
    final items = {
      for (final i in await db.select(db.shoppingItems).get()) i.id: i,
    };
    expect(items['kupljeno']!.isBought, isTrue);
    expect(items['rucno']!.isManual, isTrue);
    expect(items.values.every((i) => i.householdId == 'h1'), isTrue);
    expect(await db.select(db.shoppingSources).get(), isEmpty);
    expect(await db.select(db.shoppingContributions).get(), isEmpty);
    expect(await outbox(), [
      'meal_plan:p1:upsert',
      'meal_plan_entry:e1:upsert',
      'shopping_list:l1:upsert',
      'shopping_item:kupljeno:upsert',
      'shopping_item:rucno:upsert',
    ]);
  });

  test('zajednički katalog namirnica se ne prebacuje u nalog', () async {
    await db
        .into(db.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'f_jaje',
            name: 'jaje',
            category: 'mlečni proizvodi i jaja',
            baseUnit: 'kom',
          ),
        );
    await db
        .into(db.foodAliases)
        .insert(
          FoodAliasesCompanion.insert(
            id: 'a1',
            foodId: 'f_jaje',
            alias: 'jaja',
          ),
        );
    expect(await mover.needsMove(), isFalse);
    expect(await mover.moveIfNeeded(a), 0);
    expect((await db.select(db.foods).get()).single.householdId, isNull);
    expect((await db.select(db.foodAliases).get()).single.householdId, isNull);
    expect(await db.select(db.syncOutbox).get(), isEmpty);
  });
}
