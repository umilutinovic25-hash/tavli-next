import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/features/recipes/recipe_providers.dart';

import '../../helpers/test_app.dart';

/// Ponedeljak: tekuća nedelja je ceo 2–8. novembar.
final today = DateTime(2026, 11, 2, 9);

/// Raspored nedelje ručkova: "Jelo 1" … "Jelo 7".
final outline = aiAnswer({
  'meals': [
    for (var d = 2; d <= 8; d++)
      {
        'date': '2026-11-${d.toString().padLeft(2, '0')}',
        'meal': 'lunch',
        'recipeId': null,
        'title': 'Jelo ${d - 1}',
      },
  ],
});

/// Sažeci recepata u grupama po tri: 1–3, 4–6, 7.
List<(int, String, Map<String, List<String>>)> summaries(int from, int to) => [
  aiAnswer({
    'recipes': [for (var i = from; i <= to; i++) recipeJson('Jelo $i')],
  }),
];

final fullWeek = [
  outline,
  ...summaries(1, 3),
  ...summaries(4, 6),
  ...summaries(7, 7),
];

String location(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri
        .toString();

Future<TestApp> pumpPlan(
  WidgetTester tester, {
  Size size = phone,
  List<(int, String, Map<String, List<String>>)> ai = const [],
  List<Recipe> recipes = const [],
}) => pumpTavli(
  tester,
  size: size,
  location: '/plan',
  ai: ai,
  recipes: recipes,
  overrides: [clockProvider.overrideWithValue(() => today)],
);

void main() {
  for (final (name, size) in [('telefon', phone), ('široko', wide)]) {
    testTavli('$name: prvi plan bez ostave — podešavanje, pregled, '
        'pa čuvanje', (tester) async {
      final app = await pumpPlan(tester, size: size, ai: fullWeek);

      // Bez plana je glavna akcija "Napravi plan".
      expect(find.text('Još nemaš plan'), findsOneWidget);
      await tapButton(tester, 'Napravi plan');

      // Jedan ekran: period, obroci, porcije; ostava nije obavezna.
      expect(find.text('Novi plan'), findsOneWidget);
      expect(find.text('2–8. novembar 2026.'), findsOneWidget);
      expect(find.text('7 obroka · 2 porcije po obroku'), findsOneWidget);
      expect(find.text('Koristi ostavu'), findsNothing);

      await tapButton(tester, 'Predloži plan');

      // Pregled pre čuvanja: ništa još nije upisano.
      expect(find.text('Predlog plana'), findsOneWidget);
      expect(find.textContaining('Jelo 1\n'), findsOneWidget);
      expect(find.textContaining('Jelo 7\n'), findsOneWidget);
      expect(await app.db.select(app.db.mealPlans).get(), isEmpty);
      expect(app.adapter.requests, hasLength(4));

      await tapButton(tester, 'Sačuvaj plan');

      expect(location(tester), '/plan');
      expect(find.text('Plan je sačuvan.'), findsOneWidget);
      if (size.width < 1000) {
        // Naslov i kontrole ostaju čitljivi; do prvog obroka se skroluje.
        await tester.scrollUntilVisible(
          find.text('Jelo 1'),
          160,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
      }
      expect(find.text('Jelo 1'), findsOneWidget);
      expect(find.text('Otvori nabavku'), findsOneWidget);
      expect(await app.db.select(app.db.mealPlans).get(), hasLength(1));
      expect(await app.db.select(app.db.mealPlanEntries).get(), hasLength(7));
      expect(await app.titles(), containsAll(['Jelo 1', 'Jelo 7']));
    });
  }

  testTavli('izbori ostaju posle greške i povratka na podešavanje', (
    tester,
  ) async {
    await pumpPlan(tester);
    await tapButton(tester, 'Napravi plan');

    await tester.tap(find.text('Večera'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Više porcija'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Više opcija'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bez svinjetine');
    await tester.pumpAndSettle();
    expect(find.text('14 obroka · 3 porcije po obroku'), findsOneWidget);

    // AI ne odgovara: greška sa ponovnim pokušajem, bez praznog ekrana.
    await tapButton(tester, 'Predloži plan');
    expect(find.text('Nastavi'), findsOneWidget);
    expect(find.text('Sačuvaj plan'), findsNothing);

    await tapButton(tester, 'Promeni izbore');
    expect(find.text('Novi plan'), findsOneWidget);
    expect(find.text('14 obroka · 3 porcije po obroku'), findsOneWidget);
    expect(find.text('bez svinjetine'), findsOneWidget);
  });

  testTavli('pala grupa: gotov deo ostaje, nastavak traži samo ono što '
      'nedostaje', (tester) async {
    final app = await pumpPlan(tester, ai: [outline, ...summaries(1, 3)]);
    await tapButton(tester, 'Napravi plan');
    await tapButton(tester, 'Predloži plan');

    expect(find.textContaining('Gotovo je 3 od 7'), findsOneWidget);
    expect(find.text('4 obroka ostaje prazno.'), findsOneWidget);
    expect(find.text('Sačuvaj nepotpun plan'), findsOneWidget);
    final before = app.adapter.requests.length;

    app.adapter.responses.addAll([...summaries(4, 6), ...summaries(7, 7)]);
    await tapButton(tester, 'Nastavi generisanje');

    expect(app.adapter.requests.length - before, 2);
    expect(find.text('Sačuvaj plan'), findsOneWidget);
    expect(await app.db.select(app.db.mealPlans).get(), isEmpty);
  });

  testTavli('nepotpun plan se čuva samo izričito i pokazuje prazna '
      'mesta', (tester) async {
    final app = await pumpPlan(tester, ai: [outline, ...summaries(1, 3)]);
    await tapButton(tester, 'Napravi plan');
    await tapButton(tester, 'Predloži plan');

    await tapButton(tester, 'Sačuvaj nepotpun plan');

    expect(location(tester), '/plan');
    expect(find.text('Nepotpun plan je sačuvan.'), findsOneWidget);
    expect(await app.db.select(app.db.mealPlanEntries).get(), hasLength(3));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.text('Nije planirano'), findsWidgets);
  });

  testTavli('odbačen predlog ne menja ništa', (tester) async {
    final app = await pumpPlan(tester, ai: fullWeek);
    await tapButton(tester, 'Napravi plan');
    await tapButton(tester, 'Predloži plan');

    await tapButton(tester, 'Odbaci');
    expect(find.text('Odbaciti predlog?'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: button('Odbaci')),
    );
    await tester.pumpAndSettle();

    expect(location(tester), '/plan');
    expect(find.text('Još nemaš plan'), findsOneWidget);
    expect(await app.db.select(app.db.mealPlans).get(), isEmpty);
    expect(await app.titles(), isEmpty);
    expect(await app.db.select(app.db.shoppingItems).get(), isEmpty);
    expect(await app.db.select(app.db.syncOutbox).get(), isEmpty);
  });

  group('zamena jednog jela u predlogu', () {
    /// Otvara izbor zamene za [index]-to jelo u predlogu.
    Future<void> openReplace(WidgetTester tester, int index) async {
      final replace = find.byTooltip('Zameni jelo').at(index);
      await tester.ensureVisible(replace);
      await tester.pumpAndSettle();
      await tester.tap(replace);
      await tester.pumpAndSettle();
    }

    testTavli('AI predlaže drugo jelo samo za taj obrok', (tester) async {
      final app = await pumpPlan(
        tester,
        ai: [
          ...fullWeek,
          aiAnswer({
            'meals': [
              {
                'date': '2026-11-04',
                'meal': 'lunch',
                'recipeId': null,
                'title': 'Pasulj',
              },
            ],
          }),
          aiAnswer({
            'recipes': [recipeJson('Pasulj')],
          }),
        ],
      );
      await tapButton(tester, 'Napravi plan');
      await tapButton(tester, 'Predloži plan');
      final before = app.adapter.requests.length;

      await openReplace(tester, 2);
      await tester.tap(find.text('Predloži drugo'));
      await tester.pumpAndSettle();

      expect(find.text('Jelo je zamenjeno.'), findsOneWidget);
      expect(find.textContaining('Pasulj\n'), findsOneWidget);
      expect(find.textContaining('Jelo 3\n'), findsNothing);
      expect(find.textContaining('Jelo 2\n'), findsOneWidget);
      expect(find.textContaining('Jelo 4\n'), findsOneWidget);
      // Samo raspored za jedno mesto i sastojci novog jela.
      expect(app.adapter.requests.length - before, 2);
      expect(app.adapter.requests[before].data.toString(), contains('Jelo 3'));
      expect(await app.db.select(app.db.mealPlans).get(), isEmpty);

      await tapButton(tester, 'Sačuvaj plan');
      final titles = await app.titles();
      expect(titles, contains('Pasulj'));
      expect(titles, isNot(contains('Jelo 3')));
      expect(await app.db.select(app.db.mealPlanEntries).get(), hasLength(7));
    });

    testTavli('recept iz biblioteke zamenjuje predloženo jelo', (tester) async {
      final app = await pumpPlan(
        tester,
        ai: fullWeek,
        recipes: [sampleRecipe('lib-1', 'Sarma')],
      );
      await tapButton(tester, 'Napravi plan');
      await tapButton(tester, 'Predloži plan');

      await openReplace(tester, 0);
      await tester.tap(find.text('Iz mojih recepata'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sarma'));
      await tester.pumpAndSettle();

      expect(find.text('Jelo je zamenjeno.'), findsOneWidget);
      expect(find.textContaining('Sarma\nIz mojih recepata'), findsOneWidget);
      expect(find.textContaining('Jelo 1\n'), findsNothing);

      await tapButton(tester, 'Sačuvaj plan');
      final entries = await app.db.select(app.db.mealPlanEntries).get();
      expect(entries, hasLength(7));
      expect(entries.where((e) => e.recipeId == 'lib-1'), hasLength(1));
      expect(await app.titles(), isNot(contains('Jelo 1')));
    });

    testTavli('kad AI ne uspe, predlog ostaje kakav je bio', (tester) async {
      final app = await pumpPlan(tester, ai: fullWeek);
      await tapButton(tester, 'Napravi plan');
      await tapButton(tester, 'Predloži plan');

      await openReplace(tester, 2);
      await tester.tap(find.text('Predloži drugo'));
      await tester.pumpAndSettle();

      expect(find.text('Jelo je zamenjeno.'), findsNothing);
      expect(find.textContaining('Jelo 3\n'), findsOneWidget);
      await tapButton(tester, 'Sačuvaj plan');
      expect(await app.titles(), contains('Jelo 3'));
    });
  });
}
