import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

/// Skroluje do elementa pa ga pritisne (ekran je viši od telefona u testu).
Future<void> tapTip(WidgetTester tester, String tooltip) async {
  await tester.ensureVisible(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}

Future<void> typeIn(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(find.widgetWithText(TextField, label));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, label), text);
}

void main() {
  testTavli('profil vodi na Preferencije', (tester) async {
    await pumpTavli(tester, location: '/profile');
    await tester.tap(find.text('Preferencije'));
    await tester.pumpAndSettle();
    expect(find.text('Ishrana'), findsOneWidget);
    expect(find.text('Alergije'), findsOneWidget);
  });

  testTavli('ishrana, alergije i broj osoba se čuvaju u bazi', (tester) async {
    final app = await pumpTavli(tester, location: '/profile/preferences');
    expect(find.text('Nema stavki.'), findsNWidgets(2));

    await tester.ensureVisible(find.widgetWithText(FilterChip, 'veganska'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'veganska'));
    await tester.pumpAndSettle();

    await typeIn(tester, 'Dodaj alergiju', '  Orasi ');
    await tapTip(tester, 'Dodaj alergiju');
    expect(find.widgetWithText(InputChip, 'orasi'), findsOneWidget);

    await tapTip(tester, 'Više osoba');
    expect(find.text('3'), findsOneWidget);

    final row = await app.db.select(app.db.householdPreferences).getSingle();
    expect(row.dietJson, '["vegan"]');
    expect(row.allergiesJson, '["orasi"]');
    expect(row.servings, 3);
  });

  testTavli('stavka se briše sa čipa; predugačka stavka se odbija', (
    tester,
  ) async {
    final app = await pumpTavli(tester, location: '/profile/preferences');
    await typeIn(tester, 'Dodaj namirnicu', 'pasulj');
    await tapTip(tester, 'Dodaj namirnicu');
    expect(find.widgetWithText(InputChip, 'pasulj'), findsOneWidget);

    await typeIn(tester, 'Dodaj namirnicu', 'a' * 41);
    await tapTip(tester, 'Dodaj namirnicu');
    expect(find.text('Najviše 40 znakova.'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'pasulj'), findsOneWidget);

    // Dugme za brisanje čipa (ikonica) nije uvek u stablu u testu, pa se
    // poziva ista akcija koju bi dodir pokrenuo.
    final chip = tester.widget<InputChip>(
      find.widgetWithText(InputChip, 'pasulj'),
    );
    chip.onDeleted!();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'pasulj'), findsNothing);
    final row = await app.db.select(app.db.householdPreferences).getSingle();
    expect(row.dislikesJson, '[]');
  });

  testTavli('broj osoba ne ide ispod 1', (tester) async {
    await pumpTavli(tester, location: '/profile/preferences');
    await tapTip(tester, 'Manje osoba');
    expect(find.text('1'), findsOneWidget);
    final minus = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.remove),
    );
    expect(minus.onPressed, isNull);
  });
}
