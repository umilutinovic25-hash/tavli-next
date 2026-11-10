import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/app/animations/photo_scan.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/features/recipes/recipe_view.dart';

import '../../helpers/test_app.dart';

Map<String, dynamic> photoRecipe(Object? quantity) => {
  ...recipeJson('Bakina pita'),
  'ingredients': [
    {
      'name': 'brašno',
      'quantity': quantity,
      'unit': 'g',
      'category': 'suvi proizvodi',
      'note': 'prosejano',
    },
  ],
};

Finder field(String label) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  ),
);

Future<void> editIngredient(WidgetTester tester, int index) async {
  final edit = find.byKey(ValueKey('review-ingredient-$index'));
  await tester.ensureVisible(edit);
  await tester.tap(edit);
  await tester.pumpAndSettle();
}

Future<void> saveIngredient(WidgetTester tester) async {
  final save = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(FilledButton, 'Sačuvaj'),
  );
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  testTavli(
    'neispravno se označava; ispravka ne piše dok se ceo recept ne sačuva',
    (tester) async {
      final app = await pumpTavli(
        tester,
        location: '/recipes/new/photo',
        ai: [aiAnswer(photoRecipe(-20))],
      );
      app.picker.next = fakePhoto;
      await tapButton(tester, 'Izaberi iz galerije');
      expect(find.text('Originalna fotografija'), findsOneWidget);
      expect(find.text('Prepoznati recept'), findsOneWidget);
      expect(find.byType(PhotoScan), findsOneWidget);
      expect(
        find.text('Neispravna količina — proveri original.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(button('Sačuvaj')).onPressed, isNull);
      expect(
        tester.widget<OutlinedButton>(button('Proveri sastojke')).onPressed,
        isNull,
      );
      await editIngredient(tester, 0);
      await tester.enterText(field('Količina'), '250,5');
      await saveIngredient(tester);
      expect(
        find.text('Neispravna količina — proveri original.'),
        findsNothing,
      );
      expect(find.text('• 250,5 g brašno (prosejano)'), findsOneWidget);
      expect(await app.titles(), isEmpty);
      expect(app.photos.saved, isEmpty);
      expect(app.adapter.requests, hasLength(1));
      await tapButton(tester, 'Sačuvaj');
      final row = await app.db.select(app.db.recipes).getSingle();
      final recipe = (await app.repo.get(row.id))!;
      expect(recipe.ingredients.single.quantity, 250.5);
      expect(recipe.ingredients.single.unit, 'g');
      expect(recipe.ingredients.single.category, 'suvi proizvodi');
      expect(recipe.ingredients.single.note, 'prosejano');
      expect(recipe.source, RecipeSource.photo);
      expect(app.photos.saved.values.single, fakePhoto);
    },
  );

  testTavli('ispravka naziva ne zaokružuje malu količinu iz foto-pregleda', (
    tester,
  ) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/new/photo',
      ai: [aiAnswer(photoRecipe(0.001))],
    );
    app.picker.next = fakePhoto;
    await tapButton(tester, 'Izaberi iz galerije');
    expect(find.text('• 0,001 g brašno (prosejano)'), findsOneWidget);
    await editIngredient(tester, 0);
    await tester.enterText(field('Naziv'), 'Šafran');
    await saveIngredient(tester);
    await tapButton(tester, 'Sačuvaj');
    final row = await app.db.select(app.db.recipes).getSingle();
    expect((await app.repo.get(row.id))!.ingredients.single.quantity, 0.001);
  });

  testTavli(
    'nečitljiva količina ostaje nepoznata; editor odbija neispravno i prihvata prazno',
    (tester) async {
      final app = await pumpTavli(
        tester,
        location: '/recipes/new/photo',
        ai: [aiAnswer(photoRecipe('nečitko'))],
      );
      app.picker.next = fakePhoto;
      await tapButton(tester, 'Izaberi iz galerije');
      expect(
        find.text('Količina nije prepoznata — proveri original.'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(button('Sačuvaj')).onPressed,
        isNotNull,
      );
      await editIngredient(tester, 0);
      for (final value in ['NaN', 'Infinity', '0', '-3', 'nečitko']) {
        await tester.enterText(field('Količina'), value);
        await saveIngredient(tester);
        expect(
          find.text(
            'Unesi pozitivan broj ili ostavi prazno ako količina nije poznata.',
          ),
          findsOneWidget,
        );
      }
      await tester.enterText(field('Količina'), '');
      await saveIngredient(tester);
      expect(
        find.text('Količina nije prepoznata — proveri original.'),
        findsOneWidget,
      );
      await tapButton(tester, 'Sačuvaj');
      final row = await app.db.select(app.db.recipes).getSingle();
      expect((await app.repo.get(row.id))!.ingredients.single.quantity, isNull);
    },
  );

  testTavli(
    'nekonačna količina iz AI odgovora je označena i ne može da se sačuva',
    (tester) async {
      final app = await pumpTavli(
        tester,
        location: '/recipes/new/photo',
        ai: [aiAnswer(photoRecipe('NaN'))],
      );
      app.picker.next = fakePhoto;
      await tapButton(tester, 'Izaberi iz galerije');
      expect(
        find.text('Neispravna količina — proveri original.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(button('Sačuvaj')).onPressed, isNull);
      expect(await app.titles(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testTavli(
    'uvećanje i ceo prikaz čuvaju fotografiju, pregled i broj AI poziva',
    (tester) async {
      final app = await pumpTavli(
        tester,
        location: '/recipes/new/photo',
        size: const Size(1200, 1000),
        ai: [aiAnswer(photoRecipe(250))],
      );
      app.picker.next = fakePhoto;
      await tapButton(tester, 'Izaberi iz galerije');
      expect(
        find.byKey(const ValueKey('photo-comparison-wide')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Originalna fotografija')).dx,
        lessThan(tester.getTopLeft(find.text('Prepoznati recept')).dx),
      );
      final image = tester.widget<Image>(
        find.byWidgetPredicate(
          (w) =>
              w is Image && w.semanticLabel == 'Originalna fotografija recepta',
        ),
      );
      expect(image.fit, BoxFit.contain);
      await tapButton(tester, 'Uvećaj fotografiju');
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      await tapButton(tester, 'Uvećaj');
      expect(
        viewer.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1),
      );
      await tapButton(tester, 'Cela fotografija');
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.text('Bakina pita'), findsOneWidget);
      expect(app.adapter.requests, hasLength(1));
      expect(await app.titles(), isEmpty);
      expect(app.photos.saved, isEmpty);
    },
  );

  testTavli('otkazivanje editora i odbacivanje pregleda ne čuvaju ispravke', (
    tester,
  ) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/new/photo',
      ai: [aiAnswer(photoRecipe(250))],
    );
    app.picker.next = fakePhoto;
    await tapButton(tester, 'Izaberi iz galerije');
    await editIngredient(tester, 0);
    await tester.enterText(field('Količina'), '999');
    await tapButton(tester, 'Otkaži');
    expect(find.text('• 250 g brašno (prosejano)'), findsOneWidget);
    await editIngredient(tester, 0);
    await tester.enterText(field('Količina'), '1/2');
    await saveIngredient(tester);
    expect(find.text('• 0,5 g brašno (prosejano)'), findsOneWidget);
    await tapButton(tester, 'Odbaci');
    expect(find.text('Izaberi iz galerije'), findsOneWidget);
    expect(await app.titles(), isEmpty);
    expect(app.photos.saved, isEmpty);
  });

  testTavli('ponovno čitanje odbacuje lokalnu ispravku i koristi istu sliku', (
    tester,
  ) async {
    final app = await pumpTavli(
      tester,
      location: '/recipes/new/photo',
      ai: [aiAnswer(photoRecipe(250)), aiAnswer(photoRecipe(300))],
    );
    app.picker.next = fakePhoto;
    await tapButton(tester, 'Izaberi iz galerije');
    await editIngredient(tester, 0);
    await tester.enterText(field('Količina'), '500');
    await saveIngredient(tester);
    await tapButton(tester, 'Pokušaj ponovo');
    expect(find.text('• 300 g brašno (prosejano)'), findsOneWidget);
    expect(find.text('• 500 g brašno (prosejano)'), findsNothing);
    expect(app.adapter.requests, hasLength(2));
    expect(await app.titles(), isEmpty);
    expect(app.photos.saved, isEmpty);
  });

  for (final width in [320.0, 1440.0]) {
    testTavli('poređenje i editor na $width px, tekst 2× i tamna tema', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await pumpTavli(
        tester,
        location: '/recipes/new/photo',
        size: Size(width, 1400),
        settings: {'theme': 'bosiljak', 'theme_mode': 'dark'},
        ai: [aiAnswer(photoRecipe(250))],
      );
      app.picker.next = fakePhoto;
      await tapButton(tester, 'Izaberi iz galerije');
      expect(
        find.byKey(
          ValueKey(
            width >= 1000
                ? 'photo-comparison-wide'
                : 'photo-comparison-stacked',
          ),
        ),
        findsOneWidget,
      );
      await editIngredient(tester, 0);
      await tester.enterText(field('Količina'), '0');
      await saveIngredient(tester);
      expect(tester.takeException(), isNull);
      await tester.enterText(field('Količina'), '1/2');
      await saveIngredient(tester);
      expect(find.text('• 0,5 g brašno (prosejano)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'isti objekat sastojka ponovljen u receptu zadržava zaseban indeks',
    (tester) async {
      const i = Ingredient(name: 'so', quantity: 1, unit: 'g');
      var edited = -1;
      final recipe = Recipe(
        id: 'r',
        title: 'R',
        servings: 2,
        ingredients: const [i, i],
        source: RecipeSource.photo,
        createdAt: DateTime.utc(2026),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecipeView(
              recipe,
              reviewQuantities: true,
              onEditIngredient: (index) => edited = index,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('review-ingredient-1')));
      expect(edited, 1);
    },
  );
}
