import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/use_first.dart';
import 'package:tavli/features/recipes/recipe_providers.dart';
import 'package:tavli/features/use_first/use_first_screen.dart';

import '../../helpers/test_app.dart';

final now = DateTime.utc(2026, 11, 10, 12);
Recipe recipe(String id, String title, List<Ingredient> ingredients) => Recipe(
  id: id,
  title: title,
  servings: 2,
  ingredients: ingredients,
  steps: const ['Skuvaj.'],
  source: RecipeSource.manual,
  createdAt: now,
);
final cabbage = recipe('cabbage', 'Kupus sa pirinčem', const [
  Ingredient(name: 'kupus', quantity: 600, unit: 'g'),
  Ingredient(name: 'pirinač', quantity: 100, unit: 'g'),
]);
final milk = recipe('milk', 'Mleko na šporetu', const [
  Ingredient(name: 'mleko', quantity: 1, unit: 'l'),
]);

Future<void> openSelection(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Potroši ove 3 namirnice'));
  await tester.tap(find.text('Potroši ove 3 namirnice'));
  await tester.pumpAndSettle();
}

Future<void> addIngredient(WidgetTester tester, String name) async {
  final input = find.byKey(const ValueKey('quick-ingredient-name'));
  await tester.ensureVisible(input);
  await tester.enterText(input, name);
  await tapButton(tester, 'Dodaj u izbor');
}

void main() {
  testTavli(
    'brzi izbor bez Ostave ne upisuje podatke i poštuje porcije/filtere',
    (tester) async {
      final app = await pumpTavli(
        tester,
        location: '/use-first',
        size: const Size(600, 1800),
        recipes: [cabbage, milk],
        overrides: [
          clockProvider.overrideWithValue(() => now),
          suggestionStockProvider.overrideWith(
            (ref) => Stream.value(<PantryStock>[]),
          ),
        ],
      );
      final beforeRecipes = await app.db.select(app.db.recipes).get();
      final beforeOutbox = await app.db.select(app.db.syncOutbox).get();
      await openSelection(tester);
      await addIngredient(tester, 'kupus');
      expect(find.text('Kupus sa pirinčem'), findsOneWidget);
      expect(find.text('Mleko na šporetu'), findsNothing);
      expect(find.text('Koristi 1/1 izabranih namirnica'), findsOneWidget);
      expect(
        find.text('Proveri količinu: kupus · za recept 600 g'),
        findsOneWidget,
      );
      expect(find.text('Sve poznate količine su dostupne'), findsNothing);
      await tester.ensureVisible(find.byTooltip('Više porcija'));
      await tester.tap(find.byTooltip('Više porcija'));
      await tester.pumpAndSettle();
      expect(
        find.text('Proveri količinu: kupus · za recept 900 g'),
        findsOneWidget,
      );
      await tester.tap(find.text('Mogu sada'));
      await tester.pumpAndSettle();
      expect(find.text('Kupus sa pirinčem'), findsNothing);
      await addIngredient(tester, 'pirinač');
      expect(find.text('Kupus sa pirinčem'), findsOneWidget);
      expect(find.text('Koristi 2/2 izabranih namirnica'), findsOneWidget);
      await tester.ensureVisible(find.text('Nedostaju 1–2 sastojka'));
      await tester.tap(find.text('Nedostaju 1–2 sastojka'));
      await tester.pumpAndSettle();
      expect(find.text('Kupus sa pirinčem'), findsNothing);
      await tapButton(tester, 'Obriši izbor');
      expect(find.text('Otvori Ostavu'), findsOneWidget);
      expect(await app.db.select(app.db.pantryItems).get(), isEmpty);
      expect(await app.db.select(app.db.shoppingItems).get(), isEmpty);
      expect(await app.db.select(app.db.recipes).get(), beforeRecipes);
      expect(await app.db.select(app.db.syncOutbox).get(), beforeOutbox);
    },
  );

  testTavli('unos odbija prazno i sinonim duplikata; tri izbora i uklanjanje', (
    tester,
  ) async {
    await pumpTavli(
      tester,
      location: '/use-first',
      size: const Size(600, 1800),
      recipes: [cabbage],
      overrides: [
        suggestionStockProvider.overrideWith(
          (ref) => Stream.value(<PantryStock>[]),
        ),
      ],
    );
    await openSelection(tester);
    await tapButton(tester, 'Dodaj u izbor');
    expect(find.text('Unesi naziv namirnice.'), findsOneWidget);
    await addIngredient(tester, 'beli luk');
    await addIngredient(tester, 'Češnjak');
    expect(find.text('Ova namirnica je već izabrana.'), findsOneWidget);
    expect(find.byType(InputChip), findsOneWidget);
    await addIngredient(tester, 'kupus');
    await addIngredient(tester, 'pirinač');
    expect(find.byType(InputChip), findsNWidgets(3));
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('quick-ingredient-name')),
          )
          .enabled,
      isFalse,
    );
    await tester.ensureVisible(find.byTooltip('Ukloni beli luk'));
    await tester.tap(find.byTooltip('Ukloni beli luk'));
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNWidgets(2));
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('quick-ingredient-name')),
          )
          .enabled,
      isTrue,
    );
    await addIngredient(tester, 'mleko');
    expect(find.byType(InputChip), findsNWidgets(3));
  });

  testTavli(
    'izbor čuva pretragu, prikazuje prazan rezultat i otvara postojeći recept',
    (tester) async {
      await pumpTavli(
        tester,
        location: '/use-first',
        size: const Size(600, 1800),
        recipes: [cabbage, milk],
        overrides: [
          suggestionStockProvider.overrideWith(
            (ref) => Stream.value(<PantryStock>[]),
          ),
        ],
      );
      await openSelection(tester);
      await addIngredient(tester, 'bundeva');
      expect(
        find.text(
          'Nema recepata sa izabranim namirnicama. Promeni izbor ili dodaj recept u zbirku.',
        ),
        findsOneWidget,
      );
      await tapButton(tester, 'Obriši izbor');
      await addIngredient(tester, 'kupus');
      final search = find.byKey(const ValueKey('suggestion-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'nema');
      await tester.pumpAndSettle();
      expect(
        find.text('Nema predloga za izabranu pretragu i filter.'),
        findsOneWidget,
      );
      await tester.enterText(search, 'kupus');
      await tester.pumpAndSettle();
      await tapButton(tester, 'Otvori recept');
      expect(find.text('Skuvaj.'), findsOneWidget);
    },
  );

  for (final width in [320.0, 1200.0]) {
    testTavli('brz izbor na $width px, tamna tema i tekst 2×', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpTavli(
        tester,
        location: '/use-first',
        size: Size(width, 1400),
        recipes: [cabbage],
        settings: {'theme': 'bosiljak', 'theme_mode': 'dark'},
        overrides: [
          suggestionStockProvider.overrideWith(
            (ref) => Stream.value(<PantryStock>[]),
          ),
        ],
      );
      await openSelection(tester);
      await addIngredient(tester, 'kupus');
      await tester.scrollUntilVisible(
        find.text('Otvori recept'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Proveri količinu: kupus · za recept 600 g'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tapButton(tester, 'Otvori recept');
      expect(find.text('Skuvaj.'), findsOneWidget);
    });
  }
}
