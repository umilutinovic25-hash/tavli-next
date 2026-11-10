import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/meal_plan_repository.dart';
import 'package:tavli/data/shopping_repository.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/sync/synced_writer.dart';

import '../../helpers/test_app.dart';
import 'plan_calendar_test.dart' show pumpPlan, show, tapText, week;

/// Plan 2–8. novembra sa ručkom i večerom; popunjeni su samo ručkovi.
Future<String> seedLunches(AppDatabase db) async {
  final account = await db.select(db.accounts).getSingle();
  final scope = AccountScope(
    userId: account.userId,
    householdId: account.householdId,
  );
  final writer = SyncedWriter(db, accountId: scope.userId);
  final plans = MealPlanRepository(
    db,
    scope: scope,
    writer: writer,
    shopping: ShoppingRepository(db, scope: scope, writer: writer),
    clock: () => DateTime.utc(2026, 11),
  );
  final request = PlanRequest(
    range: week,
    mealTypes: const {MealType.lunch, MealType.dinner},
  );
  final lunches = [
    for (final s in request.slots)
      if (s.type == MealType.lunch) s,
  ];
  return plans.approve(
    PlanDraft(
      request: request,
      proposals: {
        for (final s in lunches)
          s: SlotProposal(
            title: 'Ručak ${s.date.day}.${s.date.month}.',
            draftRecipeKey: 'r${s.date.day}',
          ),
      },
      newRecipes: {
        for (final s in lunches)
          'r${s.date.day}': RecipeSnapshot(
            title: 'Ručak ${s.date.day}.${s.date.month}.',
            baseServings: 2,
            ingredients: const [Ingredient(name: 'krompir', quantity: 1)],
          ),
      },
    ),
    allowPartial: true,
  );
}

Future<void> saveAway(
  WidgetTester tester,
  String reason, {
  String? note,
}) async {
  expect(find.text('Obrok van kuće'), findsWidgets);
  await tester.tap(find.widgetWithText(ChoiceChip, reason));
  await tester.pumpAndSettle();
  if (note != null) {
    await tester.enterText(
      find.widgetWithText(TextField, 'Napomena (nije obavezno)'),
      note,
    );
  }
  await tester.tap(find.widgetWithText(FilledButton, 'Sačuvaj'));
  await tester.pumpAndSettle();
}

void main() {
  testTavli('obrok postaje restoran: izlazi iz nabavke, jelo se vraća', (
    tester,
  ) async {
    final app = await pumpPlan(tester);
    expect(await app.db.select(app.db.shoppingSources).get(), hasLength(7));

    await tapText(tester, 'Ručak 4.11.');
    await tester.ensureVisible(find.text('Obrok van kuće'));
    await tester.tap(find.text('Obrok van kuće'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        '„Ručak 4.11.“ izlazi iz nabavke; kupljeno ostaje. Jelo možeš da '
        'vratiš.',
      ),
      findsOneWidget,
    );
    await saveAway(tester, 'Restoran', note: 'sa kolegama');

    expect(find.text('Ručak je „Restoran“.'), findsOneWidget);
    expect(find.text('Restoran · sa kolegama'), findsOneWidget);
    expect(find.text('Zameni jelom'), findsOneWidget);
    expect(await app.db.select(app.db.shoppingSources).get(), hasLength(6));

    await tester.tap(find.text('Vrati „Ručak 4.11.“'));
    await tester.pumpAndSettle();
    expect(find.text('Vraćeno: „Ručak 4.11.“.'), findsOneWidget);
    expect(find.text('Obrok van kuće'), findsOneWidget);
    expect(await app.db.select(app.db.shoppingSources).get(), hasLength(7));
  });

  testTavli('prazno mesto: preskačem zauzima mesto; Poništi ga oslobađa', (
    tester,
  ) async {
    final app = await pumpPlan(tester, setup: seedLunches);
    await show(tester, 'Sreda, 4. novembar · danas');
    final before = (await app.db.select(app.db.shoppingSources).get()).length;

    await tester.ensureVisible(find.text('Nije planirano').first);
    await tester.tap(find.text('Nije planirano').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Mesto je zauzeto i ništa se ne dodaje u nabavku.'),
      findsOneWidget,
    );
    await saveAway(tester, 'Preskačem');

    expect(find.text('Večera je „Preskačem“.'), findsOneWidget);
    expect(find.text('Preskačem'), findsOneWidget);
    expect(find.text('Van kuće'), findsOneWidget);
    expect((await app.db.select(app.db.shoppingSources).get()).length, before);

    await tester.tap(find.text('Poništi'));
    await tester.pumpAndSettle();
    expect(find.text('Preskačem'), findsNothing);
    expect(find.text('Van kuće'), findsNothing);
  });

  testTavli('zaključan obrok ne može van kuće', (tester) async {
    await pumpPlan(tester);
    await tapText(tester, 'Ručak 4.11.');
    await tester.ensureVisible(find.text('Zaključaj'));
    await tester.tap(find.text('Zaključaj'));
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Obrok van kuće'),
    );
    expect(button.onPressed, isNull);
  });

  testTavli('širok ekran: obrok van kuće u desnom delu', (tester) async {
    await pumpPlan(tester, size: wide);
    await tapText(tester, 'Ručak 4.11.');
    await tester.ensureVisible(find.text('Obrok van kuće'));
    await tester.tap(find.text('Obrok van kuće'));
    await tester.pumpAndSettle();
    await saveAway(tester, 'Kod roditelja');

    expect(find.text('Kod roditelja'), findsWidgets);
    expect(find.text('Vrati „Ručak 4.11.“'), findsOneWidget);
  });
}
