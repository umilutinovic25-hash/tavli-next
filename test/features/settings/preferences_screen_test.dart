import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/data/database.dart';

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
    expect(find.text('Moje alergije'), findsOneWidget);
  });

  testTavli('ishrana i broj osoba u domaćinstvu, alergije u mom redu', (
    tester,
  ) async {
    final app = await pumpTavli(tester, location: '/profile/preferences');
    expect(find.text('Nema stavki.'), findsNWidgets(2));
    expect(
      find.text('Niko u domaćinstvu nije upisao alergije.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.widgetWithText(FilterChip, 'veganska'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'veganska'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(FilterChip, 'kikiriki'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'kikiriki'));
    await tester.pumpAndSettle();

    await typeIn(tester, 'Dodaj alergiju', '  Orasi ');
    await tapTip(tester, 'Dodaj alergiju');
    expect(find.widgetWithText(InputChip, 'orasi'), findsOneWidget);

    await tapTip(tester, 'Više osoba');
    expect(find.text('3'), findsOneWidget);

    final row = await app.db.select(app.db.householdPreferences).getSingle();
    expect(row.dietJson, '["vegan"]');
    expect(row.allergiesJson, '[]');
    expect(row.servings, 3);
    final mine = await app.db.select(app.db.memberAllergies).getSingle();
    expect(mine.id, '${app.scope.householdId}:${app.scope.userId}');
    expect(mine.codesJson, '["peanuts"]');
    expect(mine.customJson, '["orasi"]');
    expect(find.text('Važi za sve obroke: kikiriki, orasi'), findsOneWidget);
  });

  for (final width in [400.0, 1200.0]) {
    testTavli('alergije drugih članova važe za sve obroke na $width px', (
      tester,
    ) async {
      await pumpTavli(
        tester,
        location: '/profile/preferences',
        size: Size(width, 1600),
        setup: (db) async {
          final hh = (await db.select(db.accounts).getSingle()).householdId;
          await db
              .into(db.memberAllergies)
              .insert(
                MemberAllergiesCompanion.insert(
                  id: '$hh:drugi',
                  householdId: Value(hh),
                  userId: 'drugi',
                  codesJson: const Value('["gluten"]'),
                  customJson: const Value('["kivi"]'),
                ),
              );
        },
      );
      expect(find.text('Važi za sve obroke: gluten, kivi'), findsOneWidget);
      // Tuđe alergije se ne menjaju ovde: moji čipovi nisu izabrani.
      final gluten = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'gluten'),
      );
      expect(gluten.selected, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

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
