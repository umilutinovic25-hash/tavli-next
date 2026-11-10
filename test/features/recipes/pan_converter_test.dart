import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/pan_converter.dart';
import 'package:tavli/domain/recipe.dart';

import '../../helpers/test_app.dart';

void main() {
  for (final width in [320.0, 1200.0]) {
    testTavli('preračun kalupa bez izmene recepta na $width px', (
      tester,
    ) async {
      if (width == 320) {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
      final app = await pumpTavli(
        tester,
        location: '/recipes/r',
        size: Size(width, 1200),
        recipes: [sampleRecipe('r', 'Pita')],
      );
      await tapButton(tester, 'Preračunaj kalup');
      Future<void> enter(String key, String value) async {
        final field = find.byKey(ValueKey(key));
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
      }

      await enter('old-width', '20');
      await enter('old-height', '4');
      await enter('new-width', '30');
      await enter('new-height', '4');
      await tapButton(tester, 'Izračunaj');
      expect(find.text('Faktor: 2,25'), findsOneWidget);
      expect(find.text('1,125 kg kupus'), findsOneWidget);
      expect(find.text('biber — količina nije navedena'), findsOneWidget);
      final saved = (await app.repo.get('r'))!;
      expect(saved.ingredients.last.quantity, 0.5);
      await enter('new-width', '0');
      await tapButton(tester, 'Izračunaj');
      expect(find.text('Unesi broj veći od nule.'), findsOneWidget);
      expect(find.text('Faktor: 2,25'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testTavli('pravougaoni kalup koristi obe stranice', (tester) async {
    await pumpTavli(
      tester,
      location: '/recipes/r',
      size: const Size(800, 1400),
      recipes: [sampleRecipe('r', 'Pita')],
    );
    await tapButton(tester, 'Preračunaj kalup');
    await tester.tap(find.byType(DropdownButtonFormField<PanShape>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pravougaoni').last);
    await tester.pumpAndSettle();
    for (final entry in {
      'old-width': '20',
      'old-length': '30',
      'old-height': '2',
      'new-width': '20',
      'new-height': '2',
    }.entries) {
      final field = find.byKey(ValueKey(entry.key));
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
    await tapButton(tester, 'Izračunaj');
    expect(find.text('Faktor: 0,523599'), findsOneWidget);
  });
  testTavli('preračun zadržava napomene i za poznate i za nepoznate količine', (
    tester,
  ) async {
    final recipe = sampleRecipe('r', 'Pita').copyWith(
      ingredients: const [
        Ingredient(name: 'brašno', quantity: 100, unit: 'g', note: 'prosejano'),
        Ingredient(name: 'so', note: 'po ukusu'),
      ],
    );
    await pumpTavli(
      tester,
      location: '/recipes/r',
      size: const Size(800, 1400),
      recipes: [recipe],
    );
    await tapButton(tester, 'Preračunaj kalup');
    for (final entry in {
      'old-width': '20',
      'old-height': '4',
      'new-width': '30',
      'new-height': '4',
    }.entries) {
      final field = find.byKey(ValueKey(entry.key));
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
    await tapButton(tester, 'Izračunaj');
    expect(find.text('225 g brašno (prosejano)'), findsOneWidget);
    expect(find.text('so — količina nije navedena (po ukusu)'), findsOneWidget);
  });
}
