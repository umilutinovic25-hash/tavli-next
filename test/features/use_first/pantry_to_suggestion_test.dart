// Integration-only acceptance check for 011 + 012 + 013 + 014.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/features/recipes/recipe_providers.dart';

import '../../helpers/test_app.dart';
import 'use_first_screen_test.dart' show recipe, now;

void main() {
  testTavli('Ostava unos → Potroši prvo → postojeći recept', (tester) async {
    await pumpTavli(
      tester,
      location: '/pantry',
      recipes: [recipe('kupus', 'Kupus za ručak', 'kupus')],
      overrides: [clockProvider.overrideWithValue(() => now)],
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tapButton(tester, 'Dodaj namirnicu');
    for (final (field, value) in [
      ('name', 'kupus'),
      ('quantity', '500'),
      ('unit', 'g'),
      ('expiry', '10.11.2026.'),
    ]) {
      final finder = find.byKey(ValueKey('pantry-$field'));
      await tester.ensureVisible(finder);
      await tester.enterText(finder, value);
    }
    await tapButton(tester, 'Sačuvaj');
    await tester.tap(find.byTooltip('Potroši prvo'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kupus za ručak'), findsOneWidget);
    expect(find.textContaining('Potroši prvo: kupus'), findsOneWidget);
    await tapButton(tester, 'Otvori recept');
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Kupus za ručak'), findsOneWidget);
  });
}
