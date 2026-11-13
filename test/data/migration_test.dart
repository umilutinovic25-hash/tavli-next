import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/data/database.dart';

import '../helpers/v3_schema.dart';
import '../helpers/v4_schema.dart';

void main() {
  test('migracija 18 → 19 čuva stavku i dodaje izbor proizvoda', () async {
    final dir = await Directory.systemTemp.createTemp('tavli-v18-price-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/cache.sqlite');
    final before = AppDatabase(NativeDatabase(file));
    await before.customStatement(
      "INSERT INTO shopping_lists (id, name, created_at, household_id) VALUES ('l', 'Lista', 1, 'home')",
    );
    await before.customStatement(
      "INSERT INTO shopping_items (id, list_id, name, category, household_id) VALUES ('i', 'l', 'Mleko', 'ostalo', 'home')",
    );
    await before.customStatement(
      'ALTER TABLE shopping_items DROP COLUMN price_selection_json',
    );
    await before.customStatement('PRAGMA user_version = 18');
    await before.close();
    final after = AppDatabase(NativeDatabase(file));
    addTearDown(after.close);
    final row = (await after.select(after.shoppingItems).get()).single;
    expect(row.name, 'Mleko');
    expect(row.priceSelectionJson, isNull);
    expect(after.schemaVersion, 22);
  });

  test('migracija 19 → 20 dodaje oznaku približno doprinosu', () async {
    final dir = await Directory.systemTemp.createTemp('tavli-v19-approx-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/cache.sqlite');
    final before = AppDatabase(NativeDatabase(file));
    await before.customStatement(
      'ALTER TABLE shopping_contributions DROP COLUMN approximate',
    );
    await before.customStatement(
      'ALTER TABLE shopping_items DROP COLUMN approximate',
    );
    await before.customStatement('PRAGMA user_version = 19');
    await before.close();
    final after = AppDatabase(NativeDatabase(file));
    addTearDown(after.close);
    for (final table in ['shopping_contributions', 'shopping_items']) {
      final columns = await after
          .customSelect('PRAGMA table_info($table)')
          .get();
      final approximate = columns.singleWhere(
        (c) => c.read<String>('name') == 'approximate',
      );
      expect(approximate.read<int>('notnull'), 1, reason: table);
      expect(approximate.read<String>('dflt_value'), '0', reason: table);
    }
    expect(after.schemaVersion, 22);
  });

  test('migracija 20 → 21 dodaje nutritivne kolone namirnici', () async {
    final dir = await Directory.systemTemp.createTemp('tavli-v20-nutrition-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/cache.sqlite');
    final before = AppDatabase(NativeDatabase(file));
    await before.customStatement(
      "INSERT INTO foods (id, name, category, base_unit) VALUES ('f_jaje', 'jaje', 'ostalo', 'kom')",
    );
    for (final c in [
      'kcal100',
      'protein100',
      'fat100',
      'carbs100',
      'nutrition_source',
      'nutrition_ref',
    ]) {
      await before.customStatement('ALTER TABLE foods DROP COLUMN $c');
    }
    await before.customStatement('PRAGMA user_version = 20');
    await before.close();
    final after = AppDatabase(NativeDatabase(file));
    addTearDown(after.close);
    final row = (await after.select(after.foods).get()).single;
    expect(row.name, 'jaje');
    expect(row.kcal100, isNull);
    expect(row.nutritionSource, isNull);
    expect(after.schemaVersion, 22);
  });

  test('migracija 21 → 22 dodaje težinu jedinice namirnici', () async {
    final dir = await Directory.systemTemp.createTemp('tavli-v21-weight-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/cache.sqlite');
    final before = AppDatabase(NativeDatabase(file));
    await before.customStatement(
      "INSERT INTO foods (id, name, category, base_unit) VALUES ('f_jaje', 'jaje', 'ostalo', 'kom')",
    );
    for (final c in ['unit_grams', 'unit_grams_source']) {
      await before.customStatement('ALTER TABLE foods DROP COLUMN $c');
    }
    await before.customStatement('PRAGMA user_version = 21');
    await before.close();
    final after = AppDatabase(NativeDatabase(file));
    addTearDown(after.close);
    final row = (await after.select(after.foods).get()).single;
    expect(row.name, 'jaje');
    expect(row.unitGrams, isNull);
    expect(row.unitGramsSource, isNull);
    expect(after.schemaVersion, 22);
  });

  test('migracija 5 → 14 čuva podatke i pravi tabelu šablona', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tavli-v5-template-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final before = AppDatabase(NativeDatabase(file));
    await before.customStatement(
      "INSERT INTO meal_plans (id, start_date, end_date, meal_types_json, created_at, household_id) VALUES ('kept', 1, 2, '[\"lunch\"]', 1, 'home')",
    );
    await before.customStatement('DROP TABLE week_templates');
    await before.customStatement('PRAGMA user_version = 5');
    await before.close();
    final after = AppDatabase(NativeDatabase(file));
    addTearDown(after.close);
    expect((await after.select(after.mealPlans).get()).single.id, 'kept');
    expect(await after.select(after.weekTemplates).get(), isEmpty);
    expect(
      (await after.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      after.schemaVersion,
    );
  });

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
    await before.customStatement('DROP TABLE week_templates');
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

    expect(db.schemaVersion, 22);

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

  test('migracija 5 → 7 čuva recepte i dodaje izvor', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v7-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement(
      "INSERT INTO recipes (id, title, servings, source, ingredients_json, steps_json, created_at, updated_at) VALUES ('r', 'Pita', 2, 'manual', '[]', '[]', 1, 1)",
    );
    await first.customStatement('ALTER TABLE recipes DROP COLUMN source_url');
    await first.customStatement('PRAGMA user_version = 5');
    await first.close();
    final after = AppDatabase(NativeDatabase(file));
    addTearDown(after.close);
    final row = (await after.select(after.recipes).get()).single;
    expect(row.title, 'Pita');
    expect(row.sourceUrl, isNull);
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
  test(
    'migracija 5 → 6 čuva postojeće podatke i pravi tabelu pretraga',
    () async {
      final directory = await Directory.systemTemp.createTemp('tavli-v6-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/cache.sqlite');
      final first = AppDatabase(NativeDatabase(file));
      await first.customStatement(
        "INSERT INTO app_settings (key, value) VALUES ('theme', 'dark')",
      );
      await first.customStatement('DROP TABLE saved_recipe_searches');
      await first.customStatement('PRAGMA user_version = 5');
      await first.close();
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);
      expect(
        (await upgraded.select(upgraded.appSettings).get()).single.value,
        'dark',
      );
      expect(
        await upgraded.select(upgraded.savedRecipeSearches).get(),
        isEmpty,
      );
    },
  );
  for (final version in [5, 6]) {
    test(
      'migracija $version → 14 čuva pretrage i dodaje izvor recepta',
      () async {
        final dir = await Directory.systemTemp.createTemp('tavli-url-merge-');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/cache.sqlite');
        final before = AppDatabase(NativeDatabase(file));
        await before.customStatement(
          "INSERT INTO recipes (id, title, servings, source, ingredients_json, steps_json, created_at, updated_at) VALUES ('r', 'Pita', 2, 'manual', '[]', '[]', 1, 1)",
        );
        await before.customStatement(
          'ALTER TABLE recipes DROP COLUMN source_url',
        );
        if (version == 5) {
          await before.customStatement('DROP TABLE saved_recipe_searches');
        } else {
          await before.customStatement(
            "INSERT INTO saved_recipe_searches (id, user_id, name, query, include_ingredient, exclude_ingredient) VALUES ('s', 'u', 'Brzo', 'pita', '', '')",
          );
        }
        await before.customStatement('PRAGMA user_version = $version');
        await before.close();
        final after = AppDatabase(NativeDatabase(file));
        addTearDown(after.close);
        expect(
          (await after.select(after.recipes).get()).single.sourceUrl,
          isNull,
        );
        final searches = await after.select(after.savedRecipeSearches).get();
        expect(searches.length, version == 5 ? 0 : 1);
        if (version == 6) expect(searches.single.name, 'Brzo');
      },
    );
  }
  for (final version in [5, 6]) {
    test('migracija $version → 14 čuva pretrage i uvodi šablone', () async {
      final dir = await Directory.systemTemp.createTemp('tavli-week-merge-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/cache.sqlite');
      final before = AppDatabase(NativeDatabase(file));
      await before.customStatement(
        "INSERT INTO app_settings (key, value) VALUES ('theme', 'dark')",
      );
      await before.customStatement('DROP TABLE week_templates');
      if (version == 5) {
        await before.customStatement('DROP TABLE saved_recipe_searches');
      } else {
        await before.customStatement(
          "INSERT INTO saved_recipe_searches (id, user_id, name, query, include_ingredient, exclude_ingredient) VALUES ('s', 'u', 'Brzo', 'pita', '', '')",
        );
      }
      await before.customStatement('PRAGMA user_version = $version');
      await before.close();
      final after = AppDatabase(NativeDatabase(file));
      addTearDown(after.close);
      expect(await after.select(after.weekTemplates).get(), isEmpty);
      final searches = await after.select(after.savedRecipeSearches).get();
      expect(searches.length, version == 5 ? 0 : 1);
      if (version == 6) expect(searches.single.name, 'Brzo');
    });
  }
  test('v5 migracija čuva stavke i dodaje prazne detalje', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v9-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final before = AppDatabase(NativeDatabase(file));
    await before.customStatement(
      "INSERT INTO shopping_lists (id, name, created_at, household_id) VALUES ('l', 'Lista', 1, 'h')",
    );
    await before.customStatement(
      "INSERT INTO shopping_items (id, list_id, name, quantity, unit, category, household_id) VALUES ('i', 'l', 'Mleko', 2, 'l', 'ostalo', 'h')",
    );
    await before.customStatement(
      'ALTER TABLE shopping_items DROP COLUMN brand',
    );
    await before.customStatement('ALTER TABLE shopping_items DROP COLUMN note');
    await before.customStatement(
      'ALTER TABLE shopping_items DROP COLUMN photo_path',
    );
    await before.customStatement('PRAGMA user_version = 5');
    await before.close();
    final after = AppDatabase(NativeDatabase(file));
    addTearDown(after.close);
    final item = (await after.select(after.shoppingItems).get()).single;
    expect(item.name, 'Mleko');
    expect(item.quantity, 2);
    expect(item.unit, 'l');
    expect(item.brand, isNull);
    expect(item.note, isNull);
    expect(item.photoPath, isNull);
  });

  test(
    'migracija 5 → 11 dodaje red „Uskoro kuvam“ i čuva postojeće redove',
    () async {
      final directory = await Directory.systemTemp.createTemp('tavli-v10-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/cache.sqlite');
      final before = AppDatabase(NativeDatabase(file));
      await before.customStatement(
        'INSERT INTO recipes (id, title, servings, source, ingredients_json, '
        "steps_json, created_at, updated_at, household_id) VALUES ('r1', "
        "'Sarma', 4, 'manual', '[]', '[]', 1, 2, 'h1')",
      );
      await before.customStatement('DROP TABLE cook_soon_items');
      await before.customStatement('PRAGMA user_version = 5');
      await before.close();

      final after = AppDatabase(NativeDatabase(file));
      addTearDown(after.close);
      expect((await after.select(after.recipes).get()).single.id, 'r1');
      await after.customStatement(
        'INSERT INTO cook_soon_items (id, household_id, recipe_id, '
        'recipe_snapshot_json, servings, position, created_at) VALUES '
        "('q1', 'h1', 'r1', '{}', 4, 0, 1)",
      );
      expect((await after.select(after.cookSoonItems).get()).single.id, 'q1');
    },
  );

  test('ponovljena v10 migracija (tabela već postoji) ne pada', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v10b-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement(
      'INSERT INTO cook_soon_items (id, recipe_snapshot_json, servings, '
      "position, created_at) VALUES ('q1', '{}', 2, 0, 1)",
    );
    await first.customStatement('PRAGMA user_version = 9');
    await first.close();

    final again = AppDatabase(NativeDatabase(file));
    addTearDown(again.close);
    expect((await again.select(again.cookSoonItems).get()).single.id, 'q1');
  });

  test(
    'migracija 5 → 13 dodaje vrstu obroka; stari obroci se kuvaju',
    () async {
      final directory = await Directory.systemTemp.createTemp('tavli-v11-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/cache.sqlite');
      final before = AppDatabase(NativeDatabase(file));
      await before.customStatement(
        'INSERT INTO meal_plans (id, start_date, end_date, meal_types_json, '
        "created_at) VALUES ('p1', 1, 1, '[\"lunch\"]', 1)",
      );
      await before.customStatement(
        'INSERT INTO meal_plan_entries (id, plan_id, date, meal_type) '
        "VALUES ('e1', 'p1', 1, 'lunch')",
      );
      for (final c in ['kind', 'away_reason', 'away_note']) {
        await before.customStatement(
          'ALTER TABLE meal_plan_entries DROP COLUMN $c',
        );
      }
      await before.customStatement('PRAGMA user_version = 5');
      await before.close();

      final after = AppDatabase(NativeDatabase(file));
      addTearDown(after.close);
      final e = (await after.select(after.mealPlanEntries).get()).single;
      expect(e.id, 'e1');
      expect(e.kind, 'cook');
      expect(e.awayReason, isNull);
    },
  );

  test('ponovljena v11 migracija (kolone već postoje) ne pada', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v11b-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement('PRAGMA user_version = 10');
    await first.close();

    final again = AppDatabase(NativeDatabase(file));
    addTearDown(again.close);
    expect(await again.select(again.mealPlanEntries).get(), isEmpty);
  });

  test('migracija 5 → 12 dodaje zapis veza; recepti ostaju isti', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v12-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final before = AppDatabase(NativeDatabase(file));
    await before.customStatement(
      'INSERT INTO recipes (id, title, servings, source, ingredients_json, '
      "steps_json, created_at, updated_at) VALUES ('r1', 'Sarma', 4, "
      """'manual', '[{"name":"kupus"}]', '["Kuvati."]', 1, 2)""",
    );
    await before.customStatement(
      'ALTER TABLE recipes DROP COLUMN step_links_json',
    );
    await before.customStatement('PRAGMA user_version = 5');
    await before.close();

    final after = AppDatabase(NativeDatabase(file));
    addTearDown(after.close);
    final r = (await after.select(after.recipes).get()).single;
    expect(r.stepsJson, '["Kuvati."]');
    expect(r.stepLinksJson, isNull);
  });

  test('ponovljena v12 migracija (kolona već postoji) ne pada', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v12b-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement('PRAGMA user_version = 11');
    await first.close();

    final again = AppDatabase(NativeDatabase(file));
    addTearDown(again.close);
    expect(await again.select(again.recipes).get(), isEmpty);
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

  test('migracija 5 → 14 dodaje pravila i izuzetke; obroci ostaju', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v14-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final before = AppDatabase(NativeDatabase(file));
    await before.customStatement(
      'INSERT INTO meal_plans (id, start_date, end_date, meal_types_json, '
      """created_at) VALUES ('p1', 1, 1, '["lunch"]', 1)""",
    );
    await before.customStatement(
      'INSERT INTO meal_plan_entries (id, plan_id, date, meal_type) '
      "VALUES ('e1', 'p1', 1, 'lunch')",
    );
    await before.customStatement(
      'ALTER TABLE meal_plan_entries DROP COLUMN rule_overrides_json',
    );
    await before.customStatement('DROP TABLE day_rules');
    await before.customStatement('PRAGMA user_version = 5');
    await before.close();

    final after = AppDatabase(NativeDatabase(file));
    addTearDown(after.close);
    final e = (await after.select(after.mealPlanEntries).get()).single;
    expect(e.id, 'e1');
    expect(e.ruleOverridesJson, isNull);
    expect(await after.select(after.dayRules).get(), isEmpty);
  });

  test('ponovljena v14 migracija ne pada', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v14b-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement('PRAGMA user_version = 13');
    await first.close();

    final again = AppDatabase(NativeDatabase(file));
    addTearDown(again.close);
    expect(await again.select(again.dayRules).get(), isEmpty);
  });

  test(
    'migracija 14 → 15 dodaje preferencije ishrane; pravila ostaju',
    () async {
      final directory = await Directory.systemTemp.createTemp('tavli-v15-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/cache.sqlite');
      final before = AppDatabase(NativeDatabase(file));
      await before.customStatement(
        'INSERT INTO day_rules (id, household_id, weekday, kind, mode, '
        "created_at) VALUES ('d1', 'h1', 1, 'vegetarian', 'required', 1)",
      );
      await before.customStatement('DROP TABLE household_preferences');
      await before.customStatement('PRAGMA user_version = 14');
      await before.close();

      final after = AppDatabase(NativeDatabase(file));
      addTearDown(after.close);
      expect((await after.select(after.dayRules).get()).single.id, 'd1');
      expect(await after.select(after.householdPreferences).get(), isEmpty);
      expect(
        (await after.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        after.schemaVersion,
      );
    },
  );

  test('ponovljena v15 migracija ne pada', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v15b-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement('PRAGMA user_version = 14');
    await first.close();

    final again = AppDatabase(NativeDatabase(file));
    addTearDown(again.close);
    expect(await again.select(again.householdPreferences).get(), isEmpty);
  });

  test('migracija 15 → 16 dodaje keš domaćinstava; nalog ostaje', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v16-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final before = AppDatabase(NativeDatabase(file));
    await before.customStatement(
      'INSERT INTO accounts (user_id, email, household_id, household_name, '
      "role, created_at) VALUES ('u1', 'a@b.c', 'h1', 'Moje', 'owner', 1)",
    );
    await before.customStatement('DROP TABLE household_memberships');
    await before.customStatement('DROP TABLE household_member_cache');
    await before.customStatement(
      'ALTER TABLE accounts DROP COLUMN preferred_household_id',
    );
    await before.customStatement('PRAGMA user_version = 15');
    await before.close();

    final after = AppDatabase(NativeDatabase(file));
    addTearDown(after.close);
    final account = (await after.select(after.accounts).get()).single;
    expect(account.userId, 'u1');
    expect(account.householdId, 'h1');
    expect(account.preferredHouseholdId, isNull);
    expect(await after.select(after.householdMemberships).get(), isEmpty);
    expect(await after.select(after.householdMemberCache).get(), isEmpty);
    expect(
      (await after.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      after.schemaVersion,
    );
  });

  test('ponovljena v16 migracija ne pada', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v16b-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement('PRAGMA user_version = 15');
    await first.close();

    final again = AppDatabase(NativeDatabase(file));
    addTearDown(again.close);
    expect(await again.select(again.householdMemberships).get(), isEmpty);
  });

  test('migracija 16 → 17 dodaje katalog namirnica; redovi ostaju', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v17-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final before = AppDatabase(NativeDatabase(file));
    await before.customStatement(
      'INSERT INTO pantry_items (id, name, quantity, unit, category, added_at, '
      "household_id) VALUES ('p1', 'jaja', 2, 'kom', 'ostalo', 1, 'h1')",
    );
    await before.customStatement(
      "INSERT INTO shopping_lists (id, name, created_at, household_id) VALUES ('l1', 'Lista', 1, 'h1')",
    );
    await before.customStatement(
      'INSERT INTO shopping_items (id, list_id, name, category, household_id) '
      "VALUES ('s1', 'l1', 'jaje', 'ostalo', 'h1')",
    );
    for (final t in [
      'foods',
      'food_aliases',
      'food_conversions',
      'food_allergens',
    ]) {
      await before.customStatement('DROP TABLE $t');
    }
    await before.customStatement(
      'ALTER TABLE pantry_items DROP COLUMN food_id',
    );
    await before.customStatement(
      'ALTER TABLE shopping_items DROP COLUMN food_id',
    );
    await before.customStatement('PRAGMA user_version = 16');
    await before.close();

    final after = AppDatabase(NativeDatabase(file));
    addTearDown(after.close);
    final pantry = (await after.select(after.pantryItems).get()).single;
    expect((pantry.name, pantry.quantity, pantry.foodId), ('jaja', 2.0, null));
    final item = (await after.select(after.shoppingItems).get()).single;
    expect((item.name, item.foodId), ('jaje', null));
    expect(await after.select(after.foods).get(), isEmpty);
    expect(await after.select(after.foodAliases).get(), isEmpty);
    expect(await after.select(after.foodConversions).get(), isEmpty);
    expect(await after.select(after.foodAllergens).get(), isEmpty);
    expect(
      (await after.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      after.schemaVersion,
    );
  });

  test('ponovljena v17 migracija ne pada', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v17b-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement('PRAGMA user_version = 16');
    await first.close();

    final again = AppDatabase(NativeDatabase(file));
    addTearDown(again.close);
    expect(await again.select(again.foods).get(), isEmpty);
  });

  test(
    'migracija 17 → 18 dodaje alergije po osobi; preferencije ostaju',
    () async {
      final directory = await Directory.systemTemp.createTemp('tavli-v18-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/cache.sqlite');
      final before = AppDatabase(NativeDatabase(file));
      await before.customStatement(
        'INSERT INTO household_preferences (id, household_id, allergies_json) '
        "VALUES ('h1', 'h1', '[\"kikiriki\"]')",
      );
      await before.customStatement('DROP TABLE member_allergies');
      await before.customStatement('PRAGMA user_version = 17');
      await before.close();

      final after = AppDatabase(NativeDatabase(file));
      addTearDown(after.close);
      expect(
        (await after.select(after.householdPreferences).get()).single.id,
        'h1',
      );
      expect(await after.select(after.memberAllergies).get(), isEmpty);
      expect(
        (await after.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        22,
      );
    },
  );

  test('ponovljena v18 migracija ne pada', () async {
    final directory = await Directory.systemTemp.createTemp('tavli-v18b-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cache.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement('PRAGMA user_version = 17');
    await first.close();

    final again = AppDatabase(NativeDatabase(file));
    addTearDown(again.close);
    expect(await again.select(again.memberAllergies).get(), isEmpty);
  });
}
