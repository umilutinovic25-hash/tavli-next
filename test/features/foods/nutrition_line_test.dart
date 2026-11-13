import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/features/foods/nutrition_line.dart';
import 'package:tavli/providers.dart';

import '../../helpers/test_app.dart';

const _scope = AccountScope(userId: 'u1', householdId: 'h1');

Future<void> seedFoods(AppDatabase db) async {
  await db
      .into(db.foods)
      .insert(
        FoodsCompanion.insert(
          id: 'f_krompir',
          name: 'krompir',
          category: 'ostalo',
          baseUnit: 'g',
          kcal100: const Value(77),
          protein100: const Value(2),
          fat100: const Value(0.1),
          carbs100: const Value(17),
          nutritionSource: const Value('usda-sr-legacy-2018-04'),
          nutritionRef: const Value('170026'),
        ),
      );
  await db
      .into(db.foods)
      .insert(
        FoodsCompanion.insert(
          id: 'f_kajmak',
          name: 'kajmak',
          category: 'ostalo',
          baseUnit: 'g',
        ),
      );
}

Recipe recipeWith(List<Ingredient> items, {int servings = 2}) => Recipe(
  id: 'a',
  title: 'Krompir',
  servings: servings,
  ingredients: items,
  source: RecipeSource.manual,
  createdAt: DateTime(2026, 11),
);

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedFoods(db);
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, Recipe recipe) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          accountScopeProvider.overrideWithValue(_scope),
        ],
        child: MaterialApp(home: Scaffold(body: NutritionLine(recipe))),
      ),
    );
    await tester.pumpAndSettle();
  }

  testDbWidgets('vrednost po porciji i pokrivenost', (tester) async {
    await pump(
      tester,
      recipeWith(const [
        Ingredient(
          name: 'krompir',
          foodId: 'f_krompir',
          quantity: 200,
          unit: 'g',
        ),
        Ingredient(name: 'kajmak', foodId: 'f_kajmak', quantity: 50, unit: 'g'),
        Ingredient(name: 'tajni začin'),
      ]),
    );
    expect(
      find.text(
        'Po porciji ~77 kcal · proteini 2 g · masti 0,1 g · ugljeni hidrati 17 g',
      ),
      findsOneWidget,
    );
    expect(find.text('Računato za 1 od 3 sastojka.'), findsOneWidget);
  });

  testDbWidgets('ništa pokriveno: ne prikazuje ništa umesto pogrešnog broja', (
    tester,
  ) async {
    await pump(
      tester,
      recipeWith(const [
        Ingredient(name: 'kajmak', foodId: 'f_kajmak', quantity: 50, unit: 'g'),
        Ingredient(name: 'tajni začin'),
      ]),
    );
    expect(find.textContaining('kcal'), findsNothing);
    expect(find.textContaining('Računato'), findsNothing);
  });

  testTavli('detalj recepta prikazuje vrednost po porciji ispod sastojaka', (
    tester,
  ) async {
    await pumpTavli(
      tester,
      location: '/recipes/a',
      setup: seedFoods,
      recipes: [
        recipeWith(const [
          Ingredient(
            name: 'krompir',
            foodId: 'f_krompir',
            quantity: 200,
            unit: 'g',
          ),
        ]),
      ],
    );
    expect(find.textContaining('Po porciji ~77 kcal'), findsOneWidget);
    expect(find.text('Računato za 1 od 1 sastojka.'), findsOneWidget);
  });
}
