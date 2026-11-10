import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/use_first.dart';

final now = DateTime(2026, 11, 9, 12);
Recipe recipe(String id, List<Ingredient> ingredients, {int servings = 2}) =>
    Recipe(
      id: id,
      title: id,
      servings: servings,
      ingredients: ingredients,
      source: RecipeSource.manual,
      createdAt: now,
    );
PantryStock stock(
  String id,
  String name,
  double? quantity,
  String? unit, {
  DateTime? expires,
  bool confirmed = true,
  int reserved = 0,
  bool whole = false,
  String? purchase,
}) => PantryStock(
  id: id,
  name: name,
  quantity: quantity,
  unit: unit,
  confirmedAt: confirmed ? now : null,
  expiresAt: expires,
  reservedMicros: reserved,
  reservedWhole: whole,
  sourceShoppingItemId: purchase,
);

void main() {
  test(
    'filter računa jedan ili dva poznata manjka, a ne nepoznate količine',
    () {
      final items = [stock('a', 'pirinač', 400, 'g')];
      final recipes = [
        recipe('jedan', const [
          Ingredient(name: 'pirinač', quantity: 600, unit: 'g'),
        ]),
        recipe('dva', const [
          Ingredient(name: 'pirinač', quantity: 600, unit: 'g'),
          Ingredient(name: 'so', quantity: 10, unit: 'g'),
        ]),
        recipe('tri', const [
          Ingredient(name: 'pirinač', quantity: 600, unit: 'g'),
          Ingredient(name: 'so', quantity: 10, unit: 'g'),
          Ingredient(name: 'biber', quantity: 10, unit: 'g'),
        ]),
        recipe('nepoznato', const [
          Ingredient(name: 'pirinač', quantity: 600, unit: 'g'),
          Ingredient(name: 'so'),
        ]),
        recipe('dovoljno', const [
          Ingredient(name: 'pirinač', quantity: 400, unit: 'g'),
        ]),
      ];
      final result = {
        for (final s in suggestRecipes(recipes, items, now: now))
          s.recipe.id: s,
      };
      expect(result['jedan']!.ingredients.single.missingMicros, 200000000);
      expect(result['jedan']!.missingOneOrTwo, isTrue);
      expect(result['dva']!.missingOneOrTwo, isTrue);
      expect(result['tri']!.missingOneOrTwo, isFalse);
      expect(result['nepoznato']!.missingOneOrTwo, isFalse);
      expect(result['dovoljno']!.missingOneOrTwo, isFalse);
      expect(result['dovoljno']!.ready, isTrue);
    },
  );
  test('1 kg − 250 g = 750 g; porcije i rezerve', () {
    final r = recipe('Pirinač', const [
      Ingredient(name: 'pirinač', quantity: 1, unit: 'kg'),
    ]);
    final s = stock('p', 'pirinač', 0.5, 'kg', reserved: 250000000);
    final result = suggestRecipes([r], [s], now: now).single;
    expect(result.ingredients.single.missingMicros, 750000000);
    expect(result.ingredients.single.matchedMicros, 250000000);
    expect(result.ready, isFalse);
    expect(
      suggestRecipes(
        [r],
        [s],
        now: now,
        servings: 1,
      ).single.ingredients.single.missingMicros,
      250000000,
    );
  });

  test(
    'prioritet najbližeg korišćenog roka; isteklo i neiskorišćeno ne daju skor',
    () {
      final recipes = [
        recipe('Sveže', const [
          Ingredient(name: 'pirinač', quantity: 100, unit: 'g'),
        ]),
        recipe('Mleko', const [
          Ingredient(name: 'mleko', quantity: 1, unit: 'l'),
        ]),
        recipe('Jogurt', const [
          Ingredient(name: 'jogurt', quantity: 1, unit: 'l'),
        ]),
      ];
      final items = [
        stock('p', 'pirinač', 1, 'kg'),
        stock('m', 'mleko', 1, 'l', expires: DateTime(2026, 11, 10, 23)),
        stock('j', 'jogurt', 1, 'l', expires: DateTime(2026, 11, 9, 23)),
        stock('other', 'so', 1, 'kg', expires: DateTime(2026, 11, 9, 13)),
      ];
      final results = suggestRecipes(recipes, items, now: now);
      expect(results.map((r) => r.recipe.id), ['Jogurt', 'Mleko', 'Sveže']);
      expect(results.map((r) => r.dueScore), [8, 7, 0]);
    },
  );

  test(
    'ignoriše nepoznato, nepotvrđeno, isteklo, nulu i nekompatibilnu jedinicu',
    () {
      final r = recipe('R', const [
        Ingredient(name: 'mleko', quantity: 1, unit: 'l'),
      ]);
      for (final s in [
        stock('a', 'mleko', null, 'l'),
        stock('a', 'mleko', 1, 'l', confirmed: false),
        stock(
          'a',
          'mleko',
          1,
          'l',
          expires: now.subtract(const Duration(seconds: 1)),
        ),
        stock('a', 'mleko', 0, 'l'),
        stock('a', 'mleko', 1, 'kg'),
        stock('a', 'mleko', double.infinity, 'l'),
        stock('a', 'mleko', 1, 'l', whole: true),
      ]) {
        expect(suggestRecipes([r], [s], now: now), isEmpty);
      }
    },
  );

  test(
    'isti sastojak sabira potrebe; partije FEFO, bez dupliranja fizičke zalihe',
    () {
      final r = recipe('R', const [
        Ingredient(name: 'Mleko', quantity: 250, unit: 'ml'),
        Ingredient(name: ' mleko ', quantity: 0.5, unit: 'l'),
      ]);
      final early = stock(
        'a',
        'mleko',
        0.25,
        'l',
        expires: DateTime(2026, 11, 10, 23),
        purchase: 'buy',
      );
      final results = suggestRecipes(
        [r],
        [early, early, stock('b', 'mleko', 250, 'ml')],
        now: now,
      ).single;
      expect(results.ingredients, hasLength(1));
      expect(results.ingredients.single.missingMicros, 250000000);
      expect(results.dueScore, 7);
      expect(results.soonIngredients.single, 'Mleko');
    },
  );

  test(
    'poznat deo može biti predlog, nepoznat sastojak sprečava Mogu sada',
    () {
      final r = recipe('R', const [
        Ingredient(name: 'kupus', quantity: 500, unit: 'g'),
        Ingredient(name: 'so'),
      ]);
      final result = suggestRecipes(
        [r],
        [stock('p', 'kupus', 1, 'kg')],
        now: now,
      ).single;
      expect(result.coveredCount, 1);
      expect(result.ready, isFalse);
      expect(result.ingredients.last.missingMicros, isNull);
    },
  );

  test(
    'rok za sedam kalendarskih dana ulazi, osmi ne; potvrđeno sve je Mogu sada',
    () {
      final r = recipe('R', const [
        Ingredient(name: 'mleko', quantity: 1, unit: 'l'),
      ]);
      final a = suggestRecipes(
        [r],
        [stock('p', 'mleko', 1, 'l', expires: DateTime(2026, 11, 16, 23, 59))],
        now: now,
      ).single;
      expect(a.dueScore, 1);
      expect(a.ready, isTrue);
      final b = suggestRecipes(
        [r],
        [stock('p', 'mleko', 1, 'l', expires: DateTime(2026, 11, 17))],
        now: now,
      ).single;
      expect(b.dueScore, 0);
    },
  );

  test('recepti se procenjuju nezavisno, redosled stabilan bez mutiranja', () {
    final a = recipe('A', const [
      Ingredient(name: 'jaje', quantity: 1, unit: 'kom'),
    ]);
    final b = recipe('B', a.ingredients);
    final items = [stock('p', 'jaje', 1, 'kom')];
    expect(suggestRecipes([b, a], items, now: now).map((s) => s.recipe.id), [
      'A',
      'B',
    ]);
    expect(
      suggestRecipes([a, b], items, now: now).every((s) => s.ready),
      isTrue,
    );
    expect(items.single.quantity, 1);
    expect(
      () => suggestRecipes([a], items, now: now, servings: 0),
      throwsArgumentError,
    );
    expect(
      () => suggestRecipes([a], items, now: now, servings: 21),
      throwsArgumentError,
    );
  });

  test('ranija partija troši se pre kasnije; viškovi i nulti sastojci ne podižu skor', () {
    final r = recipe('R', const [
      Ingredient(name: 'jaje', quantity: 1, unit: 'kom'),
      Ingredient(name: 'so', quantity: 0, unit: 'g'),
    ]);
    final result = suggestRecipes(
      [r],
      [
        stock('fresh', 'jaje', 10, 'kom'),
        stock('soon', 'jaje', 1, 'kom', expires: DateTime(2026, 11, 10, 23)),
        stock('zero', 'so', 10, 'g', expires: DateTime(2026, 11, 9, 23)),
      ],
      now: now,
    ).single;
    expect(result.dueScore, 7);
    expect(result.ready, isTrue);
  });
}
