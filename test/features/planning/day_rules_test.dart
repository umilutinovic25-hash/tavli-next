import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/day_rule_repository.dart';
import 'package:tavli/domain/day_rules.dart';
import 'package:tavli/features/recipes/recipe_providers.dart';
import 'package:tavli/sync/synced_writer.dart';

import '../../helpers/test_app.dart';
import 'plan_generation_test.dart' show fullWeek, today;

Future<void> addRule(
  AppDatabase db, {
  required int weekday,
  required RuleKind kind,
  String? value,
  RuleMode mode = RuleMode.required,
}) async {
  final a = await db.select(db.accounts).getSingle();
  await DayRuleRepository(
    db,
    scope: AccountScope(userId: a.userId, householdId: a.householdId),
    writer: SyncedWriter(db, accountId: a.userId),
  ).add(weekday: weekday, kind: kind, value: value, mode: mode);
}

Future<TestApp> pumpWith(
  WidgetTester tester, {
  String location = '/plan',
  Size size = phone,
  Future<void> Function(AppDatabase db)? setup,
  List<(int, String, Map<String, List<String>>)> ai = const [],
}) => pumpTavli(
  tester,
  location: location,
  size: size,
  ai: ai,
  setup: setup,
  overrides: [clockProvider.overrideWithValue(() => today)],
);

void main() {
  testTavli('pravila: dodavanje, provera naziva sastojka i brisanje', (
    tester,
  ) async {
    final app = await pumpWith(tester, location: '/plan/rules');
    expect(find.text('Još nema pravila.'), findsOneWidget);

    await tester.tap(find.text('Dodaj pravilo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sačuvaj'));
    await tester.pumpAndSettle();
    expect(find.text('Ponedeljak · bez mesa'), findsOneWidget);
    expect(find.text('Obavezno'), findsOneWidget);

    await tester.tap(find.text('Dodaj pravilo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bez mesa').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('bez sastojka').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sačuvaj'));
    await tester.pumpAndSettle();
    expect(find.text('Upiši naziv sastojka (do 40 znakova).'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Sastojak'), 'luk');
    await tester.tap(find.text('Obavezno').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sačuvaj'));
    await tester.pumpAndSettle();
    expect(find.text('Ponedeljak · bez: luk (želja)'), findsOneWidget);

    await tester.tap(find.byTooltip('Obriši pravilo „Ponedeljak · bez mesa“'));
    await tester.pumpAndSettle();
    expect(find.text('Ponedeljak · bez mesa'), findsNothing);
    expect(await app.db.select(app.db.dayRules).get(), hasLength(1));
  });

  testTavli('predlog: AI dobija pravilo, prekršaj se vidi i čuva se samo uz '
      'izuzetak za taj dan', (tester) async {
    final app = await pumpWith(
      tester,
      ai: fullWeek,
      setup: (db) =>
          addRule(db, weekday: 1, kind: RuleKind.without, value: 'luk'),
    );
    await tapButton(tester, 'Napravi plan');
    await tapButton(tester, 'Predloži plan');

    expect(
      app.adapter.requests.first.data.toString(),
      contains('Monday (all meals): without "luk" — required'),
    );
    // Ponedeljak (Jelo 1) ima crni luk; utorak nema pravilo.
    expect(
      find.text('Krši pravilo: Ponedeljak · bez: luk (crni luk)'),
      findsOneWidget,
    );

    await tapButton(tester, 'Sačuvaj plan');
    expect(
      find.text(
        'Neka jela krše obavezna pravila dana. Zameni ih ili dozvoli '
        'izuzetak.',
      ),
      findsOneWidget,
    );
    expect(await app.db.select(app.db.mealPlans).get(), isEmpty);

    await tapButton(tester, 'Dozvoli ovaj put');
    expect(
      find.text('Izuzetak: Ponedeljak · bez: luk (crni luk)'),
      findsOneWidget,
    );
    await tapButton(tester, 'Sačuvaj plan');

    expect(find.text('Plan je sačuvan.'), findsOneWidget);
    final entries = await app.db.select(app.db.mealPlanEntries).get();
    final monday = entries.singleWhere((e) => e.date.day == 2);
    expect(monday.ruleOverridesJson, contains('"'));
    expect(entries.where((e) => e.ruleOverridesJson != null), hasLength(1));
    expect(
      find.text('Izuzetak: Ponedeljak · bez: luk (crni luk)'),
      findsOneWidget,
    );
  });

  testTavli('sačuvan plan: novo pravilo pokazuje prekršaj; izuzetak se daje '
      'u obroku', (tester) async {
    final app = await pumpWith(tester, ai: fullWeek);
    await tapButton(tester, 'Napravi plan');
    await tapButton(tester, 'Predloži plan');
    await tapButton(tester, 'Sačuvaj plan');
    await addRule(app.db, weekday: 1, kind: RuleKind.fish);
    await tester.pumpAndSettle();

    expect(find.text('Krši pravilo: Ponedeljak · riba'), findsOneWidget);
    await tester.tap(find.text('Jelo 1'));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Dozvoli ovaj put');
    expect(find.text('Izuzetak: Ponedeljak · riba'), findsOneWidget);
    expect(find.text('Ukloni izuzetak'), findsOneWidget);
  });

  testTavli('širok ekran: želja ne blokira čuvanje', (tester) async {
    final app = await pumpWith(
      tester,
      size: wide,
      ai: fullWeek,
      setup: (db) => addRule(
        db,
        weekday: 1,
        kind: RuleKind.without,
        value: 'luk',
        mode: RuleMode.preferred,
      ),
    );
    await tapButton(tester, 'Napravi plan');
    await tapButton(tester, 'Predloži plan');
    expect(
      find.text('Odstupa od želje: Ponedeljak · bez: luk (želja) (crni luk)'),
      findsOneWidget,
    );
    expect(find.text('Dozvoli ovaj put'), findsNothing);
    await tapButton(tester, 'Sačuvaj plan');
    expect(await app.db.select(app.db.mealPlans).get(), hasLength(1));
  });
}
