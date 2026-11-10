import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/app/app.dart';
import 'package:tavli/features/recipes/recipe_grid.dart';

import '../../helpers/test_app.dart';

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('TAVLI_DESIGN_CAPTURE')) return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final image = await captureImage(tester.element(find.byType(TavliApp)));
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    Directory('build/recipe-library-preview').createSync(recursive: true);
    await File('build/recipe-library-preview/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('PlusJakartaSans');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      loader.addFont(
        rootBundle.load('assets/fonts/PlusJakartaSans-$weight.ttf'),
      );
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final width in [320.0, 390.0, 768.0, 1024.0, 1440.0]) {
    testTavli('lista → mreža → pretraga → recept, $width px', (tester) async {
      await pumpTavli(
        tester,
        size: Size(width, 900),
        recipes: [
          sampleRecipe('sarma', 'Sarma'),
          sampleRecipe('corba', 'Čorba od povrća'),
          sampleRecipe('musaka', 'Musaka'),
          sampleRecipe('pasulj', 'Čorbast pasulj'),
        ],
      );
      expect(find.byType(RecipeGrid), findsNothing);
      await tester.tap(find.byTooltip('Prikaži mrežu'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeGrid), findsOneWidget);
      expect(find.text('4 porcije'), findsWidgets);
      expect(find.text('45 min'), findsWidgets);
      await capture(tester, 'grid-${width.toInt()}');
      await tester.enterText(find.byType(SearchBar), 'corba');
      await tester.pumpAndSettle();
      expect(find.text('Čorba od povrća'), findsOneWidget);
      expect(find.text('Sarma'), findsNothing);
      await tester.tap(find.byTooltip('Prikaži listu'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Čorba od povrća'), findsOneWidget);
      await tester.tap(find.byTooltip('Prikaži mrežu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Čorba od povrća'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Čorba od povrća'), findsOneWidget);
      // Na 1024 px prošireni rail ostavlja manje od 840 px za split view.
      if (width >= 1200) expect(find.byType(RecipeGrid), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 1200.0]) {
    testTavli('mreža i dugi nazivi sa tekstom 2×, $width px', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpTavli(
        tester,
        size: Size(width, 1000),
        recipes: [
          sampleRecipe(
            'a',
            'Domaća čorba sa povrćem, pirinčem i svežim začinskim biljem',
          ),
        ],
      );
      await tester.tap(find.byTooltip('Prikaži mrežu'));
      await tester.pumpAndSettle();
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        1,
      );
      await capture(tester, 'grid-large-text-${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }

  for (final theme in ['bosiljak', 'safran', 'borovnica']) {
    testTavli('mreža u tamnoj temi $theme i nedostajuća slika', (tester) async {
      await pumpTavli(
        tester,
        recipes: [
          sampleRecipe('a', 'Sarma').copyWith(imagePath: 'missing.jpg'),
        ],
        settings: {'theme': theme, 'theme_mode': 'dark'},
      );
      await tester.tap(find.byTooltip('Prikaži mrežu'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(RecipeGrid))).brightness,
        Brightness.dark,
      );
      expect(find.text('Sarma'), findsOneWidget);
      await capture(tester, 'grid-dark-$theme');
      await tester.tap(find.text('Sarma'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Sarma'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testTavli('prazna pretraga u mreži i čišćenje zadržavaju prikaz', (
    tester,
  ) async {
    await pumpTavli(tester, recipes: [sampleRecipe('a', 'Sarma')]);
    await tester.tap(find.byTooltip('Prikaži mrežu'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), 'nema');
    await tester.pumpAndSettle();
    expect(find.text('Nema recepata za „nema“.'), findsOneWidget);
    await tester.tap(find.byTooltip('Obriši pretragu'));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeGrid), findsOneWidget);
    expect(find.text('Sarma'), findsOneWidget);
  });
}
