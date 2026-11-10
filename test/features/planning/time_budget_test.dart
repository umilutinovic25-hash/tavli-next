import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/meal_plan_repository.dart';
import 'package:tavli/data/shopping_repository.dart';
import 'package:tavli/data/time_budget_repository.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/domain/time_budget.dart';
import 'package:tavli/features/recipes/recipe_providers.dart';
import 'package:tavli/sync/synced_writer.dart';

import '../../helpers/test_app.dart';
import 'plan_calendar_test.dart' show show, tapText, today, week;

Future<AccountScope> scopeOf(AppDatabase db) async {
  final a = await db.select(db.accounts).getSingle();
  return AccountScope(userId: a.userId, householdId: a.householdId);
}

/// Ručak svaki dan 2–8. novembra: [active]/[total] minuta (null = samo
/// staro vreme pripreme od 40 min).
Future<void> seed(
  AppDatabase db, {
  int? active,
  int? total,
  List<DayBudget> budgets = const [],
}) async {
  final scope = await scopeOf(db);
  final writer = SyncedWriter(db, accountId: scope.userId);
  final plans = MealPlanRepository(
    db,
    scope: scope,
    writer: writer,
    shopping: ShoppingRepository(db, scope: scope, writer: writer),
    clock: () => DateTime.utc(2026, 11),
  );
  final request = PlanRequest(range: week, mealTypes: const {MealType.lunch});
  await plans.approve(
    PlanDraft(
      request: request,
      proposals: {
        for (final s in request.slots)
          s: SlotProposal(
            title: 'Ručak ${s.date.day}.${s.date.month}.',
            draftRecipeKey: 'r${s.date.day}',
          ),
      },
      newRecipes: {
        for (final s in request.slots)
          'r${s.date.day}': RecipeSnapshot(
            title: 'Ručak ${s.date.day}.${s.date.month}.',
            baseServings: 2,
            prepMinutes: 40,
            activeMinutes: active,
            totalMinutes: total,
            ingredients: const [Ingredient(name: 'krompir', quantity: 1)],
          ),
      },
    ),
  );
  final repo = TimeBudgetRepository(db, scope: scope, writer: writer);
  for (final b in budgets) {
    await repo.save(b);
  }
}

Future<TestApp> pumpPlanWith(
  WidgetTester tester,
  Future<void> Function(AppDatabase db) setup, {
  Size size = phone,
  String location = '/plan',
}) => pumpTavli(
  tester,
  size: size,
  location: location,
  setup: setup,
  overrides: [clockProvider.overrideWithValue(() => today)],
);

// Sreda je 3. dan u nedelji (danas u testovima plana).
const wednesday20 = DayBudget(weekday: 3, maxActiveMinutes: 20);

void main() {
  testTavli('vreme po danu: unos limita i prozora, greška za loš prozor', (
    tester,
  ) async {
    final app = await pumpPlanWith(tester, seed);
    await tapText(tester, 'Vreme po danu');
    expect(find.text('Bez ograničenja'), findsNWidgets(7));

    await tester.tap(find.text('Utorak'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Najviše aktivnog rada po obroku (min)'),
      '20',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Kuvam od'), '18:45');
    await tester.enterText(find.widgetWithText(TextField, 'do'), '18:00');
    await tester.tap(find.widgetWithText(FilledButton, 'Sačuvaj'));
    await tester.pumpAndSettle();
    expect(find.text('Kraj prozora mora biti posle početka.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Kuvam od'), '18:00');
    await tester.enterText(find.widgetWithText(TextField, 'do'), '18:45');
    await tester.tap(find.widgetWithText(FilledButton, 'Sačuvaj'));
    await tester.pumpAndSettle();

    expect(
      find.text('do 20 min aktivnog rada · kuvanje 18:00–18:45'),
      findsOneWidget,
    );
    final row = await app.db.select(app.db.dayTimeBudgets).getSingle();
    expect((row.weekday, row.windowStart, row.windowEnd), (2, 1080, 1125));
  });

  testTavli('staro vreme pripreme: obrok tog dana je "Vreme nepoznato"', (
    tester,
  ) async {
    await pumpPlanWith(tester, (db) => seed(db, budgets: [wednesday20]));
    await show(tester, 'Ručak 4.11.');
    expect(find.text('Vreme nepoznato'), findsOneWidget);
    expect(find.text('Preko vremena'), findsNothing);
  });

  testTavli('25 aktivno uz limit 20: "Preko vremena" i razlog u obroku', (
    tester,
  ) async {
    await pumpPlanWith(
      tester,
      (db) => seed(db, active: 25, total: 30, budgets: [wednesday20]),
    );
    await show(tester, 'Ručak 4.11.');
    expect(find.text('Preko vremena'), findsOneWidget);

    await tapText(tester, 'Ručak 4.11.');
    expect(
      find.text('Preko vremena: Aktivno 25 min, limit 20 min.'),
      findsOneWidget,
    );
  });

  testTavli('15 aktivno uz limit 20 staje; drugi dani bez oznake', (
    tester,
  ) async {
    await pumpPlanWith(
      tester,
      (db) => seed(db, active: 15, total: 60, budgets: [wednesday20]),
      size: wide,
    );
    await show(tester, 'Ručak 4.11.');
    expect(find.text('Preko vremena'), findsNothing);
    expect(find.text('Vreme nepoznato'), findsNothing);
    await tapText(tester, 'Ručak 4.11.');
    expect(find.text('Staje u vreme za taj dan'), findsOneWidget);
  });

  testTavli('recept: aktivno i ukupno vreme, provera unosa', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/a/edit',
      recipes: [sampleRecipe('a', 'Sarma')],
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Aktivno vreme (min)'),
      '30',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Ukupno vreme (min)'),
      '20',
    );
    await tester.tap(find.text('Sačuvaj'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Aktivno vreme je broj minuta veći od nule i nije duže od ukupnog.',
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Aktivno vreme (min)'),
      '15',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Ukupno vreme (min)'),
      '60',
    );
    await tester.tap(find.text('Sačuvaj'));
    await tester.pumpAndSettle();

    final r = (await app.repo.get('a'))!;
    expect((r.prepMinutes, r.activeMinutes, r.totalMinutes), (45, 15, 60));
    expect(find.text('Aktivno 15 min'), findsOneWidget);
    expect(find.text('Ukupno 60 min'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
  });

  test('sreda u testovima je 3. dan', () {
    expect(CivilDate(2026, 11, 4).weekday, 3);
  });
}
