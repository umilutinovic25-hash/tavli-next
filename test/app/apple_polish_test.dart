import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tavli/app/animations/content_reveal.dart';
import 'package:tavli/app/app.dart';
import 'package:tavli/app/theme/app_theme.dart';
import 'package:tavli/domain/theme_choice.dart';

import '../helpers/test_app.dart';

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('TAVLI_POLISH_CAPTURE')) return;
  await tester.runAsync(() async {
    final image = await captureImage(tester.element(find.byType(TavliApp)));
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    Directory('build/apple-preview').createSync(recursive: true);
    await File('build/apple-preview/$name.png')
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

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    test('sistemski font na ${platform.name}', () {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final theme = buildTavliTheme(TavliTheme.bosiljak, Brightness.light);
      expect(theme.textTheme.bodyMedium?.fontFamily, 'CupertinoSystemText');
      expect(
        theme.textTheme.bodyMedium?.fontFamilyFallback,
        contains(tavliFontFamily),
      );
    });
  }

  testWidgets('Reduce Motion prikazuje sadržaj odmah, bez aktivnih animacija', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: ContentReveal(child: Text('Spremno'))),
        ),
      ),
    );
    expect(
      tester
          .widget<Opacity>(
            find.descendant(
              of: find.byType(ContentReveal),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      1,
    );
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.text('Spremno'), findsOneWidget);
  });

  for (final width in [320.0, 390.0, 768.0, 1024.0, 1440.0]) {
    testTavli('Plan i Recepti — $width px', (tester) async {
      await pumpTavli(
        tester,
        size: Size(width, 1000),
        location: '/plan',
        recipes: [
          sampleRecipe('sarma', 'Domaća sarma'),
          sampleRecipe('corba', 'Čorba od povrća'),
        ],
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'plan-${width.toInt()}');
      final nav = find.byType(width >= 720 ? NavigationRail : NavigationBar);
      await tester.tap(
        find.descendant(of: nav, matching: find.text('Recepti')),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(currentTab(tester), 'Recepti');
      expect(find.text('Domaća sarma'), findsOneWidget);
      await capture(tester, 'recipes-${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }

  testTavli('desktop naslov sekcije ostaje tačan posle promene teme', (
    tester,
  ) async {
    await pumpTavli(tester, size: wide, location: '/plan');
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go('/profile/appearance');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Šafran'));
    await tester.pumpAndSettle();
    router.go('/plan');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Plan'), findsOneWidget);
  });

  for (final palette in ['bosiljak', 'safran', 'borovnica']) {
    testTavli('320 px, tekst 2× — $palette tamna', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpTavli(
        tester,
        size: const Size(320, 1200),
        location: '/plan',
        settings: {'theme': palette, 'theme_mode': 'dark'},
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'dark-$palette');
      expect(tester.takeException(), isNull);
    });
  }
}
