import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/features/household/invite_code_sheet.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/test_app.dart';

void main() {
  testTavli('profil vodi na Domaćinstvo sa nazivom i ulogom', (tester) async {
    await pumpTavli(tester, location: '/profile');
    final tile = find.widgetWithText(ListTile, 'Domaćinstvo');
    expect(
      find.descendant(of: tile, matching: find.text('Moje domaćinstvo')),
      findsOneWidget,
    );

    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Domaćinstvo'), findsOneWidget);
    expect(find.text('Moje domaćinstvo'), findsWidgets);
    expect(find.text('Vlasnik'), findsWidgets);
  });

  group('pozivnice (vlasnik)', () {
    testTavli('Pozovi člana prikazuje kod, rok i upotrebe', (tester) async {
      final shared = <String>[];
      await pumpTavli(
        tester,
        location: '/profile/household',
        overrides: [
          shareTextProvider.overrideWithValue((text, {origin}) async {
            shared.add(text);
          }),
        ],
      );
      expect(find.text('Nema aktivnih pozivnica.'), findsOneWidget);

      await tapButton(tester, 'Pozovi člana');

      expect(find.text('Kod za pozivanje'), findsOneWidget);
      expect(find.text('K7P2 MDX1'), findsWidgets);
      expect(find.textContaining('Važi do '), findsWidgets);
      expect(find.text('Još 5 upotreba'), findsWidgets);

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tapButton(tester, 'Kopiraj kod');
      expect(copied, 'K7P2MDX1');
      expect(find.text('Kod je kopiran.'), findsOneWidget);

      await tapButton(tester, 'Podeli');
      expect(shared, [
        'Pridruži se mom domaćinstvu u aplikaciji Tavli. Kod: K7P2MDX1. '
            'Otvori Tavli → Profil → Domaćinstvo → Pridruži se kodom.',
      ]);
    });

    testTavli('dupli dodir na Pozovi člana pravi jednu pozivnicu', (
      tester,
    ) async {
      final backend = FakeBackend();
      await pumpTavli(tester, location: '/profile/household', backend: backend);
      final gate = backend.invites.gate = Completer<void>();

      await tester.tap(button('Pozovi člana'));
      await tester.pump();
      await tester.tap(button('Pozovi člana'), warnIfMissed: false);
      await tester.pump();
      gate.complete();
      backend.invites.gate = null;
      await tester.pumpAndSettle();

      expect(backend.invites.calls.where((c) => c == 'create'), hasLength(1));
    });

    testTavli('poništena pozivnica nestaje iz liste', (tester) async {
      await pumpTavli(tester, location: '/profile/household');
      await tapButton(tester, 'Pozovi člana');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Aktivne pozivnice'), findsOneWidget);
      expect(find.text('K7P2 MDX1'), findsOneWidget);

      await tapButton(tester, 'Poništi');
      expect(find.text('Poništiti pozivnicu?'), findsOneWidget);
      expect(find.text('Kod više neće moći da se iskoristi.'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Poništi'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pozivnica je poništena.'), findsOneWidget);
      expect(find.text('K7P2 MDX1'), findsNothing);
      expect(find.text('Nema aktivnih pozivnica.'), findsOneWidget);
    });

    testTavli('bez mreže: poruka o mreži', (tester) async {
      final backend = FakeBackend();
      await pumpTavli(tester, location: '/profile/household', backend: backend);
      backend.server.offline = true;
      await tapButton(tester, 'Pozovi člana');
      expect(find.text('Za ovo je potrebna internet veza.'), findsOneWidget);
      expect(find.text('Kod za pozivanje'), findsNothing);
    });

    testTavli('član ne vidi pozivnice', (tester) async {
      final backend = FakeBackend();
      final owner = backend.server.userFor('vlasnik@mail.com');
      final ana = backend.server.userFor(testEmail);
      backend.server.addMember(backend.server.households[owner]!, ana);
      await pumpTavli(tester, location: '/profile/household', backend: backend);

      expect(find.text('Član'), findsWidgets);
      expect(button('Pozovi člana'), findsNothing);
      expect(find.text('Aktivne pozivnice'), findsNothing);
    });

    for (final (name, size, scale) in [
      ('široko', const Size(1200, 800), 1.0),
      ('telefon, tekst 2×', const Size(390, 844), 2.0),
    ]) {
      testTavli('list sa kodom bez prelivanja: $name', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpTavli(tester, location: '/profile/household', size: size);
        await tapButton(tester, 'Pozovi člana');
        expect(find.text('Kod za pozivanje'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
