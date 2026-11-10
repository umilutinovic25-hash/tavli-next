import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tavli/features/account/account_header.dart';
import 'package:tavli/sync/sync_engine.dart';
import 'package:tavli/sync/sync_remote.dart';

import '../../helpers/test_app.dart';

void main() {
  testTavli('Profil: inicijali, ime, e-pošta, domaćinstvo, uloga', (
    tester,
  ) async {
    await pumpTavli(tester, location: '/profile');
    expect(find.text('AP'), findsOneWidget);
    expect(find.text('Ana Petrović'), findsOneWidget);
    expect(find.text(testEmail), findsOneWidget);
    expect(find.text('Moje domaćinstvo · Vlasnik'), findsOneWidget);
    expect(find.text('Izmeni ime'), findsOneWidget);
    // Zaglavlje je iznad postojećih stavki.
    expect(
      tester.getTopLeft(find.text('Ana Petrović')).dy,
      lessThan(tester.getTopLeft(find.text('Izgled')).dy),
    );
  });

  testTavli('jedna reč daje jedno slovo', (tester) async {
    await pumpTavli(tester, location: '/profile', name: 'Ana');
    expect(find.text('A'), findsOneWidget);
  });

  testTavli('"Izmeni ime" menja ime i inicijale svuda', (tester) async {
    final app = await pumpTavli(tester, location: '/profile');
    await tester.tap(find.text('Izmeni ime'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, '   ');
    await tester.pump();
    expect(tester.widget<FilledButton>(button('Sačuvaj')).onPressed, isNull);

    await tester.enterText(field, 'Đorđe Šćepanović');
    await tester.pump();
    await tester.tap(button('Sačuvaj'));
    await tester.pumpAndSettle();

    expect(find.text('Đorđe Šćepanović'), findsOneWidget);
    expect(find.text('ĐŠ'), findsOneWidget);
    final row = (await app.db.select(app.db.accounts).get()).single;
    expect(row.displayName, 'Đorđe Šćepanović');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      app.backend.server.profiles[app.session.userId]!['display_name'],
      'Đorđe Šćepanović',
    );
  });

  testTavli('"Odustani" ne menja ime', (tester) async {
    await pumpTavli(tester, location: '/profile');
    await tester.tap(find.text('Izmeni ime'));
    await tester.pumpAndSettle();
    await tester.tap(button('Odustani'));
    await tester.pumpAndSettle();
    expect(find.text('Ana Petrović'), findsOneWidget);
  });

  for (final size in [phone, wide]) {
    testTavli('raspored zaglavlja na ${size.width.toInt()} px', (tester) async {
      await pumpTavli(tester, location: '/profile', size: size);
      expect(tester.takeException(), isNull);
      expect(find.text('AP'), findsOneWidget);
    });
  }

  group('stanje čuvanja', () {
    testTavli('sve sačuvano posle pokretanja', (tester) async {
      await pumpTavli(tester, location: '/profile');
      expect(find.text('Sve je sačuvano u nalogu.'), findsOneWidget);
    });

    testTavli('bez mreže čeka, pa se šalje kad se mreža vrati', (tester) async {
      final app = await pumpTavli(tester, location: '/profile');
      app.backend.server.offline = true;
      await tester.tap(find.text('Izmeni ime'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Ana',
      );
      await tester.tap(button('Sačuvaj'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Čeka slanje: 1'), findsOneWidget);

      app.backend.server.offline = false;
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Sve je sačuvano u nalogu.'), findsOneWidget);
    });

    testTavli('odbijena izmena', (tester) async {
      final app = await pumpTavli(tester, location: '/profile');
      // Grupa pa pojedinačno: server odbija oba pokušaja.
      app.backend.server.failures.addAll(const [
        PermanentSyncError('23514'),
        PermanentSyncError('23514'),
      ]);
      await tester.tap(find.text('Izmeni ime'));
      await tester.pumpAndSettle();
      await tester.tap(button('Sačuvaj'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Neke izmene nisu sačuvane u nalogu.'), findsOneWidget);
    });

    test('tekstovi za svako stanje', () {
      expect(syncStatusText(const AllSaved()), 'Sve je sačuvano u nalogu.');
      expect(syncStatusText(const Sending()), 'Čuvam izmene…');
      expect(syncStatusText(const Waiting(3)), 'Čeka slanje: 3');
      expect(
        syncStatusText(const Rejected(1)),
        'Neke izmene nisu sačuvane u nalogu.',
      );
    });
  });
}
