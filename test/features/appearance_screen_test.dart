import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/app/theme/tavli_palette.dart';
import 'package:tavli/app/theme/theme_controller.dart';
import 'package:tavli/data/settings_repository.dart';
import 'package:tavli/domain/theme_choice.dart';
import 'package:tavli/providers.dart';

import '../helpers/controlled_settings.dart';
import '../helpers/test_app.dart';

ThemeData appTheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first));

void main() {
  testTavli('podrazumevano: Bosiljak, svetla tema kad je sistem svetao', (
    tester,
  ) async {
    await pumpTavli(tester);
    final t = appTheme(tester);
    expect(t.brightness, Brightness.light);
    expect(t.colorScheme.primary, TavliPalette.bosiljakLight.primary);
  });

  testTavli('Profil → Izgled: Šafran i Tamna se odmah primene i sačuvaju', (
    tester,
  ) async {
    final app = await pumpTavli(tester, location: '/profile');
    await tester.tap(find.text('Izgled'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Šafran'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Šafran'));
    await tester.pumpAndSettle();
    expect(
      appTheme(tester).colorScheme.primary,
      TavliPalette.safranLight.primary,
    );

    await tester.ensureVisible(find.text('Tamna'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tamna'));
    await tester.pumpAndSettle();
    expect(appTheme(tester).brightness, Brightness.dark);
    expect(
      appTheme(tester).colorScheme.primary,
      TavliPalette.safranDark.primary,
    );

    final repo = SettingsRepository(app.db);
    expect(await repo.get('theme'), 'safran');
    expect(await repo.get('theme_mode'), 'dark');
  });

  testTavli('posle ponovnog pokretanja koristi sačuvanu temu', (tester) async {
    await pumpTavli(
      tester,
      settings: {'theme': 'borovnica', 'theme_mode': 'dark'},
    );
    final t = appTheme(tester);
    expect(t.brightness, Brightness.dark);
    expect(t.colorScheme.primary, TavliPalette.borovnicaDark.primary);
  });

  testTavli('Kao sistem prati tamni sistem', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpTavli(tester, settings: {'theme_mode': 'system'});
    expect(appTheme(tester).brightness, Brightness.dark);
  });

  testTavli('širok ekran: sve tri teme i režimi su vidljivi', (tester) async {
    await pumpTavli(tester, size: wide, location: '/profile/appearance');
    for (final name in [
      'Bosiljak',
      'Šafran',
      'Borovnica',
      'Svetla',
      'Tamna',
      'Kao sistem',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testTavli('nov izbor je svetao i kad je sistem taman', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpTavli(tester);
    expect(appTheme(tester).brightness, Brightness.light);
  });

  testTavli('greška čuvanja vraća temu i prikazuje srpsku poruku', (
    tester,
  ) async {
    await pumpTavli(
      tester,
      location: '/profile/appearance',
      overrides: [
        settingsRepositoryProvider.overrideWith((ref) {
          final repo = ControlledSettings(ref.watch(databaseProvider));
          repo.fail = true;
          return repo;
        }),
      ],
    );
    final before = appTheme(tester).colorScheme.primary;
    await tester.ensureVisible(find.text('Šafran'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Šafran'));
    await tester.pumpAndSettle();
    expect(find.text('Izgled nije sačuvan. Pokušaj ponovo.'), findsOneWidget);
    expect(appTheme(tester).colorScheme.primary, before);
  });

  for (final mode in ['light', 'dark']) {
    testTavli(
      '320 px, dvostruk tekst, $mode: izbor i pretraga bez prelivanja',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpTavli(
          tester,
          size: const Size(320, 900),
          location: '/profile/appearance',
          settings: {'theme_mode': mode},
        );
        for (final name in ['Bosiljak', 'Šafran', 'Borovnica']) {
          await tester.ensureVisible(find.text(name));
          await tester.pumpAndSettle();
          await tester.tap(find.text(name));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  for (final mode in ['light', 'dark']) {
    testTavli('320 px, dvostruk tekst, $mode: pretraga raste sa tekstom', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpTavli(
        tester,
        size: const Size(320, 900),
        recipes: [sampleRecipe('large', 'Sarma')],
        settings: {'theme_mode': mode},
      );
      await tester.enterText(find.byType(SearchBar), 'Sarma');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final palette in ['bosiljak', 'safran', 'borovnica']) {
    for (final mode in ['light', 'dark']) {
      testTavli('prijava koristi sačuvanu temu $palette/$mode', (tester) async {
        await pumpTavli(
          tester,
          signedIn: false,
          settings: {'theme': palette, 'theme_mode': mode},
        );
        expect(find.text('Prijava'), findsOneWidget);
        final t = appTheme(tester);
        expect(
          t.brightness,
          mode == 'dark' ? Brightness.dark : Brightness.light,
        );
        expect(
          t.colorScheme.primary,
          TavliPalette.of(
            TavliTheme.values.byName(palette),
            t.brightness,
          ).primary,
        );
        expect(t.textTheme.bodyMedium?.fontFamily, 'PlusJakartaSans');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testTavli('Profil u debug verziji ima Animacije', (tester) async {
    await pumpTavli(tester, location: '/profile');
    // Stavka je poslednja u listi; ispod preseka telefona posle "Preferencije".
    await tester.scrollUntilVisible(
      find.text('Animacije'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Animacije'), findsOneWidget);
    expect(find.text('Izgled'), findsOneWidget);
  });
}
