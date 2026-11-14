import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/allergy.dart';
import 'package:tavli/domain/food.dart';
import 'package:tavli/domain/recipe.dart';

final _catalog = FoodCatalog(
  foods: const [
    Food(
      id: 'f_jaje',
      name: 'jaje',
      category: 'mlečno',
      baseUnit: BaseUnit.kom,
    ),
    Food(
      id: 'f_kikiriki',
      name: 'kikiriki',
      category: 'ostalo',
      baseUnit: BaseUnit.g,
    ),
    Food(
      id: 'f_jagoda',
      name: 'jagoda',
      category: 'voće',
      baseUnit: BaseUnit.g,
    ),
    Food(id: 'f_so', name: 'so', category: 'začini', baseUnit: BaseUnit.g),
  ],
  aliases: const [
    FoodAlias(foodId: 'f_jaje', alias: 'jaje'),
    FoodAlias(foodId: 'f_jaje', alias: 'jajce'),
    FoodAlias(foodId: 'f_kikiriki', alias: 'kikiriki'),
    FoodAlias(foodId: 'f_jagoda', alias: 'jagoda'),
    FoodAlias(foodId: 'f_jagoda', alias: 'jagode'),
    FoodAlias(foodId: 'f_so', alias: 'so'),
  ],
  allergens: const [
    (foodId: 'f_jaje', code: 'eggs'),
    (foodId: 'f_kikiriki', code: 'peanuts'),
  ],
);

HouseholdAllergies _hh({
  Set<String> codes = const {},
  List<String> custom = const [],
}) => HouseholdAllergies.union([
  PersonAllergies(
    householdId: 'h1',
    userId: 'u1',
    codes: codes,
    custom: custom,
  ),
]);

void main() {
  group('checkAllergens', () {
    test('EU alergen preko foodId', () {
      final check = checkAllergens(
        const [Ingredient(name: 'nešto', foodId: 'f_kikiriki')],
        _catalog,
        _hh(codes: {'peanuts'}),
      );
      expect(check.hits.single.ingredient, 'nešto');
      expect(check.hits.single.allergen, 'kikiriki');
      expect(check.unconfirmed, isFalse);
    });

    test('EU alergen preko tačnog aliasa (bez foodId)', () {
      final check = checkAllergens(
        const [Ingredient(name: 'Jajce'), Ingredient(name: 'so')],
        _catalog,
        _hh(codes: {'eggs'}),
      );
      expect(check.hits.map((h) => h.allergen), ['jaja']);
      expect(check.allergens, ['jaja']);
    });

    test('slobodan unos preko kataloga: „jagode“ pogađa „jagoda“', () {
      final check = checkAllergens(
        const [Ingredient(name: 'jagoda')],
        _catalog,
        _hh(custom: ['jagode']),
      );
      expect(check.hits.single.allergen, 'jagode');
    });

    test('slobodan unos po celim rečima', () {
      final hh = _hh(custom: ['crni luk']);
      expect(
        checkAllergens(
          const [Ingredient(name: 'Sitno seckan crni luk')],
          _catalog,
          hh,
        ).hits,
        hasLength(1),
      );
      expect(
        checkAllergens(
          const [Ingredient(name: 'crnilukasto')],
          _catalog,
          hh,
        ).hits,
        isEmpty,
      );
      expect(
        checkAllergens(const [Ingredient(name: 'beli luk')], _catalog, hh).hits,
        isEmpty,
      );
    });

    test('nepotvrđen sastojak uz alergije: prihvaćeno uz oznaku', () {
      final check = checkAllergens(
        const [Ingredient(name: 'pesto đenoveze'), Ingredient(name: 'so')],
        _catalog,
        _hh(codes: {'nuts'}),
      );
      expect(check.hits, isEmpty);
      expect(check.unconfirmed, isTrue);
    });

    test('bez alergija u domaćinstvu nema ni pogodaka ni oznake', () {
      final check = checkAllergens(
        const [Ingredient(name: 'kikiriki'), Ingredient(name: 'nepoznato')],
        _catalog,
        HouseholdAllergies.none,
      );
      expect(check.hits, isEmpty);
      expect(check.unconfirmed, isFalse);
    });

    test('foodId koji nije u katalogu je nepotvrđen', () {
      final check = checkAllergens(
        const [Ingredient(name: 'x', foodId: 'f_obrisan')],
        _catalog,
        _hh(codes: {'eggs'}),
      );
      expect(check.unconfirmed, isTrue);
    });
  });

  group('HouseholdAllergies', () {
    test('legacy nazivi postaju EU kodovi, ostalo ostaje slobodan unos', () {
      final hh = HouseholdAllergies.union(
        [],
        legacy: [
          ' Jaje ',
          'orasasti plodovi',
          'senf',
          'mekusci',
          'milk',
          'Jagode',
        ],
      );
      expect(hh.codes, {'eggs', 'nuts', 'mustard', 'molluscs', 'milk'});
      expect(hh.custom, ['jagode']);
      final check = checkAllergens(
        const [Ingredient(name: 'nešto', foodId: 'f_jaje')],
        _catalog,
        hh,
      );
      expect(check.allergens, ['jaja']);
    });
    test('unija svih članova, EU po redosledu Uredbe, pa ostalo', () {
      final hh = HouseholdAllergies.union([
        PersonAllergies(
          householdId: 'h1',
          userId: 'u1',
          codes: {'nuts'},
          custom: ['jagode'],
        ),
        PersonAllergies(
          householdId: 'h1',
          userId: 'u2',
          codes: {'gluten', 'nuts'},
          custom: ['Jagode', 'kivi'],
        ),
      ]);
      expect(hh.codes, {'gluten', 'nuts'});
      expect(hh.labels, ['gluten', 'orašasti plodovi', 'jagode', 'kivi']);
      expect(hh.promptTerms, ['gluten', 'tree nuts', 'jagode', 'kivi']);
      expect(hh.isEmpty, isFalse);
      expect(HouseholdAllergies.none.isEmpty, isTrue);
    });
  });

  test('unija nema ograničenje od 30 (ono važi po osobi)', () {
    final hh = HouseholdAllergies.union([
      for (final u in ['u1', 'u2'])
        PersonAllergies(
          householdId: 'h1',
          userId: u,
          custom: [for (var i = 0; i < 20; i++) '$u-$i'],
        ),
    ]);
    expect(hh.custom, hasLength(40));
  });

  group('PersonAllergies', () {
    test('nepoznat kod se odbija', () {
      expect(
        () => PersonAllergies(
          householdId: 'h1',
          userId: 'u1',
          codes: {'kikiriki'},
        ),
        throwsArgumentError,
      );
    });

    test('najviše 30 stavki i 40 znakova; normalizacija', () {
      expect(
        () => PersonAllergies(
          householdId: 'h1',
          userId: 'u1',
          custom: [for (var i = 0; i < 31; i++) 's$i'],
        ),
        throwsArgumentError,
      );
      expect(
        () => PersonAllergies(
          householdId: 'h1',
          userId: 'u1',
          custom: ['a' * 41],
        ),
        throwsArgumentError,
      );
      expect(
        PersonAllergies(
          householdId: 'h1',
          userId: 'u1',
          custom: [' Kivi ', 'kivi'],
        ).custom,
        ['kivi'],
      );
    });

    test('id je domaćinstvo:osoba', () {
      expect(PersonAllergies(householdId: 'h1', userId: 'u1').id, 'h1:u1');
    });
  });

  test('AllergenViolation ima srpsku poruku', () {
    expect(
      const AllergenViolation(['kikiriki', 'jaja']).toString(),
      'Nije pronađen recept bez alergena članova domaćinstva '
      '(kikiriki, jaja). Promeni zahtev i pokušaj ponovo.',
    );
  });
}
