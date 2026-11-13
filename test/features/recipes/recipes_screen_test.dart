import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/recipe.dart';

import '../../helpers/test_app.dart';

void main() {
  testTavli('prazna lista pokazuje poruku i dugme za dodavanje', (
    tester,
  ) async {
    await pumpTavli(tester);

    expect(find.text('Još nema recepata'), findsOneWidget);
    expect(
      find.text('Dodaj prvi recept iz slike, po nazivu jela ili ručno.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Dodaj recept'));
    await tester.pumpAndSettle();
    expect(find.text('Iz slike'), findsOneWidget);
    expect(find.text('Po nazivu jela'), findsOneWidget);
    expect(find.text('Ručno'), findsOneWidget);
  });

  testTavli('najnoviji prvi i pretraga bez kvačica', (tester) async {
    await pumpTavli(
      tester,
      recipes: [
        sampleRecipe('a', 'Pasulj', createdAt: DateTime(2026)),
        sampleRecipe('b', 'Šargarepa čorba', createdAt: DateTime(2026, 3)),
        sampleRecipe('c', 'Sarma', createdAt: DateTime(2026, 2)),
      ],
    );

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title! as Text).data)
        .toList();
    expect(titles, ['Šargarepa čorba', 'Sarma', 'Pasulj']);
    expect(find.text('4 porcije · 45 min'), findsNWidgets(3));

    await tester.enterText(find.byType(SearchBar), 'sar');
    await tester.pumpAndSettle();
    expect(find.text('Sarma'), findsOneWidget);
    expect(find.text('Šargarepa čorba'), findsOneWidget);
    expect(find.text('Pasulj'), findsNothing);

    await tester.enterText(find.byType(SearchBar), 'čorb');
    await tester.pumpAndSettle();
    expect(find.text('Šargarepa čorba'), findsOneWidget);
    expect(find.text('Sarma'), findsNothing);

    await tester.enterText(find.byType(SearchBar), 'musaka');
    await tester.pumpAndSettle();
    expect(find.text('Nema recepata za „musaka“.'), findsOneWidget);
  });

  testTavli('telefon: recept se otvara preko celog ekrana', (tester) async {
    await pumpTavli(
      tester,
      recipes: [sampleRecipe('a', 'Sarma').copyWith(answeredBy: 'Gemini Pro')],
    );

    await tester.tap(find.text('Sarma'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchBar), findsNothing);
    expect(find.widgetWithText(AppBar, 'Sarma'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    // Kategorije redom prodavnice, količina sa zarezom.
    final povrce = tester.getTopLeft(find.text('voće i povrće')).dy;
    final zacini = tester.getTopLeft(find.text('začini i sosovi')).dy;
    expect(povrce, lessThan(zacini));
    expect(find.text('• 0,5 kg kupus'), findsOneWidget);
    expect(find.text('Napravio: Gemini Pro'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('Umotati.'), findsOneWidget);
  });

  testTavli('recept sa koracima prikazuje deo Priprema', (tester) async {
    await pumpTavli(
      tester,
      location: '/recipes/a',
      recipes: [sampleRecipe('a', 'Sarma')],
    );
    expect(find.text('Priprema'), findsOneWidget);
  });

  testTavli('recept bez koraka i ručno unet', (tester) async {
    await pumpTavli(
      tester,
      location: '/recipes/a',
      recipes: [
        Recipe(
          id: 'a',
          title: 'Salata',
          servings: 1,
          ingredients: const [Ingredient(name: 'paradajz')],
          source: RecipeSource.manual,
          createdAt: DateTime(2026),
        ),
      ],
    );

    expect(find.text('Priprema'), findsNothing);
    expect(find.text('Koraci pripreme nisu uneti.'), findsNothing);
    expect(find.text('Ručno unet'), findsOneWidget);
    expect(find.text('1 porcija'), findsOneWidget);
  });

  testTavli('širok ekran: lista i recept jedno pored drugog', (tester) async {
    await pumpTavli(
      tester,
      size: wide,
      recipes: [
        sampleRecipe('a', 'Pasulj', createdAt: DateTime(2026)),
        sampleRecipe('b', 'Sarma', createdAt: DateTime(2026, 2)),
      ],
    );
    expect(find.text('Izaberi recept'), findsOneWidget);

    await tester.tap(find.text('Sarma'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Sarma'), findsOneWidget);
    expect(find.text('Pasulj'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    final tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Sarma'),
    );
    expect(tile.selected, isTrue);
  });
}
