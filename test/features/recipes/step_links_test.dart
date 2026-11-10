import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/step_links.dart';

import '../../helpers/test_app.dart';

Recipe testo({List<List<StepUse>>? uses}) => Recipe(
  id: 't',
  title: 'Testo',
  servings: 4,
  ingredients: const [
    Ingredient(id: 'i-b', name: 'brašno', quantity: 500, unit: 'g'),
    Ingredient(id: 'i-j', name: 'jaja', quantity: 3),
  ],
  steps: const ['Prosejati brašno.', 'Umutiti jaja.', 'Dodati ostatak.'],
  stepUses:
      uses ??
      const [
        [StepUse(ingredientId: 'i-b', quantity: 300)],
        [StepUse(ingredientId: 'i-j')],
        [StepUse(ingredientId: 'i-b', quantity: 200)],
      ],
  source: RecipeSource.manual,
  createdAt: DateTime.utc(2026),
);

Finder field(String label) => find.widgetWithText(TextField, label);
Finder inDialog(Finder f) =>
    find.descendant(of: find.byType(AlertDialog), matching: f);

Future<void> saveDialog(WidgetTester tester) async {
  await tester.tap(inDialog(button('Sačuvaj')));
  await tester.pumpAndSettle();
}

Future<void> link(
  WidgetTester tester,
  int step,
  String ingredientLine, {
  String? quantity,
}) async {
  final target = find.bySemanticsLabel('Poveži sastojke sa korakom $step');
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  await tester.tap(inDialog(find.text(ingredientLine)));
  await tester.pumpAndSettle();
  if (quantity != null) {
    await tester.enterText(
      inDialog(field('Količina u ovom koraku (nije obavezno)')),
      quantity,
    );
  }
  await saveDialog(tester);
}

void main() {
  testTavli('ručni recept: brašno podeljeno na dva koraka, prikaz uz korake', (
    tester,
  ) async {
    final app = await pumpTavli(tester, location: '/recipes/new/manual');
    await tester.enterText(field('Naziv'), 'Testo');
    await tapButton(tester, 'Dodaj sastojak');
    await tester.enterText(inDialog(field('Naziv')), 'brašno');
    await tester.enterText(inDialog(field('Količina')), '500');
    await tester.enterText(inDialog(field('Jedinica')), 'g');
    await tester.pump();
    await saveDialog(tester);
    await tester.enterText(
      field('Koraci pripreme (jedan po redu)'),
      'Prosejati brašno.\nDodati ostatak.',
    );
    await tester.pumpAndSettle();

    await link(tester, 1, '500 g brašno', quantity: '300');
    await link(tester, 2, '500 g brašno', quantity: '200');
    expect(find.text('↳ 300 g brašno'), findsOneWidget);

    // Premeštanje koraka u polju: veze idu za tekstom.
    await tester.enterText(
      field('Koraci pripreme (jedan po redu)'),
      'Dodati ostatak.\nProsejati brašno.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sačuvaj'));
    await tester.pumpAndSettle();

    final saved = (await app.repo.getAll()).single;
    expect(saved.steps, ['Dodati ostatak.', 'Prosejati brašno.']);
    expect(saved.usesFor(0).single.quantity, 200);
    expect(saved.usesFor(1).single.quantity, 300);
    expect(saved.ingredients.single.id, isNotNull);
    expect(find.text('↳ 200 g brašno'), findsOneWidget);
    expect(find.text('↳ 300 g brašno'), findsOneWidget);
    expect(find.textContaining('koraci koriste'), findsNothing);
  });

  testTavli('detalji: upotreba bez količine i sukob od 600 g', (tester) async {
    await pumpTavli(
      tester,
      location: '/recipes/t',
      recipes: [
        testo(
          uses: const [
            [StepUse(ingredientId: 'i-b', quantity: 300)],
            [StepUse(ingredientId: 'i-j')],
            [StepUse(ingredientId: 'i-b', quantity: 300)],
          ],
        ),
      ],
    );
    expect(find.text('↳ jaja'), findsOneWidget);
    expect(find.text('↳ 300 g brašno'), findsNWidgets(2));
    expect(
      find.text('„brašno“: koraci koriste 600 g, a recept ima 500 g.'),
      findsOneWidget,
    );
    expect(find.text('• 500 g brašno'), findsOneWidget);
  });

  testTavli('uklanjanje korišćenog sastojka traži potvrdu i ostavlja '
      'vidljivu vezu', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/t/edit',
      recipes: [testo()],
    );

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('3 jaja'),
          matching: find.byType(ListTile),
        ),
        matching: find.byTooltip('Ukloni sastojak'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ukloniti „jaja“?'), findsOneWidget);
    await tester.tap(inDialog(button('Ukloni')));
    await tester.pumpAndSettle();

    expect(find.text('↳ Sastojak više nije u receptu'), findsOneWidget);
    await tester.tap(find.text('Sačuvaj'));
    await tester.pumpAndSettle();

    final saved = await app.repo.get('t');
    expect(saved!.ingredients.map((i) => i.name), ['brašno']);
    expect(saved.usesFor(1).single.ingredientId, 'i-j');
    expect(find.text('↳ Sastojak više nije u receptu'), findsOneWidget);
  });

  testTavli('otkazana potvrda ne uklanja sastojak', (tester) async {
    await pumpTavli(tester, location: '/recipes/t/edit', recipes: [testo()]);
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('500 g brašno'),
          matching: find.byType(ListTile),
        ),
        matching: find.byTooltip('Ukloni sastojak'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Koristi se u 2 koraka.'), findsOneWidget);
    await tester.tap(inDialog(button('Otkaži')));
    await tester.pumpAndSettle();
    expect(find.text('500 g brašno'), findsOneWidget);
  });
}
