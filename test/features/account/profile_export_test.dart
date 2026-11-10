import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void main() {
  testTavli('Profil ima dugme za izvoz ličnih podataka', (tester) async {
    await pumpTavli(tester, location: '/profile');

    expect(find.text('Izvezi moje podatke'), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
  });
}
