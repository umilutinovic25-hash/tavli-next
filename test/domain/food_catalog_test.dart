import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/food.dart';
import 'package:tavli/domain/recipe.dart';

const _shared = [
  Food(
    id: 'f_jaje',
    name: 'jaje',
    category: 'mlečni proizvodi i jaja',
    baseUnit: BaseUnit.kom,
  ),
  Food(
    id: 'f_beli_luk',
    name: 'beli luk',
    category: 'voće i povrće',
    baseUnit: BaseUnit.g,
  ),
];

const _own = Food(
  id: 'own-1',
  householdId: 'h1',
  name: 'domaće jaje',
  category: 'mlečni proizvodi i jaja',
  baseUnit: BaseUnit.kom,
);

FoodCatalog _catalog() => FoodCatalog(
  foods: [..._shared, _own],
  aliases: const [
    FoodAlias(foodId: 'f_jaje', alias: 'jaje'),
    FoodAlias(foodId: 'f_jaje', alias: 'jaja'),
    FoodAlias(foodId: 'f_jaje', alias: 'jajce'),
    FoodAlias(foodId: 'f_beli_luk', alias: 'beli luk'),
    FoodAlias(foodId: 'f_beli_luk', alias: 'češnjak'),
    FoodAlias(foodId: 'own-1', householdId: 'h1', alias: 'domaće jaje'),
    // Senka: sopstveni alias istog teksta kao zajednički ne pobeđuje.
    FoodAlias(foodId: 'own-1', householdId: 'h1', alias: 'jajce'),
  ],
  conversions: const [
    FoodConversion(foodId: 'f_beli_luk', unit: 'čen', factorMicros: 5000000),
  ],
  allergens: const [(foodId: 'f_jaje', code: 'eggs')],
);

void main() {
  group('match', () {
    test('tačan alias posle normalizacije', () {
      expect(_catalog().match(' Jajce '), 'f_jaje');
      expect(_catalog().match('ČEŠNJAK'), 'f_beli_luk');
      expect(_catalog().match('domaće   jaje'), 'own-1');
    });

    test('nema približnog poklapanja', () {
      expect(_catalog().match('jaj'), isNull);
      expect(_catalog().match('jajca'), isNull);
      expect(_catalog().match(''), isNull);
    });

    test('zajednički alias ima prednost nad sopstvenim', () {
      expect(_catalog().match('jajce'), 'f_jaje');
    });
  });

  test('byId, konverzija i alergeni', () {
    final c = _catalog();
    expect(c.byId('f_jaje')?.name, 'jaje');
    expect(c.byId('nema'), isNull);
    expect(c.byId('f_jaje')!.isShared, isTrue);
    expect(c.byId('own-1')!.isShared, isFalse);
    expect(c.conversion('f_beli_luk', ' Čen ')?.factorMicros, 5000000);
    expect(c.conversion('f_beli_luk', 'kašika'), isNull);
    expect(c.conversion('f_jaje', 'čen'), isNull);
    expect(c.allergens('f_jaje'), {'eggs'});
    expect(c.allergens('f_beli_luk'), isEmpty);
  });

  group('FoodDraft.validate', () {
    test('normalizuje naziv', () {
      final d = const FoodDraft(
        name: '  Zmajevo   Voće ',
        category: 'voće i povrće',
        baseUnit: 'g',
      ).validate();
      expect(d.name, 'zmajevo voće');
      expect(d.baseUnit, BaseUnit.g);
      expect(d.category, 'voće i povrće');
    });

    for (final (label, draft) in [
      (
        'prazan naziv',
        const FoodDraft(name: '  ', category: 'ostalo', baseUnit: 'g'),
      ),
      (
        'predugačak naziv',
        FoodDraft(name: 'a' * 61, category: 'ostalo', baseUnit: 'g'),
      ),
      (
        'nepoznata kategorija',
        const FoodDraft(name: 'mango', category: 'egzotika', baseUnit: 'g'),
      ),
      (
        'jedinica van kom/g/ml',
        const FoodDraft(name: 'mango', category: 'ostalo', baseUnit: 'kg'),
      ),
      (
        'bez jedinice',
        const FoodDraft(name: 'mango', category: 'ostalo', baseUnit: null),
      ),
    ]) {
      test('odbija: $label', () {
        expect(draft.validate, throwsFormatException);
      });
    }
  });

  group('suggestFood', () {
    test('mango 200 g, voće i povrće → nacrt u g', () {
      final d = suggestFood(
        const Ingredient(
          name: ' Mango ',
          quantity: 200,
          unit: 'g',
          category: 'voće i povrće',
        ),
      )!;
      expect(d.name, 'mango');
      expect(d.category, 'voće i povrće');
      expect(d.baseUnit, 'g');
    });

    test('kg → g, l → ml, komada → kom', () {
      expect(
        suggestFood(const Ingredient(name: 'a', unit: 'kg'))!.baseUnit,
        'g',
      );
      expect(
        suggestFood(const Ingredient(name: 'a', unit: 'l'))!.baseUnit,
        'ml',
      );
      expect(
        suggestFood(const Ingredient(name: 'a', unit: 'komada'))!.baseUnit,
        'kom',
      );
    });

    test('kašika → bez osnovne jedinice (osoba bira)', () {
      final d = suggestFood(
        const Ingredient(name: 'čia semenke', quantity: 1, unit: 'kašika'),
      )!;
      expect(d.baseUnit, isNull);
      expect(d.validate, throwsFormatException);
    });

    test('nepoznata kategorija → ostalo', () {
      expect(
        suggestFood(const Ingredient(name: 'x', category: 'egzotika'))!
            .category,
        'ostalo',
      );
    });

    test('prazan naziv → nema predloga', () {
      expect(suggestFood(const Ingredient(name: '   ', unit: 'g')), isNull);
    });

    test('sastojak sa namirnicom → nema predloga', () {
      expect(
        suggestFood(const Ingredient(name: 'jaja', foodId: 'f_jaje')),
        isNull,
      );
    });
  });

  group('recipeAllergens', () {
    final catalog = FoodCatalog(
      foods: [
        ..._shared,
        const Food(
          id: 'f_psenicno_brasno',
          name: 'pšenično brašno',
          category: 'žitarice i testenine',
          baseUnit: BaseUnit.g,
        ),
      ],
      allergens: const [
        (foodId: 'f_jaje', code: 'eggs'),
        (foodId: 'f_psenicno_brasno', code: 'gluten'),
      ],
    );
    Recipe recipe(List<Ingredient> items) => Recipe(
      id: 'r',
      title: 'T',
      servings: 2,
      ingredients: items,
      source: RecipeSource.manual,
      createdAt: DateTime.utc(2026),
    );

    test('jaje + pšenično brašno → jaja, gluten; potpuno', () {
      final r = recipeAllergens(
        recipe(const [
          Ingredient(name: 'jaja', foodId: 'f_jaje'),
          Ingredient(name: 'brašno', foodId: 'f_psenicno_brasno'),
        ]),
        catalog,
      );
      expect(r.codes, {'eggs', 'gluten'});
      expect(r.complete, isTrue);
    });

    test('jedan nepotvrđen sastojak → nije potpuno', () {
      final r = recipeAllergens(
        recipe(const [
          Ingredient(name: 'jaja', foodId: 'f_jaje'),
          Ingredient(name: 'tajni začin'),
        ]),
        catalog,
      );
      expect(r.codes, {'eggs'});
      expect(r.complete, isFalse);
    });

    test('namirnica koje nema u katalogu → nije potpuno', () {
      final r = recipeAllergens(
        recipe(const [Ingredient(name: 'x', foodId: 'f_obrisano')]),
        catalog,
      );
      expect(r.complete, isFalse);
    });

    test('sve potvrđeno bez oznaka → prazno, potpuno', () {
      final r = recipeAllergens(
        recipe(const [Ingredient(name: 'beli luk', foodId: 'f_beli_luk')]),
        catalog,
      );
      expect(r.codes, isEmpty);
      expect(r.complete, isTrue);
    });
  });

  test('euAllergens je tačno 14 EU kodova sa srpskim nazivima', () {
    expect(euAllergens.keys.toList(), [
      'gluten',
      'crustaceans',
      'eggs',
      'fish',
      'peanuts',
      'soy',
      'milk',
      'nuts',
      'celery',
      'mustard',
      'sesame',
      'sulphites',
      'lupin',
      'molluscs',
    ]);
    expect(euAllergens['eggs'], 'jaja');
    expect(euAllergens['nuts'], 'orašasti plodovi');
  });
}
