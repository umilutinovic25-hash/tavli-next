import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/app/app.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/pantry_repository.dart';
import 'package:tavli/data/shopping_repository.dart';
import 'package:tavli/features/pantry/pantry_providers.dart';
import 'package:tavli/features/recipes/recipe_providers.dart';
import 'package:tavli/sync/synced_writer.dart';

import '../../helpers/food_seed.dart';
import '../../helpers/test_app.dart';

final now = DateTime(2026, 11, 9, 12);
Future<(PantryRepository, ShoppingRepository)> repositories(
  AppDatabase db,
) async {
  final account = await db.select(db.accounts).getSingle();
  final scope = AccountScope(
    userId: account.userId,
    householdId: account.householdId,
  );
  final writer = SyncedWriter(db, accountId: scope.userId);
  final shop = ShoppingRepository(
    db,
    scope: scope,
    writer: writer,
    clock: () => now,
  );
  return (
    PantryRepository(
      db,
      scope: scope,
      writer: writer,
      shopping: shop,
      clock: () => now,
    ),
    shop,
  );
}

Future<void> enter(WidgetTester tester, String field, String value) async {
  final finder = find.byKey(ValueKey('pantry-$field'));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('TAVLI_DESIGN_CAPTURE')) return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final image = await captureImage(tester.element(find.byType(TavliApp)));
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    Directory('build/pantry-preview').createSync(recursive: true);
    await File('build/pantry-preview/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
  });
}

Future<void> tapIn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
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
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final width in [320.0, 1200.0]) {
    testTavli('brza provera, nepoznato i nestalo na $width px uz tekst 2×', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await pumpTavli(
        tester,
        location: '/pantry',
        size: Size(width, 1200),
        setup: (db) async {
          final (pantry, _) = await repositories(db);
          await pantry.create(name: 'Mleko', quantity: 1, unit: 'l');
        },
      );
      expect(find.textContaining('Provereno: 9.11.2026.'), findsOneWidget);
      Future<void> check(String label) async {
        await tester.ensureVisible(find.byTooltip('Proveri namirnicu'));
        await tester.tap(find.byTooltip('Proveri namirnicu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await check('Imam');
      await tester.enterText(
        find.byKey(const ValueKey('check-quantity')),
        '0,5',
      );
      await tapButton(tester, 'Potvrdi');
      expect(find.textContaining('0,5 l'), findsOneWidget);
      await check('Ne znam količinu');
      expect(find.textContaining('Količina nije potvrđena'), findsOneWidget);
      final unknown = (await app.db.select(app.db.pantryItems).get()).single;
      expect(unknown.quantity, isNull);
      expect(unknown.confirmedAt, isNotNull);
      await check('Nestalo');
      expect(find.text('Još nema unetih namirnica'), findsOneWidget);
      expect(
        (await app.db.select(app.db.pantryItems).get()).single.quantity,
        0,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testTavli('provera ne pretpostavlja količinu; odustajanje ništa ne upisuje', (
    tester,
  ) async {
    final app = await pumpTavli(
      tester,
      location: '/pantry',
      setup: (db) async {
        final (pantry, _) = await repositories(db);
        await pantry.create(name: 'So');
      },
    );
    expect(find.textContaining('Još nije provereno'), findsOneWidget);
    await tester.tap(find.byTooltip('Proveri namirnicu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Imam'));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Potvrdi');
    expect(find.text('Unesi broj veći od nule.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('check-quantity')), '25');
    await tapButton(tester, 'Odustani');
    final row = (await app.db.select(app.db.pantryItems).get()).single;
    expect(row.quantity, isNull);
    expect(row.confirmedAt, isNull);
  });

  testTavli('greška provere čuva količinu za ponovni pokušaj', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/pantry',
      setup: (db) async {
        final (pantry, _) = await repositories(db);
        await pantry.create(name: 'Mleko', quantity: 1, unit: 'l');
      },
    );
    await tester.runAsync(
      () => app.db.customStatement(
        "CREATE TRIGGER reject_check BEFORE UPDATE ON pantry_items BEGIN SELECT RAISE(ABORT, 'test'); END",
      ),
    );
    await tester.tap(find.byTooltip('Proveri namirnicu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Imam'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('check-quantity')),
      '0,25',
    );
    await tapButton(tester, 'Potvrdi');
    expect(find.text('Provera nije sačuvana. Pokušaj ponovo.'), findsOneWidget);
    expect((await app.db.select(app.db.pantryItems).get()).single.quantity, 1);
    await tester.runAsync(
      () => app.db.customStatement('DROP TRIGGER reject_check'),
    );
    await tapButton(tester, 'Potvrdi');
    expect(find.textContaining('0,25 l'), findsOneWidget);
  });

  testTavli('dodavanje, decimalni zarez, izmena i potvrđeno brisanje', (
    tester,
  ) async {
    final app = await pumpTavli(
      tester,
      location: '/pantry',
      overrides: [clockProvider.overrideWithValue(() => now)],
    );
    await tapButton(tester, 'Dodaj namirnicu');
    await enter(tester, 'name', 'Pirinač');
    await enter(tester, 'quantity', '1,5');
    await enter(tester, 'unit', 'kg');
    await enter(tester, 'expiry', '11.11.2026.');
    await capture(tester, 'pantry-form');
    await tapButton(tester, 'Sačuvaj');
    expect(find.text('Pirinač'), findsOneWidget);
    expect(find.textContaining('1,5 kg'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Pirinač'));
    await tester.pumpAndSettle();
    await enter(tester, 'quantity', '250');
    await enter(tester, 'unit', 'g');
    await tapButton(tester, 'Sačuvaj');
    expect(find.textContaining('250 g'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Pirinač'));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Obriši');
    await tapButton(tester, 'Odustani');
    expect(
      (await app.db.select(app.db.pantryItems).get()).single.quantity,
      250,
    );
    await tapButton(tester, 'Obriši');
    await tapButton(tester, 'Ukloni');
    expect(find.text('Još nema unetih namirnica'), findsOneWidget);
    expect(await app.db.select(app.db.pantryItems).get(), isEmpty);
  });

  testTavli('namirnica u formi Ostave: Nepotvrđeno, izbor, izmena je čuva', (
    tester,
  ) async {
    final app = await pumpTavli(
      tester,
      location: '/pantry/new',
      setup: seedEggs,
    );
    await enter(tester, 'name', 'Domaća jajca');
    await tester.pump();
    expect(find.text('Nepotvrđeno'), findsOneWidget);
    await tapIn(tester, find.text('Nepotvrđeno'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Pretraži namirnice'),
      'jaj',
    );
    await tester.pumpAndSettle();
    await tapIn(tester, find.widgetWithText(ListTile, 'jaje'));
    expect(find.text('jaje'), findsOneWidget);
    await tapButton(tester, 'Sačuvaj');
    var row = (await app.db.select(app.db.pantryItems).get()).single;
    expect([row.name, row.foodId], ['Domaća jajca', 'f_jaje']);

    // Izmena količine ne briše izabranu namirnicu.
    await tester.tap(find.widgetWithText(ListTile, 'Domaća jajca'));
    await tester.pumpAndSettle();
    expect(find.text('jaje'), findsOneWidget);
    await enter(tester, 'quantity', '6');
    await tapButton(tester, 'Sačuvaj');
    row = (await app.db.select(app.db.pantryItems).get()).single;
    expect([row.quantity, row.foodId], [6.0, 'f_jaje']);
  });

  testTavli('validacija naziva, količine i datuma; nepoznata količina', (
    tester,
  ) async {
    await pumpTavli(tester, location: '/pantry/new');
    await tapButton(tester, 'Sačuvaj');
    expect(find.text('Unesi naziv.'), findsOneWidget);
    await enter(tester, 'name', 'So');
    await enter(tester, 'quantity', 'NaN');
    await enter(tester, 'expiry', '31.2.2026.');
    await tapButton(tester, 'Sačuvaj');
    expect(find.text('Unesi broj veći od nule.'), findsOneWidget);
    expect(find.text('Unesi datum u obliku d.m.gggg.'), findsOneWidget);
    await enter(tester, 'quantity', '');
    await enter(tester, 'expiry', '');
    await tapButton(tester, 'Sačuvaj');
    expect(find.textContaining('Količina nije potvrđena'), findsOneWidget);
  });

  for (final width in [320.0, 390.0, 768.0, 1024.0, 1440.0]) {
    testTavli('pretraga i rokovi na $width px', (tester) async {
      await pumpTavli(
        tester,
        location: '/pantry',
        size: Size(width, 1000),
        overrides: [clockProvider.overrideWithValue(() => now)],
        setup: (db) async {
          final (pantry, _) = await repositories(db);
          await pantry.create(
            name: 'Mleko',
            quantity: 1,
            unit: 'l',
            category: 'mlečni proizvodi i jaja',
            expiresAt: DateTime(2026, 11, 11, 23, 59),
          );
          await pantry.create(
            name: 'Brašno',
            quantity: 500,
            unit: 'g',
            category: 'suvi proizvodi',
          );
          await pantry.create(
            name: 'Jogurt',
            quantity: 2,
            unit: 'kom',
            category: 'mlečni proizvodi i jaja',
            expiresAt: DateTime(2026, 11, 8),
          );
        },
      );
      await capture(tester, 'pantry-${width.toInt()}');
      await tester.enterText(find.byType(SearchBar), 'brasno');
      await tester.pumpAndSettle();
      expect(find.text('Brašno'), findsOneWidget);
      expect(find.text('Mleko'), findsNothing);
      await tester.tap(find.byTooltip('Obriši pretragu'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Uskoro ističe'));
      await tester.pumpAndSettle();
      expect(find.text('Mleko'), findsOneWidget);
      expect(find.text('Jogurt'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Isteklo'));
      await tester.pumpAndSettle();
      expect(find.text('Jogurt'), findsOneWidget);
      expect(find.text('Mleko'), findsNothing);
      await tester.enterText(find.byType(SearchBar), 'nema');
      await tester.pumpAndSettle();
      expect(find.text('Nema namirnica za ovaj izbor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 1200.0]) {
    testTavli('forma sa tekstom 2× na $width px', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpTavli(tester, location: '/pantry/new', size: Size(width, 1000));
      await enter(tester, 'name', 'Maslinovo ulje');
      await enter(tester, 'quantity', '0,5');
      await enter(tester, 'unit', 'l');
      await tapButton(tester, 'Sačuvaj');
      expect(find.text('Maslinovo ulje'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testTavli('kupljeno iz Nabavke se vidi u istoj Ostavi', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/shopping',
      setup: (db) async {
        final (_, shop) = await repositories(db);
        final list = await shop.recipeList();
        final id = await shop.addManual(list, 'Mleko', quantity: 1, unit: 'l');
        await shop.setBought([id], bought: true);
      },
    );
    await tester.tap(find.text('Po receptu').first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Prebaci u ostavu (1)');
    await tester.tap(find.text('Ostava'));
    await tester.pumpAndSettle();
    expect(find.text('Mleko'), findsOneWidget);
    expect(find.textContaining('Iz nabavke'), findsOneWidget);
    expect(await app.db.select(app.db.pantryItems).get(), hasLength(1));
  });

  testTavli('greška upisa čuva unos; ponovni pokušaj radi', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/pantry/new',
      setup: (db) => db.customStatement(
        "CREATE TRIGGER reject_pantry BEFORE INSERT ON pantry_items BEGIN SELECT RAISE(ABORT, 'test'); END",
      ),
    );
    await enter(tester, 'name', 'So');
    await enter(tester, 'quantity', '10');
    await tapButton(tester, 'Sačuvaj');
    expect(find.text('Izmena nije sačuvana. Pokušaj ponovo.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('pantry-name')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      'So',
    );
    await tester.runAsync(
      () => app.db.customStatement('DROP TRIGGER reject_pantry'),
    );
    await tapButton(tester, 'Sačuvaj');
    expect(find.text('So'), findsOneWidget);
  });

  testTavli('izmena naziva čuva preciznu količinu; tastatura menja polje', (
    tester,
  ) async {
    final app = await pumpTavli(
      tester,
      location: '/pantry',
      setup: (db) async {
        final (pantry, _) = await repositories(db);
        await pantry.create(name: 'Šafran', quantity: 0.001, unit: 'g');
      },
    );
    expect(find.textContaining('0,001 g'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Šafran'));
    await tester.pumpAndSettle();
    await enter(tester, 'name', 'Mleveni šafran');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('pantry-quantity')),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tapButton(tester, 'Sačuvaj');
    expect(
      (await app.db.select(app.db.pantryItems).get()).single.quantity,
      0.001,
    );
  });

  for (final theme in ['bosiljak', 'safran', 'borovnica']) {
    testTavli('Ostava u tamnoj temi $theme', (tester) async {
      await pumpTavli(
        tester,
        location: '/pantry',
        settings: {'theme': theme, 'theme_mode': 'dark'},
        setup: (db) async {
          final (pantry, _) = await repositories(db);
          await pantry.create(name: 'Mleko', quantity: 1, unit: 'l');
        },
      );
      expect(
        Theme.of(tester.element(find.byType(SearchBar))).brightness,
        Brightness.dark,
      );
      await capture(tester, 'pantry-dark-$theme');
      await tester.tap(find.widgetWithText(ListTile, 'Mleko'));
      await tester.pumpAndSettle();
      await enter(tester, 'quantity', '0,5');
      await tapButton(tester, 'Sačuvaj');
      expect(find.textContaining('0,5 l'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testTavli('duga kategorija i tekst 2× na telefonu', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpTavli(
      tester,
      location: '/pantry',
      size: const Size(320, 1000),
      setup: (db) async {
        final (pantry, _) = await repositories(db);
        await pantry.create(
          name: 'Mleko',
          quantity: 1,
          unit: 'l',
          category: 'mlečni proizvodi i jaja',
        );
      },
    );
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Mleko'));
    await tester.tap(find.widgetWithText(ListTile, 'Mleko'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Sačuvaj');
    expect(tester.takeException(), isNull);
  });

  testTavli('nepostojeća namirnica ima poruku', (tester) async {
    await pumpTavli(tester, location: '/pantry/missing/edit');
    expect(find.text('Namirnica nije pronađena.'), findsOneWidget);
  });

  testTavli('greška čitanja ima poruku i ponovni pokušaj', (tester) async {
    await pumpTavli(
      tester,
      location: '/pantry',
      overrides: [
        pantryItemsProvider.overrideWith(
          (ref) => Stream.error(Exception('test')),
        ),
      ],
    );
    expect(find.text('Ostava trenutno ne može da se prikaže.'), findsOneWidget);
    expect(find.text('Pokušaj ponovo'), findsOneWidget);
  });
}
