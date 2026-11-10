import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void main() {
  testTavli('Politika privatnosti: naslov, oznaka nacrta i AI servisi', (
    tester,
  ) async {
    await pumpTavli(tester, location: '/profile/privacy');

    expect(find.text('Politika privatnosti'), findsOneWidget);
    expect(
      find.text('Nacrt — pravni pregled je potreban pre objave'),
      findsOneWidget,
    );
    // ListView gradi samo vidljive redove, pa se skroluje do svakog.
    final scrollable = find.byType(Scrollable).first;
    for (final text in [
      'Google Gemini',
      'Groq',
      'OpenRouter',
      '[email za privatnost]',
    ]) {
      await tester.scrollUntilVisible(
        find.textContaining(text),
        300,
        scrollable: scrollable,
      );
      expect(find.textContaining(text), findsOneWidget, reason: text);
    }
  });

  testTavli('Profil → Politika privatnosti otvara ekran', (tester) async {
    await pumpTavli(tester, location: '/profile');
    await tester.tap(find.text('Politika privatnosti'));
    await tester.pumpAndSettle();

    expect(
      find.text('Nacrt — pravni pregled je potreban pre objave'),
      findsOneWidget,
    );
  });
}
