import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/features/foods/allergen_line.dart';
import 'package:tavli/features/recipes/ai_preview.dart';
import 'package:tavli/features/recipes/recipe_form_screen.dart';
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

  group('alergije članova (039)', () {
    Future<void> allergic(String codes) => db
        .into(db.memberAllergies)
        .insert(
          MemberAllergiesCompanion.insert(
            id: 'h1:u2',
            householdId: const Value('h1'),
            userId: 'u2',
            codesJson: Value(codes),
          ),
        );

    Future<void> pumpWidget(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            accountScopeProvider.overrideWithValue(_scope),
          ],
          child: MaterialApp(home: Scaffold(body: child)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testDbWidgets('detalj: alergen člana je istaknut', (tester) async {
      await allergic('["eggs"]');
      await pump(
        tester,
        recipeWith(const [
          Ingredient(name: 'jaja', foodId: 'f_jaje'),
          Ingredient(name: 'so', foodId: 'f_so'),
        ]),
      );
      expect(find.text('Sadrži alergen člana: jaja'), findsOneWidget);
      expect(find.text('Nepotvrđeno, proveri alergene'), findsNothing);
    });

    for (final width in [320.0, 1200.0]) {
      testDbWidgets('poznati alergen ne skriva nepotvrđen sastojak ($width)', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await allergic('["eggs"]');
        await pumpWidget(
          tester,
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: AllergenLine(
              recipeWith(const [
                Ingredient(name: 'jaja', foodId: 'f_jaje'),
                Ingredient(name: 'tajni začin'),
              ]),
            ),
          ),
        );
        expect(find.text('Sadrži alergen člana: jaja'), findsOneWidget);
        expect(find.text('Nepotvrđeno, proveri alergene'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testDbWidgets(
      'detalj: uz alergije i nepotvrđen sastojak → „Nepotvrđeno, proveri alergene“',
      (tester) async {
        await allergic('["nuts"]');
        await pump(
          tester,
          recipeWith(const [Ingredient(name: 'pesto đenoveze')]),
        );
        expect(find.text('Nepotvrđeno, proveri alergene'), findsOneWidget);
        expect(find.text('Podaci o alergenima nisu potpuni.'), findsNothing);
        expect(find.textContaining('Sadrži alergen člana'), findsNothing);
      },
    );

    testDbWidgets('bez alergija u domaćinstvu nema upozorenja člana', (
      tester,
    ) async {
      await pump(
        tester,
        recipeWith(const [Ingredient(name: 'jaja', foodId: 'f_jaje')]),
      );
      expect(find.textContaining('alergen člana'), findsNothing);
      expect(find.text('Nepotvrđeno, proveri alergene'), findsNothing);
    });

    testDbWidgets('pregled AI recepta (foto/naziv) pokazuje upozorenje', (
      tester,
    ) async {
      await allergic('["eggs"]');
      await pumpWidget(
        tester,
        AiRecipePreview(
          recipe: recipeWith(const [
            Ingredient(name: 'jaja', foodId: 'f_jaje'),
          ]),
          onSave: () {},
          onRetry: () {},
          onDiscard: () {},
        ),
      );
      expect(find.text('Sadrži alergen člana: jaja'), findsOneWidget);
    });

    testDbWidgets(
      'uvoz sa linka: forma pokazuje upozorenje i dozvoljava čuvanje',
      (tester) async {
        await allergic('["eggs"]');
        final draft = Recipe(
          id: 'u',
          title: 'Uvezeno',
          servings: 2,
          ingredients: const [Ingredient(name: 'jaja', foodId: 'f_jaje')],
          source: RecipeSource.url,
          sourceUrl: 'https://primer.rs/recept',
          createdAt: DateTime(2026, 11),
        );
        await pumpWidget(tester, RecipeFormScreen(draft: draft));
        expect(find.text('Sadrži alergen člana: jaja'), findsOneWidget);
        expect(find.text('Sačuvaj'), findsOneWidget);
      },
    );
  });
}
