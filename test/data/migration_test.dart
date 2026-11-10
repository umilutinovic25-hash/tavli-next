import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/data/database.dart';

import '../helpers/v3_schema.dart';
import '../helpers/v4_schema.dart';

void main() {
  test('postojeća v4 struktura označena kao v3 čuva id-jeve i outbox pri otvaranju', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tavli-migration-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final before = AppDatabase(NativeDatabase(file));
    await before.customStatement(
      "INSERT INTO recipes (id, title, servings, source, ingredients_json, steps_json, created_at, updated_at, household_id) VALUES ('recipe-kept', 'Test recept', 2, 'manual', '[]', '[]', 1, 2, 'home-kept')",
    );
    await before.customStatement(
      "INSERT INTO recipe_versions (id, recipe_id, recipe_json, created_at, household_id) VALUES ('version-kept', 'recipe-kept', '{}', 1, 'home-kept')",
    );
    await before.customStatement(
      "INSERT INTO shopping_lists (id, name, created_at, household_id) VALUES ('list-kept', 'Test lista', 1, 'home-kept')",
    );
    await before.customStatement(
      "INSERT INTO shopping_items (id, list_id, name, category, household_id) VALUES ('item-kept', 'list-kept', 'Test sastojak', 'ostalo', 'home-kept')",
    );
    await before.customStatement(
      "INSERT INTO user_profiles (id, profile_json) VALUES ('user-kept', '{}')",
    );
    await before.customStatement(
      "INSERT INTO sync_outbox (account_id, entity, record_id, op, created_at) VALUES ('user-kept', 'recipe_version', 'version-kept', 'upsert', 1), ('user-kept', 'shopping_item', 'item-kept', 'upsert', 1)",
    );
    await before.customStatement(
      "INSERT INTO app_settings (key, value) VALUES ('theme', 'borovnica')",
    );
    await before.customStatement('PRAGMA user_version = 3');
    await before.close();

    final after = AppDatabase(NativeDatabase(file));
    addTearDown(after.close);
    expect(
      (await after.select(after.appSettings).get()).single.value,
      'borovnica',
    );
    expect(
      (await after.select(after.recipeVersions).get()).single.id,
      'version-kept',
    );
    expect(
      (await after.select(after.shoppingItems).get()).single.id,
      'item-kept',
    );
    expect(
      (await after.select(after.userProfiles).get()).single.id,
      'user-kept',
    );
    expect(
      (await after.select(after.recipes).get()).single.householdId,
      'home-kept',
    );
    expect(
      (await after.select(after.syncOutbox).get()).map((row) => row.recordId),
      ['version-kept', 'item-kept'],
    );
    expect(
      (await after.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      after.schemaVersion,
    );
  });

  test('migracija 2 → 3 dodaje vrstu izmene i model, a čuva verzije', () async {
    final executor = NativeDatabase.memory(
      setup: (raw) {
        raw.execute(
          'CREATE TABLE recipe_versions (id INTEGER PRIMARY KEY, '
          'recipe_id TEXT NOT NULL, recipe_json TEXT NOT NULL, '
          'instruction TEXT, created_at INTEGER NOT NULL)',
        );
        raw.execute(
          'INSERT INTO recipe_versions (recipe_id, recipe_json, instruction, '
          "created_at) VALUES ('r1', '{}', 'bez luka', 0)",
        );
        raw.execute('PRAGMA user_version = 2');
      },
    );
    final db = AppDatabase(executor);
    addTearDown(db.close);

    final rows = await db.select(db.recipeVersions).get();
    expect(rows.single.instruction, 'bez luka');
    expect(rows.single.changeKind, 'ai');
    expect(rows.single.changedBy, isNull);
  });

  test('migracija 3 → 4 čuva sve redove, daje tekstualne id-jeve i nove tabele', () async {
    final executor = NativeDatabase.memory(
      setup: (raw) {
        for (final s in v3Schema) {
          raw.execute(s);
        }
        raw.execute(
          "INSERT INTO recipes VALUES ('r1', 'Sarma', 4, 60, 'manual', '[]', "
          "'[]', 'recipe_photos/a.jpg', NULL, 1, 2)",
        );
        raw.execute(
          "INSERT INTO recipes VALUES ('r2', 'Pasulj', 2, NULL, 'ai', '[]', "
          "'[]', NULL, 'Gemini', 1, 2)",
        );
        for (var i = 0; i < 3; i++) {
          raw.execute(
            'INSERT INTO recipe_versions (recipe_id, recipe_json, change_kind, '
            "created_at) VALUES ('r1', '{}', 'ai', $i)",
          );
        }
        raw.execute(
          'INSERT INTO recipe_versions (recipe_id, recipe_json, change_kind, '
          "created_at) VALUES ('r2', '{}', 'manual', 9)",
        );
        raw.execute(
          "INSERT INTO pantry_items (name, category, added_at) VALUES ('so', 'ostalo', 1)",
        );
        raw.execute(
          "INSERT INTO shopping_lists VALUES ('l1', 'Lista', 'p1', 1, 1)",
        );
        raw.execute(
          'INSERT INTO shopping_items (list_id, name, category) '
          "VALUES ('l1', 'mleko', 'ostalo'), ('l1', 'hleb', 'pekara')",
        );
        raw.execute(
          "INSERT INTO meal_plans VALUES ('p1', 1, 2, '[\"lunch\"]', 1, 1)",
        );
        raw.execute(
          'INSERT INTO meal_plan_entries (plan_id, date, meal_type, recipe_id) '
          "VALUES ('p1', 1, 'lunch', 'r1'), ('p1', 2, 'dinner', NULL)",
        );
        raw.execute(
          'INSERT INTO ratings (recipe_id, stars, cooked_at) '
          "VALUES ('r1', 5, 1)",
        );
        raw.execute("INSERT INTO user_profiles VALUES (1, '{\"ljuto\":true}')");
        raw.execute("INSERT INTO app_settings VALUES ('theme', 'dark')");
        raw.execute(
          "INSERT INTO model_statuses (provider, model) VALUES ('gemini', 'm')",
        );
        raw.execute('PRAGMA user_version = 3');
      },
    );
    final db = AppDatabase(executor);
    addTearDown(db.close);

    expect(db.schemaVersion, 13);

    final recipes = await db.select(db.recipes).get();
    expect(recipes.map((r) => r.id), unorderedEquals(['r1', 'r2']));
    expect(recipes.every((r) => r.householdId == null), isTrue);
    expect(
      recipes.firstWhere((r) => r.id == 'r1').imagePath,
      'recipe_photos/a.jpg',
    );

    final versions = await db.select(db.recipeVersions).get();
    expect(versions, hasLength(4));
    expect(versions.map((v) => v.id).toSet(), hasLength(4));
    expect(versions.where((v) => v.recipeId == 'r1'), hasLength(3));
    expect(
      versions.every((v) => RegExp(r'^[0-9a-f]{32}$').hasMatch(v.id)),
      isTrue,
    );
    expect(versions.every((v) => v.householdId == null), isTrue);

    final items = await db.select(db.shoppingItems).get();
    expect(items.map((i) => i.name), unorderedEquals(['mleko', 'hleb']));
    expect(
      items.every((i) => i.listId == 'l1' && i.householdId == null),
      isTrue,
    );
    expect(items.map((i) => i.id).toSet(), hasLength(2));

    final lists = await db.select(db.shoppingLists).get();
    expect(lists.single.householdId, isNull);
    expect(lists.single.mealPlanId, 'p1');

    final entries = await db.select(db.mealPlanEntries).get();
    expect(entries, hasLength(2));
    expect(entries.where((e) => e.recipeId == 'r1'), hasLength(1));
    expect(entries.every((e) => e.planId == 'p1'), isTrue);

    expect((await db.select(db.mealPlans).get()).single.householdId, isNull);
    final pantry = (await db.select(db.pantryItems).get()).single;
    expect(pantry.name, 'so');
    expect(pantry.householdId, isNull);

    final rating = (await db.select(db.ratings).get()).single;
    expect(rating.recipeId, 'r1');
    expect(rating.userId, isNull);

    final profile = (await db.select(db.userProfiles).get()).single;
    expect(profile.id, 'legacy');
    expect(profile.profileJson, '{"ljuto":true}');

    expect((await db.select(db.appSettings).get()).single.value, 'dark');
    expect(await db.select(db.modelStatuses).get(), hasLength(1));
    expect(await db.select(db.accounts).get(), isEmpty);
    expect(await db.select(db.syncOutbox).get(), isEmpty);
    expect(await db.select(db.syncCursors).get(), isEmpty);
  });

  test('migracija 4 → 5 čuva redove i id-jeve, dodaje porcije, nedelje i '
      'tabele nabavke', () async {
    final executor = NativeDatabase.memory(
      setup: (raw) {
        for (final s in v4Schema) {
          raw.execute(s);
        }
        raw.execute(
          "INSERT INTO recipes VALUES ('r1', 'Sarma', 4, 60, 'manual', "
          '\'[{"name":"kupus","quantity":1,"unit":"kom"}]\', \'["Kuvati."]\', '
          "NULL, NULL, 1, 2, 'h1')",
        );
        raw.execute(
          "INSERT INTO meal_plans VALUES ('p1', 1, 2, '[\"lunch\"]', 1, 1, 'h1')",
        );
        raw.execute(
          'INSERT INTO meal_plan_entries (id, plan_id, date, meal_type, '
          "recipe_id, household_id) VALUES ('e1', 'p1', 1, 'lunch', 'r1', 'h1'), "
          "('e2', 'p1', 2, 'dinner', NULL, 'h1')",
        );
        raw.execute(
          "INSERT INTO shopping_lists VALUES ('l1', 'Lista', 'p1', 5, 1, 'h1')",
        );
        raw.execute(
          'INSERT INTO shopping_items (id, list_id, name, category, is_bought, '
          "is_manual, household_id) VALUES ('i1', 'l1', 'mleko', 'ostalo', 1, 0, "
          "'h1'), ('i2', 'l1', 'hleb', 'pekara', 0, 1, 'h1')",
        );
        raw.execute(
          'INSERT INTO pantry_items (id, name, category, added_at, household_id) '
          "VALUES ('o1', 'so', 'ostalo', 1, 'h1')",
        );
        raw.execute(
          'INSERT INTO sync_outbox (account_id, entity, record_id, op, '
          "created_at) VALUES ('u1', 'shopping_item', 'i2', 'upsert', 1)",
        );
        raw.execute('PRAGMA user_version = 4');
      },
    );
    final db = AppDatabase(executor);
    addTearDown(db.close);

    final entries = {
      for (final e in await db.select(db.mealPlanEntries).get()) e.id: e,
    };
    expect(entries.keys, unorderedEquals(['e1', 'e2']));
    expect(entries['e1']!.servings, isNull);
    final snapshot =
        jsonDecode(entries['e1']!.recipeSnapshotJson!) as Map<String, Object?>;
    expect(snapshot['title'], 'Sarma');
    expect(snapshot['servings'], 4);
    expect(snapshot['steps'], ['Kuvati.']);
    expect(
      (snapshot['ingredients']! as List).single,
      containsPair('name', 'kupus'),
    );
    expect(entries['e2']!.recipeSnapshotJson, isNull);

    expect((await db.select(db.mealPlans).get()).single.defaultServings, 2);

    // Stara lista se ne deli na nedelje.
    final list = (await db.select(db.shoppingLists).get()).single;
    expect(list.week, 5);
    expect(list.periodStart, isNull);
    expect(list.periodEnd, isNull);

    final items = {
      for (final i in await db.select(db.shoppingItems).get()) i.id: i,
    };
    expect(items['i1']!.isBought, isTrue);
    expect(items['i2']!.isManual, isTrue);
    expect(items.values.every((i) => i.purchaseProvenanceJson == null), isTrue);

    final pantry = (await db.select(db.pantryItems).get()).single;
    expect(pantry.id, 'o1');
    expect(pantry.confirmedAt, isNull);
    expect(pantry.sourceShoppingItemId, isNull);

    expect(await db.select(db.shoppingSources).get(), isEmpty);
    expect(await db.select(db.shoppingContributions).get(), isEmpty);
    expect(await db.select(db.supplyAllocations).get(), isEmpty);
    expect((await db.select(db.syncOutbox).get()).single.recordId, 'i2');

    // Prijem jedne kupovine je jedinstven; nova tabela prima redove.
    await db.customStatement(
      "UPDATE pantry_items SET source_shopping_item_id = 'i1'",
    );
    await expectLater(
      db.customStatement(
        'INSERT INTO pantry_items (id, name, category, added_at, '
        "source_shopping_item_id) VALUES ('o2', 'mleko', 'ostalo', 1, 'i1')",
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('ponovljena v5 migracija (user_version vraćen na 4) ne pada', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v5-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement(
      'INSERT INTO shopping_lists (id, name, created_at, period_start) '
      "VALUES ('l1', 'Nedelja 1', 1, 1)",
    );
    await first.customStatement('PRAGMA user_version = 4');
    await first.close();

    final again = AppDatabase(NativeDatabase(file));
    addTearDown(again.close);
    expect((await again.select(again.shoppingLists).get()).single.id, 'l1');
    expect(await again.select(again.shoppingSources).get(), isEmpty);
  });

  test('migracija 5 → 13 dodaje vreme recepta i vreme po danu', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v13-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final before = AppDatabase(NativeDatabase(file));
    await before.customStatement(
      'INSERT INTO recipes (id, title, servings, prep_minutes, source, '
      'ingredients_json, steps_json, created_at, updated_at) VALUES '
      "('r1', 'Pasulj', 4, 15, 'manual', '[]', '[]', 1, 2)",
    );
    for (final c in ['active_minutes', 'total_minutes']) {
      await before.customStatement('ALTER TABLE recipes DROP COLUMN $c');
    }
    await before.customStatement('DROP TABLE day_time_budgets');
    await before.customStatement('PRAGMA user_version = 5');
    await before.close();

    final after = AppDatabase(NativeDatabase(file));
    addTearDown(after.close);
    final r = (await after.select(after.recipes).get()).single;
    expect(r.prepMinutes, 15);
    expect(r.activeMinutes, isNull);
    expect(r.totalMinutes, isNull);
    expect(await after.select(after.dayTimeBudgets).get(), isEmpty);
  });

  test('ponovljena v13 migracija ne pada', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v13b-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement('PRAGMA user_version = 12');
    await first.close();

    final again = AppDatabase(NativeDatabase(file));
    addTearDown(again.close);
    expect(await again.select(again.dayTimeBudgets).get(), isEmpty);
  });
}
