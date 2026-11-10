import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/personal_export.dart';
import 'package:tavli/domain/account.dart';

final _at = DateTime.utc(2026, 11, 10, 9, 30);

const _account = Account(
  userId: 'u1',
  email: 'ana@tavli.test',
  displayName: 'Ana Petrović',
  householdId: 'h1',
  householdName: 'Dom',
  role: 'owner',
);

RecipeRow _recipeRow({String id = 'r1', String? householdId = 'h1'}) =>
    RecipeRow(
      id: id,
      title: 'Sarma',
      servings: 4,
      prepMinutes: 90,
      source: 'manual',
      ingredientsJson: '[{"name":"kupus","quantity":"1"}]',
      stepsJson: '["Kuvati."]',
      imagePath: 'recipe_photos/abc.jpg',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026, 2),
      householdId: householdId,
    );

void main() {
  test('prazan izvor: sve sekcije postoje i prazne liste su prazne', () {
    final export = buildPersonalExport(
      exportedAt: _at,
      email: 'ana@tavli.test',
    );

    expect(export['formatVersion'], personalExportFormatVersion);
    expect(export['exportedAt'], '2026-11-10T09:30:00.000Z');
    expect(export['account'], {'email': 'ana@tavli.test', 'displayName': null});
    final sections = export['sections']! as Map<String, Object?>;
    expect(sections.keys, [
      'recipes',
      'mealPlans',
      'mealPlanEntries',
      'shoppingLists',
      'shoppingItems',
      'pantryItems',
      'savedRecipeSearches',
      'dayRules',
      'dayTimeBudgets',
    ]);
    for (final list in sections.values) {
      expect(list, isEmpty);
    }
  });

  test('recept: JSON kolone su objekti, slika je samo putanja', () {
    final export = buildPersonalExport(
      exportedAt: _at,
      email: _account.email,
      recipes: [_recipeRow()],
    );
    final recipes = (export['sections']! as Map)['recipes']! as List<Object?>;
    final recipe = recipes.single! as Map<String, Object?>;

    expect(recipe['title'], 'Sarma');
    expect(recipe['ingredients'], [
      {'name': 'kupus', 'quantity': '1'},
    ]);
    expect(recipe['steps'], ['Kuvati.']);
    expect(recipe['imagePath'], 'recipe_photos/abc.jpg');
    expect(recipe['stepLinks'], isNull);
    expect(recipe['createdAt'], '2026-01-01T00:00:00.000Z');
  });

  test('izvoz ne sadrži AI ključeve, tokene ni podešavanja', () {
    final export = buildPersonalExport(
      exportedAt: _at,
      email: _account.email,
      recipes: [_recipeRow()],
    );
    final text = jsonEncode(export);

    for (final forbidden in [
      'api_key',
      'apiKey',
      'AIza',
      'gsk_',
      'sk-or-',
      'Bearer',
      'access_token',
      'refresh_token',
      'secret',
    ]) {
      expect(text, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('collectPersonalExport: samo podaci domaćinstva i naloga', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.recipes)
        .insert(
          RecipesCompanion.insert(
            id: 'mine',
            title: 'Moj recept',
            servings: 2,
            source: 'manual',
            ingredientsJson: '[]',
            stepsJson: '[]',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            householdId: const Value('h1'),
          ),
        );
    await db
        .into(db.recipes)
        .insert(
          RecipesCompanion.insert(
            id: 'tuđi',
            title: 'Tuđi recept',
            servings: 2,
            source: 'manual',
            ingredientsJson: '[]',
            stepsJson: '[]',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            householdId: const Value('h2'),
          ),
        );
    await db
        .into(db.savedRecipeSearches)
        .insert(
          SavedRecipeSearchesCompanion.insert(
            id: 's1',
            userId: 'u1',
            name: 'Brzo',
            query: '',
            includeIngredient: '',
            excludeIngredient: '',
          ),
        );
    await db
        .into(db.savedRecipeSearches)
        .insert(
          SavedRecipeSearchesCompanion.insert(
            id: 's2',
            userId: 'u2',
            name: 'Tuđa',
            query: '',
            includeIngredient: '',
            excludeIngredient: '',
          ),
        );
    // Podešavanja aplikacije nisu deo izvoza.
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(key: 'gemini_key', value: 'AIza-test'),
        );

    final export = await collectPersonalExport(db, _account, clock: () => _at);
    final sections = export['sections']! as Map<String, Object?>;
    final recipes = sections['recipes']! as List<Object?>;
    final searches = sections['savedRecipeSearches']! as List<Object?>;

    expect(recipes.map((r) => (r! as Map)['id']), ['mine']);
    expect(searches.map((s) => (s! as Map)['id']), ['s1']);
    expect(jsonEncode(export), isNot(contains('AIza-test')));
    expect(jsonEncode(export), isNot(contains('gemini_key')));
  });

  test('writePersonalExportFile upisuje JSON sa datumom u imenu', () async {
    final dir = Directory.systemTemp.createTempSync('tavli_izvoz_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final export = buildPersonalExport(
      exportedAt: _at,
      email: _account.email,
      recipes: [_recipeRow()],
    );

    final file = await writePersonalExportFile(export, dir);

    expect(file.path, startsWith(dir.path));
    expect(
      file.uri.pathSegments.last,
      matches(r'^tavli-izvoz-\d{4}-\d{2}-\d{2}\.json$'),
    );
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, Object?>;
    expect(decoded['formatVersion'], personalExportFormatVersion);
    expect(decoded['sections'], export['sections']);
  });
}
