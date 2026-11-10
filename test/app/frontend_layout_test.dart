import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/app/app.dart';
import 'package:tavli/domain/theme_choice.dart';
import 'package:tavli/features/recipes/recipe_providers.dart';

import '../features/planning/plan_calendar_test.dart'
    show seedPlan, today, week;
import '../helpers/test_app.dart';

/// Opt-in slike iz stvarnih widgeta; nikada produkcioni nalog ili AI.
Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('TAVLI_DESIGN_CAPTURE')) return;
  await tester.runAsync(() async {
    final image = await captureImage(tester.element(find.byType(TavliApp)));
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = Directory('build/design-preview')
      ..createSync(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('PlusJakartaSans');
    loader.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'));
    loader.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Medium.ttf'));
    loader.addFont(
      rootBundle.load('assets/fonts/PlusJakartaSans-SemiBold.ttf'),
    );
    loader.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Bold.ttf'));
    loader.addFont(
      rootBundle.load('assets/fonts/PlusJakartaSans-ExtraBold.ttf'),
    );
    await loader.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final width in [320.0, 390.0, 768.0, 1024.0, 1440.0]) {
    testTavli('Plan → Nabavka i tabovi na $width px', (tester) async {
      await pumpTavli(
        tester,
        location: '/plan',
        size: Size(width, 900),
        recipes: [
          sampleRecipe('sarma', 'Sarma'),
          sampleRecipe('supa', 'Supa od povrća'),
        ],
        setup: (db) => seedPlan(db, week),
        overrides: [clockProvider.overrideWithValue(() => today)],
      );
      await capture(tester, 'plan-${width.toInt()}');
      if (width >= 1024) {
        await openFirstMeal(tester);
        await capture(tester, 'plan-detail-${width.toInt()}');
        await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
        await tester.pumpAndSettle();
      }
      await tapButton(tester, 'Otvori nabavku');
      expect(currentTab(tester), 'Nabavka');
      expect(find.text('krompir'), findsWidgets);
      await capture(tester, 'shopping-${width.toInt()}');

      await tester.tap(find.text('Recepti').last);
      await tester.pumpAndSettle();
      expect(currentTab(tester), 'Recepti');
      await capture(tester, 'recipes-${width.toInt()}');
      await tester.enterText(find.byType(SearchBar), 'Sarma');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Sarma'), findsOneWidget);
      expect(find.text('Supa od povrća'), findsNothing);
      if (width >= 1440) {
        await tester.tap(find.widgetWithText(ListTile, 'Sarma'));
        await tester.pumpAndSettle();
        await capture(tester, 'recipe-detail-${width.toInt()}');
      }

      await tester.tap(find.text('Ostava').last);
      // Ostava učitava stvarne podatke; prazna animacija igra jednom.
      await tester.pumpAndSettle();
      expect(currentTab(tester), 'Ostava');
      expect(find.text('Još nema unetih namirnica'), findsOneWidget);
      await capture(tester, 'pantry-${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }

  for (final theme in TavliTheme.values) {
    testTavli('tamna tema ${theme.name}: Plan ostaje upotrebljiv', (
      tester,
    ) async {
      await pumpTavli(
        tester,
        location: '/plan',
        settings: {'theme': theme.name, 'theme_mode': 'dark'},
        setup: (db) => seedPlan(db, week),
        overrides: [clockProvider.overrideWithValue(() => today)],
      );
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        Brightness.dark,
      );
      await tapButton(tester, 'Otvori nabavku');
      expect(currentTab(tester), 'Nabavka');
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> openFirstMeal(WidgetTester tester) async {
  final meal = find.text('Ručak 2.11.');
  await tester.ensureVisible(meal);
  await tester.tap(meal);
  await tester.pumpAndSettle();
}
