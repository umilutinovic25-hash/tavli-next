import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/test_app.dart';

/// Vlasnik drugog domaćinstva sa jednim receptom pravi pozivnicu.
Future<String> ownerInvite(FakeBackend backend) async {
  final owner = await backend.auth.verifyCode('vlasnik@mail.com', '123456');
  final home = backend.server.households[owner.userId]!;
  backend.server.householdNames[home] = 'Kod Vlasnika';
  backend.server.upsert('recipes', [
    {
      'id': 'zajednicki',
      'household_id': home,
      'title': 'Zajednička sarma',
      'servings': 4,
      'prep_minutes': null,
      'source': 'manual',
      'ingredients': <Object>[],
      'steps': ['Kuvati.'],
      'image_path': null,
      'answered_by': null,
      'created_at': '2026-10-30T10:00:00.000Z',
    },
  ], 'id');
  final code = await backend.invites.create(home);
  final me = backend.auth.sessionFor(testEmail);
  // Na serveru je isto ime kao na uređaju (puno preuzimanje donosi profil).
  backend.server.profiles[me.userId]!['display_name'] = 'Ana Petrović';
  backend.auth.current = me;
  return code;
}

Future<void> openJoin(WidgetTester tester) async {
  await tapButton(tester, 'Pridruži se kodom');
}

Finder codeField() => find.widgetWithText(TextField, 'Unesi kod od 8 znakova');

bool joinEnabled(WidgetTester tester) =>
    tester.widget<ButtonStyleButton>(button('Pridruži se')).onPressed != null;

void main() {
  testTavli('objašnjenje i dugme tek uz 8 znakova', (tester) async {
    await pumpTavli(tester, location: '/profile/household');
    await openJoin(tester);

    expect(
      find.text(
        'Posle pridruživanja vidiš plan, nabavku, recepte i ostavu ovog '
        'domaćinstva. Tvoji dosadašnji podaci ostaju sačuvani u tvom '
        'domaćinstvu.',
      ),
      findsOneWidget,
    );
    expect(joinEnabled(tester), isFalse);
    await tester.enterText(codeField(), 'abcd');
    await tester.pump();
    expect(joinEnabled(tester), isFalse);
    await tester.enterText(codeField(), 'abcd-efgh');
    await tester.pump();
    expect(joinEnabled(tester), isTrue);
  });

  testTavli('nalepljen kod: član zajedničkog domaćinstva i njegovi recepti', (
    tester,
  ) async {
    final backend = FakeBackend();
    final code = await ownerInvite(backend);
    final app = await pumpTavli(
      tester,
      location: '/profile/household',
      backend: backend,
    );
    await openJoin(tester);

    final pasted =
        ' ${code.substring(0, 4).toLowerCase()}-'
        '${code.substring(4).toLowerCase()}\n';
    await tester.enterText(codeField(), pasted);
    await tester.pump();
    await tapButton(tester, 'Pridruži se');

    expect(
      find.text('Sada si član domaćinstva „Kod Vlasnika“.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(AppBar, 'Domaćinstvo'), findsOneWidget);
    expect(find.text('Kod Vlasnika'), findsWidgets);
    // Lista članova novog domaćinstva se učitava odmah (vlasnik i „Ti“).
    expect(find.text('Ti'), findsOneWidget);
    expect(find.text('Vlasnik'), findsWidgets);

    await tester.pumpAndSettle(const Duration(seconds: 1));
    final titles = await app.titles();
    expect(titles, contains('Zajednička sarma'));
  });

  testTavli('nevažeći kod, pa previše pokušaja', (tester) async {
    await pumpTavli(tester, location: '/profile/household');
    await openJoin(tester);
    for (var i = 0; i < 5; i++) {
      await tester.enterText(codeField(), 'ZZZZZZZZ');
      await tester.pump();
      await tapButton(tester, 'Pridruži se');
      expect(find.text('Kod nije važeći ili je istekao.'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(codeField())).clearSnackBars();
      await tester.pumpAndSettle();
    }
    await tapButton(tester, 'Pridruži se');
    expect(
      find.text('Previše pokušaja. Pokušaj ponovo za 10 minuta.'),
      findsOneWidget,
    );
  });

  testTavli('bez mreže: poruka i kod ostaje u polju', (tester) async {
    final backend = FakeBackend();
    await pumpTavli(tester, location: '/profile/household', backend: backend);
    await openJoin(tester);
    backend.server.offline = true;
    await tester.enterText(codeField(), 'K7P2MDX1');
    await tester.pump();
    await tapButton(tester, 'Pridruži se');
    expect(find.text('Za ovo je potrebna internet veza.'), findsOneWidget);
    expect(find.text('K7P2MDX1'), findsOneWidget);
  });

  testTavli('dupli dodir šalje jedan zahtev', (tester) async {
    final backend = FakeBackend();
    final code = await ownerInvite(backend);
    await pumpTavli(tester, location: '/profile/household', backend: backend);
    await openJoin(tester);
    await tester.enterText(codeField(), code);
    await tester.pump();
    final gate = backend.invites.gate = Completer<void>();

    await tester.tap(button('Pridruži se'));
    await tester.pump();
    await tester.tap(button('Pridruži se'), warnIfMissed: false);
    await tester.pump();
    gate.complete();
    backend.invites.gate = null;
    await tester.pumpAndSettle();

    expect(backend.invites.calls.where((c) => c == 'redeem'), hasLength(1));
  });

  testTavli('telefon, tekst 2×: bez prelivanja', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpTavli(
      tester,
      location: '/profile/household/join',
      size: const Size(390, 844),
    );
    expect(codeField(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
