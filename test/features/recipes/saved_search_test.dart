import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void main() {
  for (final size in [phone, wide]) {
    testWidgets('sačuvana kombinacija se primenjuje i briše na $size', (
      tester,
    ) async {
      final app = await pumpTavli(
        tester,
        size: size,
        recipes: [
          sampleRecipe('a', 'Sarma').copyWith(prepMinutes: 25),
          sampleRecipe('b', 'Pasulj'),
        ],
      );
      app.backend.server.offline = true;
      await tester.tap(find.byTooltip('Filteri'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Do minuta'),
        '30',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Sa sastojkom'),
        'kupus',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Bez sastojka'),
        'orah',
      );
      await tester.ensureVisible(find.text('Sačuvaj pretragu'));
      await tester.tap(find.text('Sačuvaj pretragu'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Naziv pretrage'),
        'Brzo',
      );
      await tester.tap(find.text('Sačuvaj').last);
      await tester.pumpAndSettle();
      expect(
        (await app.db.select(app.db.savedRecipeSearches).get()).single.name,
        'Brzo',
      );
      await tester.tap(find.text('Primeni'));
      await tester.pumpAndSettle();
      expect(find.text('Sarma'), findsOneWidget);
      expect(find.text('Pasulj'), findsNothing);
      await tester.tap(find.byTooltip('Filteri'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Brzo'));
      await tester.tap(find.text('Brzo'));
      await tester.pumpAndSettle();
      expect(find.text('Sarma'), findsOneWidget);
      expect(find.text('Pasulj'), findsNothing);
      await tester.tap(find.byTooltip('Filteri'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Do minuta'),
            )
            .controller!
            .text,
        '30',
      );
      await tester.ensureVisible(find.byTooltip('Obriši pretragu'));
      await tester.tap(find.byTooltip('Obriši pretragu'));
      await tester.pumpAndSettle();
      expect(await app.db.select(app.db.savedRecipeSearches).get(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }
}
