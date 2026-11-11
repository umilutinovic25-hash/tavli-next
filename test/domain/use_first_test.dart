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
  String? foodId,
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
  foodId: foodId,
);

void main() {
  test(
    'brz izbor bez Ostave rangira različite namirnice, bez izmišljene zalihe',
    () {
      final recipes = [
        recipe('Jedan', const [
          Ingredient(name: 'kupus', quantity: 600, unit: 'g'),
        ]),
        recipe('Dva', const [
          Ingredient(name: 'kupus', quantity: 600, unit: 'g'),
          Ingredient(name: 'pirinač', quantity: 100, unit: 'g'),
        ]),
        recipe('Tri', const [
          Ingredient(name: 'kupus', quantity: 600, unit: 'g'),
          Ingredient(name: 'pirinač', quantity: 100, unit: 'g'),
          Ingredient(name: 'so'),
        ]),
        recipe('Nema', const [
          Ingredient(name: 'mleko', quantity: 1, unit: 'l'),
        ]),
      ];
      final result = suggestRecipes(
        recipes,
        [],
        now: now,
        selectedIngredients: ['kupus', 'pirinač', 'so'],
      );
      expect(result.map((s) => s.recipe.id), ['Tri', 'Dva', 'Jedan']);
      expect(result.map((s) => s.selectedIngredientCount), [3, 2, 1]);
      expect(result.every((s) => s.selectionSize == 3 && !s.ready), isTrue);
      expect(result.last.ingredients.single.matchedMicros, 0);
      expect(result.last.ingredients.single.missingMicros, 600000000);
      expect(result.last.ingredients.single.selected, isTrue);
      expect(result.every((s) => !s.missingOneOrTwo), isTrue);
      expect(result.first.ingredients.last.missingMicros, isNull);
    },
  );

  test(
    'brz izbor koristi potvrđeni sinonim, ali ne podstring ili duple redove',
    () {
      final result = suggestRecipes(
        [
          recipe('Luk', const [
            Ingredient(name: 'beli luk', quantity: 1, unit: 'kom'),
            Ingredient(name: 'beli luk', quantity: 10, unit: 'g'),
          ]),
          recipe('Ne', const [
            Ingredient(name: 'mladi beli luk', quantity: 1, unit: 'kom'),
          ]),
          recipe('Nula', const [
            Ingredient(name: 'beli luk', quantity: 0, unit: 'g'),
          ]),
        ],
        [],
        now: now,
        selectedIngredients: ['  Češnjak  '],
      );
      expect(result.single.recipe.id, 'Luk');
      expect(result.single.selectedIngredientCount, 1);
      expect(result.single.ingredients.every((i) => i.selected), isTrue);
    },
  );

  test('izbor ne potvrđuje količinu: 600 g − 400 g = 200 g; porcije i rezerve ostaju', () {
    final r = recipe('R', const [
      Ingredient(name: 'kupus', quantity: 600, unit: 'g'),
    ]);
    final items = [stock('p', 'kupus', 500, 'g', reserved: 100000000)];
    final result = suggestRecipes(
      [r],
      items,
      now: now,
      selectedIngredients: ['kupus'],
    ).single;
    expect(result.ingredients.single.missingMicros, 200000000);
    expect(result.ingredients.single.matchedMicros, 400000000);
    expect(result.ready, isFalse);
    expect(
      suggestRecipes(
        [r],
        items,
        now: now,
        servings: 1,
        selectedIngredients: ['kupus'],
      ).single.ready,
      isTrue,
    );
    final expired = stock(
      'p',
      'kupus',
      1000,
      'g',
      expires: now.subtract(const Duration(days: 1)),
    );
    expect(
      suggestRecipes(
        [r],
        [expired],
        now: now,
        selectedIngredients: ['kupus'],
      ).single.ingredients.single.matchedMicros,
      0,
    );
    expect(items.single.quantity, 500);
  });

  test(
    'broj izabranih ima prednost, a isti broj čuva rangiranje po rokovima',
    () {
      final recipes = [
        recipe('Jedan', const [
          Ingredient(name: 'kupus', quantity: 100, unit: 'g'),
        ]),
        recipe('Dva', const [
          Ingredient(name: 'pirinač', quantity: 100, unit: 'g'),
          Ingredient(name: 'so', quantity: 1, unit: 'g'),
        ]),
        recipe('Jedan kasnije', const [
          Ingredient(name: 'pirinač', quantity: 100, unit: 'g'),
        ]),
      ];
      final items = [
        stock(
          'k',
          'kupus',
          200,
          'g',
          expires: now.add(const Duration(days: 1)),
        ),
        stock(
          'p',
          'pirinač',
          200,
          'g',
          expires: now.add(const Duration(days: 5)),
        ),
      ];
      expect(
        suggestRecipes(
          recipes,
          items,
          now: now,
          selectedIngredients: ['kupus', 'pirinač', 'so'],
        ).map((s) => s.recipe.id),
        ['Dva', 'Jedan', 'Jedan kasnije'],
      );
    },
  );

  test('prazan izbor čuva stari tok; nevalidni izbori se odbijaju', () {
    final r = recipe('R', const [
      Ingredient(name: 'so', quantity: 1, unit: 'g'),
    ]);
    expect(suggestRecipes([r], [], now: now), isEmpty);
    expect(suggestRecipes([r], [], now: now, selectedIngredients: []), isEmpty);
    for (final selection in [
      [''],
      ['  '],
      ['a', 'b', 'c', 'd'],
      ['beli luk', 'češnjak'],
      ['So', ' so '],
      ['x' * 81],
    ]) {
      expect(
        () => suggestRecipes([r], [], now: now, selectedIngredients: selection),
        throwsArgumentError,
      );
    }
  });

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

  group('036: namirnica u Potroši prvo', () {
    test('jajce (f_jaje) pokriva jaja (f_jaje)', () {
      final r = recipe('Omlet', const [
        Ingredient(name: 'jaja', quantity: 2, unit: 'kom', foodId: 'f_jaje'),
      ]);
      final result = suggestRecipes(
        [r],
        [stock('o', 'jajce', 2, 'kom', foodId: 'f_jaje')],
        now: now,
      ).single;
      expect(result.ready, isTrue);
    });

    test('bez namirnice na jednoj strani: tekst kao danas', () {
      final r = recipe('Omlet', const [
        Ingredient(name: 'jaja', quantity: 2, unit: 'kom', foodId: 'f_jaje'),
      ]);
      expect(
        suggestRecipes(
          [r],
          [stock('o', 'jaja', 2, 'kom')],
          now: now,
        ).single.ready,
        isTrue,
      );
      expect(
        suggestRecipes([r], [stock('o', 'jajce', 2, 'kom')], now: now),
        isEmpty,
      );
    });

    test('različite namirnice istog naziva se ne mešaju', () {
      final r = recipe('Omlet', const [
        Ingredient(name: 'jaja', quantity: 2, unit: 'kom', foodId: 'f_jaje'),
      ]);
      expect(
        suggestRecipes(
          [r],
          [stock('o', 'jaja', 2, 'kom', foodId: 'own-prepelicja')],
          now: now,
        ),
        isEmpty,
      );
    });
  });
}
