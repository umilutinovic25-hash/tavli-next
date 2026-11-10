import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/app/app.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/use_first.dart';
import 'package:tavli/features/recipes/recipe_providers.dart';
import 'package:tavli/features/use_first/use_first_screen.dart';

import '../../helpers/test_app.dart';

final now = DateTime.utc(2026, 11, 9, 12);
Recipe recipe(String id, String title, String ingredient) => Recipe(
  id: id,
  title: title,
  servings: 2,
  ingredients: [Ingredient(name: ingredient, quantity: 500, unit: 'g')],
  steps: const ['Skuvaj.'],
  source: RecipeSource.manual,
  createdAt: now,
);
Future<void> seed(AppDatabase db) async {
  for (final (id, name, days) in [('one', 'kupus', 1), ('two', 'pasulj', 5)]) {
    await db
        .into(db.pantryItems)
        .insert(
          PantryItemsCompanion.insert(
            id: id,
            name: name,
            category: 'ostalo',
            addedAt: now,
            householdId: const Value('home-1'),
            quantity: const Value(500),
            unit: const Value('g'),
            confirmedAt: Value(now),
            expiresAt: Value(now.add(Duration(days: days))),
          ),
        );
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('TAVLI_USE_FIRST_CAPTURE')) return;
  await tester.runAsync(() async {
    final image = await captureImage(tester.element(find.byType(TavliApp)));
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    Directory('build/use-first-preview').createSync(recursive: true);
    await File('build/use-first-preview/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    final font = FontLoader('PlusJakartaSans');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      font.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testTavli('prioritet, porcije i živa Ostava bez upisa', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/use-first',
      size: const Size(600, 1600),
      recipes: [recipe('a', 'Pasulj', 'pasulj'), recipe('b', 'Kupus', 'kupus')],
      setup: seed,
      overrides: [clockProvider.overrideWithValue(() => now)],
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kupus'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Kupus')).dy,
      lessThan(tester.getTopLeft(find.text('Pasulj')).dy),
    );
    final writes = (await app.db.select(app.db.syncOutbox).get()).length;
    await tester.tap(find.byTooltip('Više porcija'));
    await tester.pumpAndSettle();
    expect(find.text('Nedostaje: kupus · 250 g'), findsOneWidget);
    // 500 g × 3/2 = 750 g; 250 g nedostaje (format je decimalni zarez).
    expect(find.textContaining('Nedostaje: kupus'), findsOneWidget);
    await tester.tap(find.text('Mogu sada'));
    await tester.pumpAndSettle();
    expect(
      find.text('Nema predloga za izabranu pretragu i filter.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Manje porcija'));
    await tester.pumpAndSettle();
    expect(find.text('Kupus'), findsOneWidget);
    await (app.db.update(app.db.pantryItems)..where((p) => p.id.equals('one')))
        .write(const PantryItemsCompanion(quantity: Value(0)));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kupus'), findsNothing);
    expect(find.text('Pasulj'), findsOneWidget);
    expect((await app.db.select(app.db.syncOutbox).get()).length, writes);
  });
  for (final width in [320.0, 390.0, 768.0, 1024.0, 1440.0]) {
    testTavli('raspored $width', (tester) async {
      await pumpTavli(
        tester,
        location: '/use-first',
        size: Size(width, 1000),
        recipes: [recipe('b', 'Kupus', 'kupus')],
        setup: seed,
        overrides: [clockProvider.overrideWithValue(() => now)],
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kupus'), findsOneWidget);
      await capture(tester, 'use-first-${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }
  testTavli('bez recepata vodi do zbirke', (tester) async {
    await pumpTavli(tester, location: '/use-first');
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Otvori recepte'), findsOneWidget);
  });
  testTavli('greška, ponovni pokušaj i prazna Ostava', (tester) async {
    var recover = false;
    await pumpTavli(
      tester,
      location: '/use-first',
      recipes: [recipe('b', 'Kupus', 'kupus')],
      overrides: [
        suggestionStockProvider.overrideWith((ref) {
          return !recover
              ? Stream<List<PantryStock>>.error(Exception('offline'))
              : Stream.value(<PantryStock>[]);
        }),
      ],
    );
    expect(find.text('Predlozi trenutno nisu dostupni.'), findsOneWidget);
    recover = true;
    await tester.tap(find.text('Pokušaj ponovo'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Otvori Ostavu'), findsOneWidget);
  });
  testTavli('neprijavljeni ne mogu otvoriti predloge', (tester) async {
    await pumpTavli(tester, location: '/use-first', signedIn: false);
    expect(find.byType(UseFirstScreen), findsNothing);
  });
  testTavli('pretraga i otvaranje postojećeg recepta', (tester) async {
    await pumpTavli(
      tester,
      location: '/pantry',
      size: const Size(600, 1600),
      recipes: [recipe('b', 'Kupus', 'kupus'), recipe('a', 'Pasulj', 'pasulj')],
      setup: seed,
      overrides: [clockProvider.overrideWithValue(() => now)],
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Potroši prvo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'kup');
    await tester.pumpAndSettle();
    expect(find.text('Pasulj'), findsNothing);
    await tester.tap(find.text('Otvori recept'));
    await tester.pumpAndSettle();
    expect(find.text('Skuvaj.'), findsOneWidget);
  });
  for (final theme in ['bosiljak', 'safran', 'borovnica']) {
    testTavli('tema $theme i tekst 2×', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpTavli(
        tester,
        location: '/use-first',
        size: const Size(320, 1200),
        recipes: [recipe('b', 'Kupus', 'kupus')],
        setup: seed,
        settings: {'theme': theme, 'theme_mode': 'dark'},
        overrides: [clockProvider.overrideWithValue(() => now)],
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -650));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
