import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/recipe_labels.dart';
import 'package:tavli_ui/tavli_ui.dart';

import '../../helpers/test_app.dart';

void main() {
  testTavli('semantička pretraga objašnjava slanje sadržaja pre aktivacije', (
    tester,
  ) async {
    await pumpTavli(tester, recipes: [sampleRecipe('a', 'Pasulj')]);

    await tester.tap(find.bySemanticsLabel('Pretraži po smislu'));
    await tester.pumpAndSettle();

    expect(find.text('Pretraga preko OpenAI-ja'), findsOneWidget);
    expect(find.textContaining('biće poslati OpenAI-ju'), findsOneWidget);
    await tester.tap(find.text('Otkaži'));
    await tester.pumpAndSettle();
    expect(find.text('Pasulj'), findsOneWidget);
  });

  testTavli('prazna lista pokazuje poruku i dugme za dodavanje', (
    tester,
  ) async {
    await pumpTavli(tester);

    expect(find.text('Još nema recepata'), findsOneWidget);
    expect(
      find.text('Dodaj prvi recept sa slike, po nazivu jela ili ručno.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Dodaj recept'));
    await tester.pumpAndSettle();
    expect(find.text('Sa slike'), findsOneWidget);
    expect(find.text('Slikaj ili izaberi sliku recepta'), findsOneWidget);
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

    final titles = [
      'Šargarepa čorba',
      'Sarma',
      'Pasulj',
    ].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
    final sorted = [...titles]..sort();
    expect(titles, sorted, reason: 'najnoviji recept je prvi');
    expect(find.text('45 min · 4 porcije'), findsNWidgets(3));

    await tester.enterText(find.byType(TavliSearchField), 'sar');
    await tester.pumpAndSettle();
    expect(find.text('Sarma'), findsOneWidget);
    expect(find.text('Šargarepa čorba'), findsOneWidget);
    expect(find.text('Pasulj'), findsNothing);

    await tester.enterText(find.byType(TavliSearchField), 'čorb');
    await tester.pumpAndSettle();
    expect(find.text('Šargarepa čorba'), findsOneWidget);
    expect(find.text('Sarma'), findsNothing);

    await tester.enterText(find.byType(TavliSearchField), 'musaka');
    await tester.pumpAndSettle();
    expect(find.text('Nema recepata za „musaka“.'), findsOneWidget);
  });

  testTavli('promena širine čuva pretragu, njen fokus i položaj liste', (
    tester,
  ) async {
    await pumpTavli(
      tester,
      size: const Size(719, 680),
      recipes: [for (var i = 0; i < 20; i++) sampleRecipe('r$i', 'Sarma $i')],
    );
    await tester.enterText(find.byType(TavliSearchField), 'Sarma');
    await tester.pumpAndSettle();
    final list = find.descendant(
      of: find.byKey(const PageStorageKey('recipes-list')),
      matching: find.byType(Scrollable),
    );
    await tester.drag(list, const Offset(0, -350));
    await tester.pumpAndSettle();
    final pixels = tester.state<ScrollableState>(list).position.pixels;
    expect(pixels, greaterThan(0));

    // Uz bočnu traku od 220 sadržaj je širok 500, 880, 780, 980 i 719:
    // lista, mreža, lista, mreža, lista.
    for (final (width, grid) in [
      (720.0, false),
      (1100.0, true),
      (1000.0, false),
      (1200.0, true),
      (719.0, false),
    ]) {
      tester.view.physicalSize = Size(width, 680);
      await tester.pumpAndSettle();
      expect(currentTab(tester), 'Recepti');
      final input = tester.widget<EditableText>(find.byType(EditableText));
      expect(input.controller.text, 'Sarma');
      expect(input.focusNode.hasFocus, isTrue, reason: 'width: $width');
      expect(
        find.byKey(const PageStorageKey('recipes-grid')),
        grid ? findsOneWidget : findsNothing,
        reason: 'width: $width',
      );
      if (!grid) {
        expect(
          tester.state<ScrollableState>(list).position.pixels,
          closeTo(pixels, 1),
          reason: 'width: $width',
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testTavli('telefon: recept se otvara preko celog ekrana', (tester) async {
    await pumpTavli(
      tester,
      recipes: [sampleRecipe('a', 'Sarma').copyWith(answeredBy: 'Gemini Pro')],
    );

    await tester.tap(find.text('Sarma'));
    await tester.pumpAndSettle();

    expect(find.byType(TavliSearchField), findsNothing);
    expect(recipeHeading('Sarma'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    // Kategorije redom prodavnice, količina sa zarezom.
    final povrce = tester.getTopLeft(find.text('VOĆE I POVRĆE')).dy;
    final zacini = tester.getTopLeft(find.text('ZAČINI I SOSOVI')).dy;
    expect(povrce, lessThan(zacini));
    expect(find.text('kupus'), findsOneWidget);
    expect(find.text('0,5 kg'), findsOneWidget);
    expect(find.text('Napravio: Gemini Pro'), findsOneWidget);
    expect(find.text('Priprema'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Umotati.'), findsOneWidget);
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
    expect(find.text('paradajz'), findsOneWidget);
    expect(find.text('Ručno unet'), findsOneWidget);
    expect(find.text('1 porcija'), findsOneWidget);
  });

  testTavli('duga jedinica se prelama pored sastojka na 320 px i 2×', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const name = 'belo brašno';
    const unit = 'velikih i vrhom punih šolja za čaj';
    await pumpTavli(
      tester,
      size: const Size(320, 800),
      location: '/recipes/a',
      recipes: [
        sampleRecipe('a', 'Hleb').copyWith(
          ingredients: const [Ingredient(name: name, quantity: 2, unit: unit)],
        ),
      ],
    );

    final nameBounds = tester.getRect(find.text(name));
    final quantityBounds = tester.getRect(find.text('2 $unit'));
    expect(nameBounds.width, greaterThan(quantityBounds.width));
    expect(quantityBounds.left, greaterThan(nameBounds.right));
    expect(quantityBounds.right, lessThan(320));
    expect(quantityBounds.height, greaterThan(nameBounds.height));
    expect(tester.takeException(), isNull);
  });

  testTavli('oznake: neoznačen recept, izmena i čuvanje', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/a',
      recipes: [sampleRecipe('a', 'Sarma')],
    );

    expect(find.text('Oznake'), findsOneWidget);
    expect(
      find.textContaining('Nije označeno', findRichText: true),
      findsNWidgets(3),
    );

    await tester.tap(find.text('Izmeni oznake'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Ručak'));
    await tester.tap(find.widgetWithText(FilterChip, 'Večera'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Jak'));
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Kuvano jelo'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Kuvano jelo'));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Sačuvaj');

    expect(find.text('Oznake su sačuvane.'), findsOneWidget);
    expect(
      find.text('Obrok: Ručak, Večera', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Težina: Jak', findRichText: true), findsOneWidget);
    expect(
      find.text('Vrsta jela: Kuvano jelo', findRichText: true),
      findsOneWidget,
    );
    final row = await app.db.select(app.db.recipes).getSingle();
    expect(row.labelsSource, 'user');
    expect(await app.db.select(app.db.recipeVersions).get(), isEmpty);
  });

  testTavli('oznake: Otkaži ne menja ništa', (tester) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/a',
      recipes: [sampleRecipe('a', 'Sarma')],
    );
    await tester.tap(find.text('Izmeni oznake'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Ručak'));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Otkaži');

    expect(
      find.textContaining('Nije označeno', findRichText: true),
      findsNWidgets(3),
    );
    final row = await app.db.select(app.db.recipes).getSingle();
    expect(row.labelsSource, isNull);
  });

  for (final size in [const Size(320, 700), wide]) {
    testTavli('${size.width} px, tekst 2×: izmena oznaka bez preliva', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpTavli(
        tester,
        size: size,
        location: '/recipes/a',
        recipes: [sampleRecipe('a', 'Sarma')],
      );
      await tester.ensureVisible(find.text('Izmeni oznake'));
      await tester.tap(find.text('Izmeni oznake'));
      await tester.pumpAndSettle();

      expect(find.byType(ChoiceChip), findsNWidgets(12));
      expect(tester.takeException(), isNull);
    });
  }

  for (final (label, size) in [('telefon', phone), ('širok ekran', wide)]) {
    testTavli('recept bez koraka: $label, tekst 2× i smanjeno kretanje', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpTavli(
        tester,
        size: size,
        location: '/recipes/a',
        recipes: [sampleRecipe('a', 'Sarma').copyWith(steps: [])],
      );

      expect(find.text('Sastojci'), findsOneWidget);
      expect(find.text('Priprema'), findsNothing);
      expect(find.text('Koraci pripreme nisu uneti.'), findsNothing);
    });
  }

  testTavli(
    'širok ekran: zaglavlje u jednom redu i mreža, recept je ceo ekran',
    (tester) async {
      await pumpTavli(
        tester,
        size: wide,
        recipes: [
          sampleRecipe('a', 'Pasulj', createdAt: DateTime(2026)),
          sampleRecipe('b', 'Sarma', createdAt: DateTime(2026, 2)),
        ],
      );
      // Platno, macOS · Recepti: naslov, pretraga i „Dodaj recept“ u istom
      // redu, ispod mreža kartica sa slikom na vrhu.
      expect(find.byType(TavliCardGrid), findsOneWidget);
      expect(find.byType(TavliFloatingButton), findsNothing);
      final title = tester.getCenter(find.text('Recepti').last).dy;
      expect(tester.getCenter(find.byType(TavliSearchField)).dy, title);
      expect(tester.getCenter(button('Dodaj recept')).dy, title);
      final pasulj = tester.getTopLeft(find.text('Pasulj'));
      final sarma = tester.getTopLeft(find.text('Sarma'));
      expect(pasulj.dy, sarma.dy, reason: 'kartice su u istom redu mreže');

      await tester.tap(find.text('Sarma'));
      await tester.pumpAndSettle();

      // Recept se otvara kao ceo ekran, bez liste pored.
      expect(recipeHeading('Sarma'), findsOneWidget);
      expect(find.text('Pasulj'), findsNothing);
      expect(find.byType(TavliSearchField), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
    },
  );

  testTavli('detalj: veliki naslov, AI izmena je u meniju', (tester) async {
    await pumpTavli(
      tester,
      location: '/recipes/a',
      recipes: [sampleRecipe('a', 'Sarma')],
    );
    final title = tester.widget<Text>(find.text('Sarma'));
    expect(
      title.style?.fontSize,
      Theme.of(tester.element(find.text('Sarma')))
          .textTheme
          .headlineSmall
          ?.fontSize,
    );
    expect(iconButton('Izmeni sa AI'), findsNothing);
    await tester.tap(iconButton('Još opcija'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Izmeni sa AI'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Šta da promenim?'), findsOneWidget);
  });

  testTavli('tablet: recepti u jednoj koloni, kao na telefonu', (tester) async {
    await pumpTavli(
      tester,
      size: const Size(820, 1180),
      recipes: [
        sampleRecipe('a', 'Sarma', createdAt: DateTime.utc(2026, 11, 2)),
        sampleRecipe('b', 'Pasulj'),
      ],
    );
    final first = tester.getTopLeft(find.text('Sarma'));
    final second = tester.getTopLeft(find.text('Pasulj'));
    expect(second.dx, first.dx);
    expect(second.dy, greaterThan(first.dy));
    expect(tester.takeException(), isNull);
  });

  group('filteri (TRELLO-102)', () {
    List<Recipe> labelled() => [
      sampleRecipe('a', 'Sarma').copyWith(
        labels: RecipeLabels.byUser(
          meals: {MealSuitability.lunch},
          weight: DishWeight.hearty,
          dishKind: DishKind.cooked,
        ),
      ),
      sampleRecipe('b', 'Grčka salata').copyWith(
        prepMinutes: 10,
        labels: RecipeLabels.byUser(
          meals: {MealSuitability.dinner},
          weight: DishWeight.light,
          dishKind: DishKind.salad,
        ),
      ),
      sampleRecipe('c', 'Pasulj'),
    ];

    Future<void> openFilters(WidgetTester tester) async {
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is TavliIconButton && w.semanticLabel.startsWith('Filteri'),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> close(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Prikaži recepte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prikaži recepte'));
      await tester.pumpAndSettle();
    }

    testTavli('izbor obroka i vremena sužava listu', (tester) async {
      await pumpTavli(tester, recipes: labelled());

      await openFilters(tester);
      expect(find.text('OBROK'), findsOneWidget);
      await tester.tap(find.text('Večera'));
      await tester.pumpAndSettle();
      await close(tester);

      expect(find.text('Grčka salata'), findsOneWidget);
      expect(find.text('Sarma'), findsNothing);
      expect(find.text('Pasulj'), findsNothing);
      expect(find.bySemanticsLabel('Filteri (1)'), findsOneWidget);
    });

    testTavli('bez pogotka: poruka i „Očisti filtere“ vraća sve', (
      tester,
    ) async {
      await pumpTavli(tester, recipes: labelled());

      await openFilters(tester);
      await tester.tap(find.text('Jak'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Do 15 min'));
      await tester.tap(find.text('Do 15 min'));
      await tester.pumpAndSettle();
      await close(tester);

      expect(find.text('Nema recepata za izabrane filtere.'), findsOneWidget);
      await tester.tap(find.text('Očisti filtere'));
      await tester.pumpAndSettle();
      expect(find.text('Sarma'), findsOneWidget);
      expect(find.text('Grčka salata'), findsOneWidget);
      expect(find.text('Pasulj'), findsOneWidget);
      expect(find.bySemanticsLabel('Filteri'), findsOneWidget);
    });

    testTavli('naziv i filter zajedno; „Sve“ isključuje filter', (
      tester,
    ) async {
      await pumpTavli(tester, recipes: labelled());

      await tester.enterText(find.byType(TavliSearchField), 'r');
      await tester.pumpAndSettle();
      await openFilters(tester);
      await tester.tap(find.text('Ručak'));
      await tester.pumpAndSettle();
      await close(tester);
      expect(find.text('Sarma'), findsOneWidget);
      expect(find.text('Grčka salata'), findsNothing);

      await openFilters(tester);
      await tester.tap(find.text('Sve').first);
      await tester.pumpAndSettle();
      await close(tester);
      expect(find.text('Sarma'), findsOneWidget);
      expect(find.text('Grčka salata'), findsOneWidget);
      expect(find.text('Pasulj'), findsNothing);
    });

    for (final size in [
      const Size(320, 640),
      const Size(400, 800),
      const Size(1200, 800),
    ]) {
      testTavli('${size.width} px, tekst 2×, tamna tema, bez animacija: '
          'filteri bez preliva', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await pumpTavli(
          tester,
          size: size,
          recipes: labelled(),
          settings: {'theme_mode': 'dark'},
        );
        await openFilters(tester);
        await tester.tap(find.text('Ručak'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Filteri (1)'), findsOneWidget);
        await tester.ensureVisible(find.text('Prikaži recepte'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
