import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/domain/recipe.dart';

import '../../helpers/food_seed.dart';
import '../../helpers/test_app.dart';

void main() {
  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> addIngredient(
    WidgetTester tester, {
    required String name,
    String quantity = '',
    String unit = '',
  }) async {
    await tapButton(tester, 'Dodaj sastojak');
    final dialog = find.byType(AlertDialog);
    Finder dialogField(String label) => find.descendant(
      of: dialog,
      matching: find.widgetWithText(TextField, label),
    );
    await tester.enterText(dialogField('Naziv'), name);
    await tester.enterText(dialogField('Količina'), quantity);
    await tester.enterText(dialogField('Jedinica'), unit);
    await tester.pump();
    await tester.tap(find.descendant(of: dialog, matching: button('Sačuvaj')));
    await tester.pumpAndSettle();
  }

  testTavli('bez naziva i sastojaka ništa se ne čuva', (tester) async {
    final app = await pumpTavli(tester, location: '/recipes/new/manual');

    await tester.tap(find.text('Sačuvaj'));
    await tester.pumpAndSettle();

    expect(find.text('Unesi naziv recepta.'), findsOneWidget);
    expect(find.text('Dodaj bar jedan sastojak.'), findsOneWidget);
    expect(await app.titles(), isEmpty);
  });

  testTavli('ručni unos novog recepta', (tester) async {
    final app = await pumpTavli(tester, location: '/recipes/new/manual');

    await tester.enterText(field('Naziv'), 'Kajgana');
    await tester.enterText(field('Broj porcija'), '1');
    await tester.enterText(field('Vreme pripreme (min)'), '10');
    await addIngredient(tester, name: 'jaja', quantity: '3', unit: 'kom');
    await addIngredient(tester, name: 'mleko', quantity: '0,5', unit: 'dl');
    expect(find.text('0,5 dl mleko'), findsOneWidget);
    await tester.enterText(
      field('Koraci pripreme (jedan po redu)'),
      'Umutiti jaja.\n\nPeći.',
    );
    await tester.tap(find.text('Sačuvaj'));
    await tester.pumpAndSettle();

    final row = await app.db.select(app.db.recipes).getSingle();
    expect(row.title, 'Kajgana');
    expect(row.servings, 1);
    expect(row.prepMinutes, 10);
    expect(row.source, 'manual');
    expect(row.stepsJson, '["Umutiti jaja.","Peći."]');
    expect(find.widgetWithText(AppBar, 'Kajgana'), findsOneWidget);
    expect(find.text('Ručno unet'), findsOneWidget);
  });

  testTavli('izmena čuva prethodnu verziju kao ručnu izmenu', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/a',
      recipes: [sampleRecipe('a', 'Sarma')],
    );

    await tester.tap(find.byTooltip('Izmeni'));
    await tester.pumpAndSettle();
    expect(find.text('Izmeni recept'), findsOneWidget);
    await tester.enterText(field('Naziv'), 'Posna sarma');
    await tester.tap(find.text('Sačuvaj'));
    await tester.pumpAndSettle();

    expect(await app.titles(), ['Posna sarma']);
    final version = await app.db.select(app.db.recipeVersions).getSingle();
    expect(version.changeKind, 'manual');

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Još opcija'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prethodne verzije'));
    await tester.pumpAndSettle();
    expect(find.text('Ručna izmena'), findsOneWidget);
  });

  testTavli('potvrda namirnice sastojka: foodId, tekst isti, nova verzija, '
      'snimak plana netaknut', (tester) async {
    final recipe = Recipe(
      id: 'a',
      title: 'Omlet',
      servings: 2,
      ingredients: const [
        Ingredient(id: 'i1', name: 'jajca domaća', quantity: 3, unit: 'kom'),
      ],
      source: RecipeSource.manual,
      createdAt: DateTime(2026, 11),
    );
    const snapshot = '{"title":"Omlet","servings":2,"ingredients":[]}';
    final app = await pumpTavli(
      tester,
      location: '/recipes/a',
      recipes: [recipe],
      setup: (db) async {
        await seedEggs(db);
        await db
            .into(db.mealPlans)
            .insert(
              MealPlansCompanion.insert(
                id: 'p',
                startDate: DateTime(2026, 11, 9),
                endDate: DateTime(2026, 11, 15),
                mealTypesJson: '["lunch"]',
                createdAt: DateTime(2026, 11),
              ),
            );
        await db
            .into(db.mealPlanEntries)
            .insert(
              MealPlanEntriesCompanion.insert(
                id: 'e',
                planId: 'p',
                date: DateTime(2026, 11, 10),
                mealType: 'lunch',
                recipeId: const Value('a'),
                recipeSnapshotJson: const Value(snapshot),
              ),
            );
      },
    );

    await tester.tap(find.byTooltip('Izmeni'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nepotvrđeno'), findsOneWidget);
    await tester.tap(find.text('3 kom jajca domaća'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Nepotvrđeno')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Nepotvrđeno')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Pretraži namirnice'),
      'jaj',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'jaje'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: dialog, matching: find.text('jaje')),
      findsOneWidget,
    );
    // Kategorija sastojka preuzeta iz namirnice; osoba je i dalje menja.
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('mlečni proizvodi i jaja'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: dialog, matching: button('Sačuvaj')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nepotvrđeno'), findsNothing);
    await tester.tap(find.text('Sačuvaj'));
    await tester.pumpAndSettle();

    final row = await app.db.select(app.db.recipes).getSingle();
    final saved = (jsonDecode(row.ingredientsJson) as List).single as Map;
    expect(saved['foodId'], 'f_jaje');
    expect(saved['name'], 'jajca domaća');
    expect(saved['quantity'], 3);
    expect(saved['category'], 'mlečni proizvodi i jaja');
    expect(saved['id'], 'i1');
    final version = await app.db.select(app.db.recipeVersions).getSingle();
    expect(version.changeKind, 'manual');
    expect(version.recipeJson, isNot(contains('f_jaje')));
    final entry = await app.db.select(app.db.mealPlanEntries).getSingle();
    expect(entry.recipeSnapshotJson, snapshot);
  });

  testTavli('izmena sastojka bez izbora čuva postojeću namirnicu', (
    tester,
  ) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/a',
      setup: seedEggs,
      recipes: [
        Recipe(
          id: 'a',
          title: 'Omlet',
          servings: 2,
          ingredients: const [
            Ingredient(id: 'i1', name: 'moja jaja', foodId: 'f_jaje'),
          ],
          source: RecipeSource.manual,
          createdAt: DateTime(2026, 11),
        ),
      ],
    );
    await tester.tap(find.byTooltip('Izmeni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('moja jaja'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextField, 'Količina'),
      ),
      '2',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: button('Sačuvaj'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sačuvaj'));
    await tester.pumpAndSettle();
    final row = await app.db.select(app.db.recipes).getSingle();
    final saved = (jsonDecode(row.ingredientsJson) as List).single as Map;
    expect(saved['foodId'], 'f_jaje');
    expect(saved['quantity'], 2);
  });

  group('AI predlog nove namirnice (SC-005)', () {
    Recipe aiRecipe(RecipeSource source) => Recipe(
      id: 'a',
      title: 'Voćna salata',
      servings: 2,
      ingredients: const [
        Ingredient(
          id: 'i1',
          name: 'zmajevo voće',
          quantity: 200,
          unit: 'g',
          category: 'voće i povrće',
        ),
        Ingredient(id: 'i2', name: 'jaja', quantity: 2, unit: 'kom'),
      ],
      source: source,
      createdAt: DateTime(2026, 11),
    );

    Future<TestApp> open(WidgetTester tester, RecipeSource source) async {
      final app = await pumpTavli(
        tester,
        location: '/recipes/a',
        recipes: [aiRecipe(source)],
        setup: seedEggs,
      );
      await tester.tap(find.byTooltip('Izmeni'));
      await tester.pumpAndSettle();
      return app;
    }

    Future<Map<String, Object?>> savedIngredient(
      TestApp app,
      String name,
    ) async {
      final row = await app.db.select(app.db.recipes).getSingle();
      return (jsonDecode(row.ingredientsJson) as List)
          .cast<Map<String, Object?>>()
          .firstWhere((i) => i['name'] == name);
    }

    testTavli('Odbaci: katalog isti, sastojak ostaje nepotvrđen', (
      tester,
    ) async {
      final app = await open(tester, RecipeSource.ai);
      // Sastojak koji katalog prepoznaje nema predlog.
      expect(
        find.text('AI predlaže novu namirnicu: „zmajevo voće“.'),
        findsOneWidget,
      );
      expect(find.textContaining('„jaja“'), findsNothing);
      await tapButton(tester, 'Odbaci');
      expect(find.textContaining('AI predlaže'), findsNothing);
      await tapButton(tester, 'Sačuvaj');
      expect(await app.db.select(app.db.foods).get(), hasLength(1));
      expect((await savedIngredient(app, 'zmajevo voće'))['foodId'], isNull);
      expect((await savedIngredient(app, 'jaja'))['foodId'], 'f_jaje');
    });

    testTavli('Potvrdi: jedna sopstvena namirnica aktivnog domaćinstva', (
      tester,
    ) async {
      final app = await open(tester, RecipeSource.photo);
      await tapButton(tester, 'Potvrdi');
      final name = find.widgetWithText(TextField, 'Naziv namirnice');
      expect(tester.widget<TextField>(name).controller!.text, 'zmajevo voće');
      await tapButton(tester, 'Sačuvaj kao moju namirnicu');
      expect(find.textContaining('AI predlaže'), findsNothing);
      await tapButton(tester, 'Sačuvaj');

      final account = await app.db.select(app.db.accounts).getSingle();
      final own = await (app.db.select(
        app.db.foods,
      )..where((f) => f.householdId.isNotNull())).get();
      expect(own, hasLength(1));
      expect(own.single.householdId, account.householdId);
      expect(own.single.baseUnit, 'g');
      expect(
        (await savedIngredient(app, 'zmajevo voće'))['foodId'],
        own.single.id,
      );
    });

    testTavli('ručni recept nema predlog', (tester) async {
      await open(tester, RecipeSource.manual);
      expect(find.textContaining('AI predlaže'), findsNothing);
    });
  });

  testTavli('izlazak sa nesačuvanim izmenama pita za potvrdu', (tester) async {
    await pumpTavli(
      tester,
      location: '/recipes/a',
      recipes: [sampleRecipe('a', 'Sarma')],
    );
    await tester.tap(find.byTooltip('Izmeni'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Naziv'), 'Nešto drugo');
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Odbaciti izmene?'), findsOneWidget);

    await tester.tap(find.text('Nastavi uređivanje'));
    await tester.pumpAndSettle();
    expect(find.text('Izmeni recept'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Odbaci'));
    await tester.pumpAndSettle();
    expect(find.text('Izmeni recept'), findsNothing);
    expect(find.widgetWithText(AppBar, 'Sarma'), findsOneWidget);
  });

  testTavli('brisanje uz potvrdu', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/a',
      recipes: [sampleRecipe('a', 'Sarma')],
    );

    await tester.tap(find.byTooltip('Još opcija'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obriši recept'));
    await tester.pumpAndSettle();
    expect(find.text('Obrisati „Sarma“?'), findsOneWidget);

    await tester.tap(find.text('Otkaži'));
    await tester.pumpAndSettle();
    expect(await app.titles(), ['Sarma']);

    await tester.tap(find.byTooltip('Još opcija'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obriši recept'));
    await tester.pumpAndSettle();
    await tester.tap(button('Obriši'));
    await tester.pumpAndSettle();

    expect(await app.titles(), isEmpty);
    expect(find.text('Recept je obrisan.'), findsOneWidget);
    expect(find.text('Još nema recepata'), findsOneWidget);
  });
}
