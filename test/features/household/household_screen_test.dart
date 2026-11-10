import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
