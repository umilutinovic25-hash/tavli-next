import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/cook_soon_repository.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/meal_plan_repository.dart';
import 'package:tavli/data/shopping_repository.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/features/recipes/recipe_providers.dart';
import 'package:tavli/sync/synced_writer.dart';

import '../../helpers/test_app.dart';
import 'plan_calendar_test.dart' show show, today, week;

Future<(MealPlanRepository, CookSoonRepository)> repos(AppDatabase db) async {
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
  return (
    plans,
    CookSoonRepository(db, scope: scope, writer: writer, plans: plans),
  );
}

/// Plan 2–8. novembra sa ručkom i večerom; popunjeni su samo ručkovi.
Future<String> seedLunches(AppDatabase db) async {
  final (plans, _) = await repos(db);
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

Future<void> queue(AppDatabase db, List<Recipe> recipes) async {
  final (_, q) = await repos(db);
  for (final r in recipes) {
    await q.add(r);
  }
}

Future<TestApp> pumpQueue(
  WidgetTester tester, {
  Size size = phone,
  List<String> queued = const ['Sarma'],
  bool withPlan = true,
  Future<void> Function(AppDatabase db)? extra,
}) {
  final recipes = [for (final (i, t) in queued.indexed) sampleRecipe('r$i', t)];
  return pumpTavli(
    tester,
    size: size,
    location: '/plan',
    recipes: recipes,
    setup: (db) async {
      if (withPlan) await seedLunches(db);
      await queue(db, recipes);
      await extra?.call(db);
    },
    overrides: [clockProvider.overrideWithValue(() => today)],
  );
}

Future<void> openSchedule(WidgetTester tester, {String title = 'Sarma'}) async {
  await show(tester, title);
  final button = find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
    matching: find.text('Rasporedi'),
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> pickMeal(WidgetTester tester, String label) async {
  await tester.tap(
    find.widgetWithText(DropdownButtonFormField<MealType>, 'Obrok'),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testTavli('recept ide u red, a raspoređivanje na prazno mesto pravi obrok', (
    tester,
  ) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/a',
      recipes: [sampleRecipe('a', 'Sarma')],
      setup: seedLunches,
      overrides: [clockProvider.overrideWithValue(() => today)],
    );

    await tester.tap(find.byTooltip('Još opcija'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dodaj u „Uskoro kuvam“'));
    await tester.pumpAndSettle();
    expect(
      find.text('Dodato u „Uskoro kuvam“. Rasporedi ga u Planu.'),
      findsOneWidget,
    );
    expect(await app.db.select(app.db.shoppingSources).get(), hasLength(7));

    await tester.tap(find.text('Plan').last);
    await tester.pumpAndSettle();
    await show(tester, 'Uskoro kuvam');
    await openSchedule(tester);

    // Prvo slobodno mesto od danas: sreda, večera.
    expect(find.text('Sreda, 4. novembar'), findsOneWidget);
    expect(find.text('Večera'), findsWidgets);
    expect(
      find.text('Mesto je prazno; obrok dobija 4 porcije.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rasporedi'));
    await tester.pumpAndSettle();

    expect(find.text('„Sarma“ je u planu.'), findsOneWidget);
    expect(find.text('Uskoro kuvam'), findsNothing);
    expect(await app.db.select(app.db.cookSoonItems).get(), isEmpty);
    expect(await app.db.select(app.db.shoppingSources).get(), hasLength(8));
    await show(tester, 'Sarma');
  });

  testTavli('zamena postojećeg obroka ima poseban pregled', (tester) async {
    final app = await pumpQueue(tester);
    await openSchedule(tester);
    await pickMeal(tester, 'Ručak');

    expect(
      find.text('Zameniće „Ručak 4.11.“; obrok zadržava 2 porcije.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Zameni'));
    await tester.pumpAndSettle();

    expect(find.text('„Sarma“ je u planu.'), findsOneWidget);
    expect(find.text('Ručak 4.11.'), findsNothing);
    final entries = await app.db.select(app.db.mealPlanEntries).get();
    expect(entries, hasLength(7));
  });

  testTavli('zaključan obrok se ne može zameniti', (tester) async {
    await pumpQueue(
      tester,
      extra: (db) async {
        final (plans, _) = await repos(db);
        final entries = await db.select(db.mealPlanEntries).get();
        final wednesday = entries.singleWhere((e) => e.date.day == 4);
        await plans.setLocked(wednesday.id, locked: true);
      },
    );
    await openSchedule(tester);
    await pickMeal(tester, 'Ručak');

    expect(
      find.text('„Ručak 4.11.“ je zaključan i ne menja se.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Zameni'),
    );
    expect(button.onPressed, isNull);
  });

  testTavli('redosled i uklanjanje bez prevlačenja', (tester) async {
    final app = await pumpQueue(tester, queued: ['Sarma', 'Pasulj']);
    await show(tester, 'Pasulj');

    await tester.tap(find.byTooltip('Još opcija za „Pasulj“'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pomeri gore'));
    await tester.pumpAndSettle();
    final titles = [
      for (final t in tester.widgetList<ListTile>(find.byType(ListTile)))
        (t.title! as Text).data,
    ];
    expect(titles.indexOf('Pasulj'), lessThan(titles.indexOf('Sarma')));

    await tester.tap(find.byTooltip('Još opcija za „Sarma“'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ukloni iz reda'));
    await tester.pumpAndSettle();
    expect(find.text('Uklonjeno iz reda „Uskoro kuvam“.'), findsOneWidget);
    expect(
      (await app.db.select(app.db.cookSoonItems).get()).single.recipeId,
      'r1',
    );
  });

  testTavli('bez plana: red se pominje na praznom ekranu', (tester) async {
    await pumpQueue(tester, withPlan: false, queued: ['Sarma', 'Pasulj']);
    expect(
      find.textContaining('U redu „Uskoro kuvam“ čeka 2 recepta'),
      findsOneWidget,
    );
  });

  testTavli('širok ekran: red i raspoređivanje rade isto', (tester) async {
    await pumpQueue(tester, size: wide);
    await openSchedule(tester);
    expect(
      find.text('Mesto je prazno; obrok dobija 4 porcije.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rasporedi'));
    await tester.pumpAndSettle();
    expect(find.text('„Sarma“ je u planu.'), findsOneWidget);
  });
}
