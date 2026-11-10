import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/step_links.dart';

import '../../helpers/test_app.dart';

void main() {
  Future<void> send(WidgetTester tester, String text) async {
    // Poruka na dnu ekrana (SnackBar) ne sme da prekrije polje za unos.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Šta da promenim?'),
      text,
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Pošalji'));
    await tester.pumpAndSettle();
  }

  testTavli('predlog → Prihvati menja recept i čuva istoriju', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/a/chat',
      recipes: [sampleRecipe('a', 'Sarma')],
      ai: [aiAnswer(recipeJson('Posna sarma'))],
    );

    await send(tester, 'posno');

    expect(app.adapter.requests.single.data.toString(), contains('posno'));
    expect(find.text('Predlog izmene'), findsOneWidget);
    expect(await app.titles(), ['Sarma']);

    await tapButton(tester, 'Prihvati');

    expect(await app.titles(), ['Posna sarma']);
    expect(find.text('Izmena je sačuvana.'), findsOneWidget);
    expect(find.text('posno'), findsOneWidget);
    expect(find.textContaining('Gemini Pro · '), findsOneWidget);
    final version = await app.db.select(app.db.recipeVersions).getSingle();
    expect(version.changeKind, 'ai');
    expect(version.instruction, 'posno');
    expect(version.changedBy, 'Gemini Pro');

    await tester.tap(find.byTooltip('Poništi poslednju izmenu'));
    await tester.pumpAndSettle();
    expect(await app.titles(), ['Sarma']);
    expect(find.text('Izmena je poništena.'), findsOneWidget);
    expect(await app.db.select(app.db.recipeVersions).get(), isEmpty);
  });

  testTavli('AI izmena zadržava veze istih sastojaka i koraka', (tester) async {
    final linked = sampleRecipe('a', 'Sarma').copyWith(
      ingredients: const [
        Ingredient(
          id: 'i-l',
          name: 'crni luk',
          quantity: 0.5,
          unit: 'kg',
          category: 'voće i povrće',
        ),
      ],
      steps: const ['Iseckati luk.', 'Pržiti.'],
      stepUses: const [
        [StepUse(ingredientId: 'i-l', quantity: 0.5)],
      ],
    );
    final app = await pumpTavli(
      tester,
      location: '/recipes/a/chat',
      recipes: [linked],
      // AI vraća iste sastojke bez id-jeva i iste prve korake.
      ai: [aiAnswer(recipeJson('Posna sarma'))],
    );

    await send(tester, 'posno');
    await tapButton(tester, 'Prihvati');

    final saved = (await app.repo.get('a'))!;
    expect(saved.ingredients.first.id, 'i-l');
    expect(saved.steps.first, 'Iseckati luk.');
    expect(saved.usesFor(0).single.ingredientId, 'i-l');
    expect(saved.ingredients[1].id, isNull);
  });

  testTavli('Odbaci ne menja recept i vraća tekst u polje', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/a/chat',
      recipes: [sampleRecipe('a', 'Sarma')],
      ai: [aiAnswer(recipeJson('Posna sarma'))],
    );

    await send(tester, 'posno');
    await tapButton(tester, 'Odbaci');

    expect(await app.titles(), ['Sarma']);
    expect(await app.db.select(app.db.recipeVersions).get(), isEmpty);
    expect(find.widgetWithText(TextField, 'posno'), findsOneWidget);
  });

  testTavli('greška AI-ja: poruka, tekst ostaje, recept isti', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/a/chat',
      recipes: [sampleRecipe('a', 'Sarma')],
      ai: [(401, '{}', {})],
    );

    await send(tester, 'posno');

    expect(
      find.text('Nijedan model nije dostupan. Proveri ključeve.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'posno'), findsOneWidget);
    expect(await app.titles(), ['Sarma']);
  });

  testTavli('vraćanje starije verzije iz liste verzija', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/a/chat',
      recipes: [sampleRecipe('a', 'Prva')],
      ai: [aiAnswer(recipeJson('Druga')), aiAnswer(recipeJson('Treća'))],
    );
    await send(tester, 'druga');
    await tapButton(tester, 'Prihvati');
    await send(tester, 'treća');
    await tapButton(tester, 'Prihvati');
    expect(await app.titles(), ['Treća']);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Prethodne verzije'));
    await tester.pumpAndSettle();
    expect(find.text('AI izmena: „druga“'), findsOneWidget);
    expect(find.text('AI izmena: „treća“'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'AI izmena: „druga“'),
        matching: find.text('Vrati'),
      ),
    );
    await tester.pumpAndSettle();

    expect(await app.titles(), ['Prva']);
    expect(find.textContaining('Vraćena je verzija od'), findsOneWidget);

    // I vraćanje se može poništiti.
    await tester.tap(find.byTooltip('Poništi poslednju izmenu'));
    await tester.pumpAndSettle();
    expect(await app.titles(), ['Treća']);
  });
}
