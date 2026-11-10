import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/data/recipe_url_import.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/features/recipes/from_url_screen.dart';

import '../../helpers/test_app.dart';

class FakeImporter implements RecipeUrlImporter {
  FakeImporter({this.fail = false, this.error});
  final bool fail;
  final RecipeUrlImportException? error;
  @override
  Future<Recipe> fetch(String url) async {
    if (error case final e?) throw e;
    if (fail) throw const RecipeUrlImportException();
    return Recipe(
      id: 'url-recipe',
      title: 'Pita',
      servings: 4,
      ingredients: const [
        Ingredient(name: '200 g brašna'),
        Ingredient(name: 'so po ukusu'),
      ],
      steps: const ['Umesi.'],
      source: RecipeSource.url,
      sourceUrl: url,
      createdAt: DateTime.utc(2026),
    );
  }
}

void main() {
  for (final size in [phone, wide]) {
    testTavli('URL pregled i čuvanje na širini ${size.width}', (tester) async {
      final app = await pumpTavli(
        tester,
        size: size,
        location: '/recipes/new/url',
        overrides: [
          recipeUrlImporterProvider.overrideWithValue(FakeImporter()),
        ],
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Adresa recepta'),
        'https://example.com/pita',
      );
      await tapButton(tester, 'Pregledaj recept');
      expect(await app.titles(), isEmpty);
      expect(find.textContaining('Proveri uvezene sastojke'), findsOneWidget);
      expect(find.text('200 g brašna'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Naziv'),
        'Moja pita',
      );
      await tapButton(tester, 'Sačuvaj');
      expect(await app.titles(), ['Moja pita']);
      expect(
        (await app.repo.get('url-recipe'))?.sourceUrl,
        'https://example.com/pita',
      );
    });
  }
  testTavli('neuspešan uvoz ne čuva recept', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/new/url',
      overrides: [
        recipeUrlImporterProvider.overrideWithValue(FakeImporter(fail: true)),
      ],
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Adresa recepta'),
      'bad',
    );
    await tapButton(tester, 'Pregledaj recept');
    expect(find.textContaining('Nije moguće učitati recept'), findsOneWidget);
    expect(await app.titles(), isEmpty);
  });

  testTavli('previše uvoza prikazuje poruku o ograničenju', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/new/url',
      overrides: [
        recipeUrlImporterProvider.overrideWithValue(
          FakeImporter(
            error: const RecipeUrlImportException(rateLimited: true),
          ),
        ),
      ],
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Adresa recepta'),
      'https://example.com/pita',
    );
    await tapButton(tester, 'Pregledaj recept');
    expect(
      find.text('Previše uvoza zaredom. Sačekaj malo pa pokušaj ponovo.'),
      findsOneWidget,
    );
    expect(await app.titles(), isEmpty);
  });
}
