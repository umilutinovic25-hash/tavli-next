import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/meal_plan_repository.dart';
import 'package:tavli/data/shopping_repository.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/features/recipes/recipe_providers.dart';
import 'package:tavli/sync/synced_writer.dart';

import '../../helpers/test_app.dart';

/// Sreda usred plana 2–8. novembra.
final today = DateTime(2026, 11, 4, 9);

String location(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri
        .toString();

/// Sačuvan plan ručkova: `Ručak <dan>.<mesec>.` za svaki dan [range].
Future<String> seedPlan(
  AppDatabase db,
  DateRange range, {
  DateTime? createdAt,
}) async {
  final account = await db.select(db.accounts).getSingle();
  final scope = AccountScope(
    userId: account.userId,
    householdId: account.householdId,
  );
  final writer = SyncedWriter(db, accountId: scope.userId);
  final repo = MealPlanRepository(
    db,
    scope: scope,
    writer: writer,
    shopping: ShoppingRepository(db, scope: scope, writer: writer),
    clock: () => createdAt ?? DateTime.utc(2026, 11),
  );
  final request = PlanRequest(range: range, mealTypes: const {MealType.lunch});
  String key(MealSlot s) => 'ručak ${s.date.month}-${s.date.day}';
  return repo.approve(
    PlanDraft(
      request: request,
      proposals: {
        for (final s in request.slots)
          s: SlotProposal(
            title: 'Ručak ${s.date.day}.${s.date.month}.',
            draftRecipeKey: key(s),
          ),
      },
      newRecipes: {
        for (final s in request.slots)
          key(s): RecipeSnapshot(
            title: 'Ručak ${s.date.day}.${s.date.month}.',
            baseServings: 2,
            prepMinutes: 40,
            ingredients: const [
              Ingredient(name: 'krompir', quantity: 1, unit: 'kg'),
            ],
          ),
      },
    ),
  );
}

final week = DateRange(CivilDate(2026, 11, 2), CivilDate(2026, 11, 8));

Future<TestApp> pumpPlan(
  WidgetTester tester, {
  Size size = phone,
  Future<void> Function(AppDatabase db)? setup,
  List<(int, String, Map<String, List<String>>)> ai = const [],
  List<Recipe> recipes = const [],
}) => pumpTavli(
  tester,
  size: size,
  location: '/plan',
  ai: ai,
  recipes: recipes,
  setup: setup ?? (db) => seedPlan(db, week),
  overrides: [clockProvider.overrideWithValue(() => today)],
);

/// Skroluje listu plana dok se tekst ne pojavi (lista se gradi lenjo).
Future<void> show(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) {
    // Od vrha liste naniže.
    await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
    await tester.pumpAndSettle();
  }
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  expect(finder, findsWidgets);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await show(tester, text);
  await tester.ensureVisible(find.text(text).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [phone, wide]) {
    testTavli('šablon: pregled pre potvrde, sačuvan plan ($size)', (
      tester,
    ) async {
      final app = await pumpPlan(tester, size: size);
      await tapText(tester, 'Sačuvaj nedelju kao šablon');
      await tester.enterText(find.byType(TextField).last, 'Porodična');
      await tester.tap(find.text('Sačuvaj').last);
      await tester.pumpAndSettle();
      expect(await app.db.select(app.db.weekTemplates).get(), hasLength(1));
      await tapText(tester, 'Šabloni nedelje');
      expect(find.text('Pregled'), findsOneWidget);
      expect(find.text('Ručak 2.11.').last, findsWidgets);
      expect(await app.db.select(app.db.mealPlans).get(), hasLength(1));
      await tester.tap(find.text('Sačuvaj plan'));
      await tester.pumpAndSettle();
      expect(await app.db.select(app.db.mealPlans).get(), hasLength(2));
      expect(await app.db.select(app.db.mealPlanEntries).get(), hasLength(14));
    });
  }

  testTavli('telefon: nedelja je lista dana; danas je istaknut; obrok '
      'otvara recept iz plana', (tester) async {
    await pumpPlan(tester);

    expect(find.text('Otvori nabavku'), findsOneWidget);
    await show(tester, 'Sreda, 4. novembar · danas');
    expect(find.text('Ručak 2.11.'), findsOneWidget);
    expect(find.text('Napravi plan'), findsNothing);

    await tapText(tester, 'Ručak 4.11.');

    expect(location(tester), startsWith('/plan/'));
    expect(location(tester), contains('/entries/'));
    expect(find.text('Sastojci za 2 porcije · 40 min'), findsOneWidget);
    expect(find.text('• 1 kg krompir'), findsOneWidget);
    expect(find.text('Zameni jelo'), findsOneWidget);
  });

  testTavli('mesec: kompaktan kalendar, izbor dana pokazuje njegovu '
      'nedelju; Danas vraća na danas', (tester) async {
    await pumpPlan(
      tester,
      setup: (db) => seedPlan(
        db,
        DateRange(CivilDate(2026, 11, 1), CivilDate(2026, 11, 30)),
      ),
    );

    await tapText(tester, 'Mesec');
    expect(
      find.bySemanticsLabel(RegExp('Sreda, 4. novembar, 1 obrok, danas')),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel(RegExp('^Utorak, 17. novembar')));
    await tester.pumpAndSettle();
    await show(tester, 'Utorak, 17. novembar');
    await show(tester, 'Ručak 17.11.');
    expect(find.text('Ručak 4.11.'), findsNothing);

    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tapText(tester, 'Danas');
    await show(tester, 'Ručak 4.11.');
  });

  testTavli('nedelja: strelice idu kroz nedelje plana', (tester) async {
    await pumpPlan(
      tester,
      setup: (db) => seedPlan(
        db,
        DateRange(CivilDate(2026, 11, 1), CivilDate(2026, 11, 30)),
      ),
    );

    expect(find.text('2–8. novembar 2026.'), findsOneWidget);
    await tester.tap(find.byTooltip('Sledeća nedelja'));
    await tester.pumpAndSettle();
    expect(find.text('9–15. novembar 2026.'), findsOneWidget);
    await tester.tap(find.byTooltip('Prethodna nedelja'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Prethodna nedelja'));
    await tester.pumpAndSettle();
    expect(find.text('1. novembar 2026.'), findsOneWidget);
  });

  testTavli('više planova: podrazumevan je onaj sa današnjim danom; drugi '
      'se bira', (tester) async {
    await pumpPlan(
      tester,
      setup: (db) async {
        await seedPlan(db, week, createdAt: DateTime.utc(2026, 10));
        await seedPlan(
          db,
          DateRange(CivilDate(2026, 12, 7), CivilDate(2026, 12, 13)),
          createdAt: DateTime.utc(2026, 11, 3),
        );
      },
    );

    expect(find.text('Izaberi plan'), findsOneWidget);
    await show(tester, 'Ručak 4.11.');
    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7–13. decembar 2026.').last);
    await tester.pumpAndSettle();

    await show(tester, 'Ručak 7.12.');
    expect(find.text('Ručak 4.11.'), findsNothing);
  });

  testTavli('320 px i dvostruk tekst: nedelja, mesec i obrok bez '
      'odsečenog sadržaja', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpPlan(tester, size: const Size(320, 700));

    expect(find.text('Otvori nabavku'), findsOneWidget);
    await tapText(tester, 'Mesec');
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Ručak 4.11.');
    expect(find.text('Zameni jelo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testTavli('široko: kalendar i recept jedan pored drugog', (tester) async {
    await pumpPlan(tester, size: wide);

    expect(find.text('Izaberi obrok da vidiš recept.'), findsOneWidget);
    await tapText(tester, 'Ručak 4.11.');

    expect(location(tester), '/plan');
    expect(find.text('Sastojci za 2 porcije · 40 min'), findsOneWidget);
    expect(find.text('Izaberi obrok da vidiš recept.'), findsNothing);
  });

  testTavli('zaključan obrok: oznaka u kalendaru, zamena i uklanjanje '
      'nisu dostupni', (tester) async {
    await pumpPlan(tester, size: wide);
    await tapText(tester, 'Ručak 4.11.');

    await tapText(tester, 'Zaključaj');

    expect(find.text('Zaključano'), findsWidgets);
    expect(find.text('Otključaj'), findsOneWidget);
    final replace = tester.widget<ButtonStyleButton>(button('Zameni jelo'));
    expect(replace.onPressed, isNull);
  });

  testTavli('porcije obroka se menjaju i sastojci se preračunavaju', (
    tester,
  ) async {
    await pumpPlan(tester, size: wide);
    await tapText(tester, 'Ručak 4.11.');

    await tester.tap(find.byTooltip('Više porcija').last);
    await tester.pumpAndSettle();

    expect(find.text('Sastojci za 3 porcije · 40 min'), findsOneWidget);
    expect(find.text('• 1,5 kg krompir'), findsOneWidget);
  });

  testTavli('zamena receptom iz biblioteke: pregled pa prihvatanje', (
    tester,
  ) async {
    await pumpPlan(
      tester,
      size: wide,
      recipes: [sampleRecipe('lib-1', 'Sarma')],
    );
    await tapText(tester, 'Ručak 4.11.');

    await tapText(tester, 'Zameni jelo');
    await tapText(tester, 'Iz mojih recepata');
    await tapText(tester, 'Sarma');

    expect(find.text('Pregled izmena'), findsOneWidget);
    expect(find.text('Ručak 4.11. → Sarma'), findsOneWidget);
    await tapText(tester, 'Prihvati');

    expect(find.text('Jelo je zamenjeno.'), findsOneWidget);
    expect(find.text('Sarma'), findsWidgets);
    expect(find.text('Ručak 4.11.'), findsNothing);
  });

  testTavli('ponovni predlog ne dira zaključane ni prošle obroke', (
    tester,
  ) async {
    // Danas je sreda: 2. i 3. su prošli; 4. zaključavamo; menjaju se 5–8.
    final app = await pumpPlan(
      tester,
      size: wide,
      ai: [
        aiAnswer({
          'meals': [
            for (var d = 5; d <= 8; d++)
              {
                'date': '2026-11-0$d',
                'meal': 'lunch',
                'recipeId': null,
                'title': 'Novo $d',
              },
          ],
        }),
        aiAnswer({
          'recipes': [for (var d = 5; d <= 7; d++) recipeJson('Novo $d')],
        }),
        aiAnswer({
          'recipes': [recipeJson('Novo 8')],
        }),
      ],
    );
    await tapText(tester, 'Ručak 4.11.');
    await tapText(tester, 'Zaključaj');

    await tapText(tester, 'Ponovo predloži');

    expect(find.text('Pregled izmena'), findsOneWidget);
    expect(find.textContaining('umesto: Ručak 5.11.'), findsOneWidget);
    expect(find.textContaining('Ručak 4.11.'), findsNothing);
    expect(find.text('Promeni izbore'), findsNothing);
    final outline = app.adapter.requests.first.data.toString();
    expect(outline, isNot(contains('2026-11-04')));
    expect(outline, isNot(contains('2026-11-02')));

    await tapText(tester, 'Prihvati');

    expect(location(tester), '/plan');
    expect(find.text('Izmene su sačuvane.'), findsOneWidget);
    await show(tester, 'Ručak 2.11.');
    await show(tester, 'Ručak 4.11.');
    await show(tester, 'Novo 5');
    expect(find.text('Ručak 5.11.'), findsNothing);
  });
}
