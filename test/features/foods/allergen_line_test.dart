import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/features/foods/allergen_line.dart';
import 'package:tavli/providers.dart';

import '../../helpers/test_app.dart';

const _scope = AccountScope(userId: 'u1', householdId: 'h1');

Future<void> seedFoods(AppDatabase db) async {
  for (final (id, name, allergen) in [
    ('f_jaje', 'jaje', 'eggs'),
    ('f_psenicno_brasno', 'pšenično brašno', 'gluten'),
    ('f_so', 'so', null),
  ]) {
    await db
        .into(db.foods)
        .insert(
          FoodsCompanion.insert(
            id: id,
            name: name,
            category: 'ostalo',
            baseUnit: 'g',
          ),
        );
    if (allergen != null) {
      await db
          .into(db.foodAllergens)
          .insert(
            FoodAllergensCompanion.insert(
              id: '$id:$allergen',
              foodId: id,
              allergenCode: allergen,
            ),
          );
    }
  }
}

Recipe recipeWith(List<Ingredient> items) => Recipe(
  id: 'a',
  title: 'Palačinke',
  servings: 2,
  ingredients: items,
  source: RecipeSource.manual,
  createdAt: DateTime(2026, 11),
);

/// Nijedan tekst na ekranu ne tvrdi da recept nema alergene.
void expectNoAllergenFreeClaim(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase());
  expect(texts.where((t) => t.contains('bez alergena')), isEmpty);
}

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
        child: MaterialApp(home: Scaffold(body: AllergenLine(recipe))),
      ),
    );
    await tester.pumpAndSettle();
  }

  testDbWidgets('jaje + brašno → „Sadrži: jaja, gluten“', (tester) async {
    await pump(
      tester,
      recipeWith(const [
        Ingredient(name: 'brašno', foodId: 'f_psenicno_brasno'),
        Ingredient(name: 'jaja', foodId: 'f_jaje'),
      ]),
    );
    expect(find.text('Sadrži: gluten, jaja'), findsOneWidget);
    expect(find.text('Podaci o alergenima nisu potpuni.'), findsNothing);
    expectNoAllergenFreeClaim(tester);
  });

  testDbWidgets('nepotvrđen sastojak → „nisu potpuni“ uz poznate oznake', (
    tester,
  ) async {
    await pump(
      tester,
      recipeWith(const [
        Ingredient(name: 'jaja', foodId: 'f_jaje'),
        Ingredient(name: 'tajni začin'),
      ]),
    );
    expect(find.text('Sadrži: jaja'), findsOneWidget);
    expect(find.text('Podaci o alergenima nisu potpuni.'), findsOneWidget);
    expectNoAllergenFreeClaim(tester);
  });

  testDbWidgets('sve potvrđeno bez oznaka → nikakva tvrdnja', (tester) async {
    await pump(
      tester,
      recipeWith(const [Ingredient(name: 'so', foodId: 'f_so')]),
    );
    expect(find.textContaining('Sadrži'), findsNothing);
    expect(find.textContaining('alergen'), findsNothing);
    expectNoAllergenFreeClaim(tester);
  });

  testTavli('detalj recepta prikazuje oznake ispod sastojaka', (tester) async {
    await pumpTavli(
      tester,
      location: '/recipes/a',
      setup: seedFoods,
      recipes: [
        recipeWith(const [
          Ingredient(name: 'jaja', foodId: 'f_jaje'),
          Ingredient(name: 'mleko'),
        ]),
      ],
    );
    expect(find.text('Sadrži: jaja'), findsOneWidget);
    expect(find.text('Podaci o alergenima nisu potpuni.'), findsOneWidget);
    expectNoAllergenFreeClaim(tester);
    // Samo nepotvrđen sastojak (mleko) nosi oznaku (FR-014).
    expect(find.byTooltip('Nepotvrđeno'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byTooltip('Nepotvrđeno'),
        matching: find.byType(Row),
      ),
      findsWidgets,
    );
  });
}
