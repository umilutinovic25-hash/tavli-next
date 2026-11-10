import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/features/recipes/recipe_files.dart';
import 'package:tavli/features/recipes/recipe_providers.dart';

import '../../helpers/test_app.dart';

class FakeRecipeFiles implements RecipeFiles {
  String? toPick;
  bool saveResult = true;
  final saved = <(String, String)>[];

  @override
  Future<String?> pickJson() async => toPick;

  @override
  Future<bool> saveJson(String fileName, String content, {Rect? origin}) async {
    saved.add((fileName, content));
    return saveResult;
  }
}

Future<void> openMenuItem(WidgetTester tester, String text) async {
  await tester.tap(find.byTooltip('Još opcija'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  test('naziv fajla iz naziva recepta', () {
    expect(recipeFileName(' Pita sa jabukama! '), 'Pita-sa-jabukama.json');
    expect(recipeFileName('Đuveč'), 'Đuveč.json');
    expect(recipeFileName('???'), 'recept.json');
  });

  testTavli('izvoz recepta u schema.org JSON', (tester) async {
    final files = FakeRecipeFiles();
    await pumpTavli(
      tester,
      location: '/recipes/a',
      recipes: [sampleRecipe('a', 'Sarma')],
      overrides: [recipeFilesProvider.overrideWithValue(files)],
    );

    await openMenuItem(tester, 'Izvezi kao JSON');

    final (name, content) = files.saved.single;
    expect(name, 'Sarma.json');
    final json = jsonDecode(content) as Map<String, dynamic>;
    expect(json['@type'], 'Recipe');
    expect(json['name'], 'Sarma');
    expect(json['recipeIngredient'], ['biber', '0,5 kg kupus']);
    expect(find.text('Recept je izvezen.'), findsOneWidget);
  });

  testTavli('odustajanje od izvoza ne prikazuje poruku', (tester) async {
    final files = FakeRecipeFiles()..saveResult = false;
    await pumpTavli(
      tester,
      location: '/recipes/a',
      recipes: [sampleRecipe('a', 'Sarma')],
      overrides: [recipeFilesProvider.overrideWithValue(files)],
    );

    await openMenuItem(tester, 'Izvezi kao JSON');

    expect(files.saved, hasLength(1));
    expect(find.text('Recept je izvezen.'), findsNothing);
  });

  testTavli('uvoz iz JSON fajla sa izveštajem', (tester) async {
    final files = FakeRecipeFiles()
      ..toPick = jsonEncode([
        {
          '@type': 'Recipe',
          'name': 'Palačinke',
          'recipeYield': '4',
          'recipeIngredient': ['500 ml mleka', '2 jaja'],
          'recipeInstructions': [
            {'@type': 'HowToStep', 'text': 'Umutiti.'},
          ],
          'image': 'https://primer.rs/p.jpg',
        },
        {
          '@type': 'Recipe',
          'name': 'sarma',
          'recipeIngredient': ['kupus'],
        },
      ]);
    final app = await pumpTavli(
      tester,
      recipes: [sampleRecipe('a', 'Sarma')],
      overrides: [recipeFilesProvider.overrideWithValue(files)],
    );

    await tester.tap(find.text('Dodaj recept'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Iz JSON fajla'));
    await tester.pumpAndSettle();

    expect(find.text('Uvezeno recepata: 1'), findsOneWidget);
    expect(find.text('• sarma — već postoji u receptima'), findsOneWidget);
    expect(find.text('image'), findsOneWidget);
    await tapButton(tester, 'U redu');

    final all = await app.repo.getAll();
    expect(all.map((r) => r.title), containsAll(['Sarma', 'Palačinke']));
    final p = all.firstWhere((r) => r.title == 'Palačinke');
    expect(p.servings, 4);
    expect(p.steps, ['Umutiti.']);
    expect(find.text('Palačinke'), findsOneWidget);
  });

  testTavli('pokvaren fajl prikazuje poruku i ništa ne uvozi', (tester) async {
    final files = FakeRecipeFiles()..toPick = '{nije json';
    final app = await pumpTavli(
      tester,
      overrides: [recipeFilesProvider.overrideWithValue(files)],
    );

    await tester.tap(find.text('Dodaj recept'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Iz JSON fajla'));
    await tester.pumpAndSettle();

    expect(find.text('Fajl nije ispravan JSON recepta.'), findsOneWidget);
    expect(await app.repo.getAll(), isEmpty);
  });
}
