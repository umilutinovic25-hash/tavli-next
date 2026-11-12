import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_demand.dart';

DemandSource source(
  String id,
  List<Ingredient> ingredients, {
  int baseServings = 2,
  int servings = 2,
}) => DemandSource(
  id: id,
  baseServings: baseServings,
  servings: servings,
  ingredients: ingredients,
);

void main() {
  group('fiksna preciznost', () {
    test('šest decimala, bez grešaka zaokruživanja', () {
      expect(toMicros(0.1) + toMicros(0.2), toMicros(0.3));
      expect(toMicros(1.0000004), 1000000);
      expect(fromMicros(1500000), 1.5);
    });

    test('odbija negativne i nekonačne vrednosti', () {
      expect(() => toMicros(-1), throwsArgumentError);
      expect(() => toMicros(double.nan), throwsArgumentError);
      expect(() => toMicros(double.infinity), throwsArgumentError);
    });
  });

  group('jedinice', () {
    test('g/kg, ml/l i kom su uporedive grupe', () {
      expect(normalizeUnit('kg'), (group: 'mass', base: 'g', factor: 1000));
      expect(normalizeUnit(' G '), (group: 'mass', base: 'g', factor: 1));
      expect(normalizeUnit('l'), (group: 'volume', base: 'ml', factor: 1000));
      expect(normalizeUnit('ml'), (group: 'volume', base: 'ml', factor: 1));
      expect(normalizeUnit('kom'), (
        group: 'count:kom',
        base: 'kom',
        factor: 1,
      ));
    });

    test('ostale jedinice su uporedive samo kad su iste', () {
      expect(normalizeUnit('Kašika'), (
        group: 'unit:kašika',
        base: 'kašika',
        factor: 1,
      ));
      expect(normalizeUnit('kašika'), normalizeUnit('KAŠIKA'));
      expect(normalizeUnit('kašika') == normalizeUnit('kasika'), isFalse);
      expect(normalizeUnit(null), (group: 'unit:', base: '', factor: 1));
    });
  });

  group('skaliranje porcija', () {
    test('količina prati porcije unosa u odnosu na osnovne', () {
      expect(scaleQuantity(300, baseServings: 2, servings: 4), 600);
      expect(
        scaleQuantity(1, baseServings: 3, servings: 1),
        closeTo(1 / 3, 1e-9),
      );
      expect(scaleQuantity(null, baseServings: 2, servings: 4), isNull);
    });

    test('porcije van 1–20 nisu dozvoljene', () {
      expect(
        () => scaleQuantity(1, baseServings: 0, servings: 2),
        throwsArgumentError,
      );
      expect(
        () => scaleQuantity(1, baseServings: 2, servings: 21),
        throwsArgumentError,
      );
    });
  });

  group('potražnja jednog izvora', () {
    test('skalira i spaja uporedive redove istog sastojka', () {
      final lines = demandFor(
        source('e1', servings: 4, [
          const Ingredient(name: 'Brašno', quantity: 0.5, unit: 'kg'),
          const Ingredient(name: ' brašno ', quantity: 100, unit: 'g'),
          const Ingredient(name: 'Mleko', quantity: 1, unit: 'l'),
        ]),
      );
      expect(lines, hasLength(2));
      final flour = lines.firstWhere((l) => l.key.ingredient == 'brašno');
      expect(flour.micros, toMicros(1200));
      expect(flour.baseUnit, 'g');
      expect(flour.key.sourceId, 'e1');
      final milk = lines.firstWhere((l) => l.key.ingredient == 'mleko');
      expect(milk.micros, toMicros(2000));
      expect(milk.baseUnit, 'ml');
    });

    test('neuporedive jedinice ostaju odvojene', () {
      final lines = demandFor(
        source('e1', [
          const Ingredient(name: 'jaja', quantity: 2, unit: 'kom'),
          const Ingredient(name: 'jaja', quantity: 100, unit: 'g'),
        ]),
      );
      expect(lines.map((l) => l.key.unitGroup), ['count:kom', 'mass']);
    });

    test('nepoznata količina ostaje za proveru i ne izmišlja se', () {
      final lines = demandFor(
        source('e1', [
          const Ingredient(name: 'so', note: 'po ukusu'),
          const Ingredient(name: 'biber', quantity: double.nan, unit: 'g'),
          const Ingredient(name: 'so', quantity: 5, unit: 'g'),
        ]),
      );
      final salt = lines.where((l) => l.key.ingredient == 'so').toList();
      expect(salt, hasLength(2));
      expect(salt.firstWhere((l) => l.isUnknown).key.unitGroup, unknownGroup);
      expect(salt.firstWhere((l) => !l.isUnknown).micros, toMicros(5));
      final pepper = lines.singleWhere((l) => l.key.ingredient == 'biber');
      expect(pepper.isUnknown, isTrue);
      expect(pepper.needsReview, isTrue);
    });

    test('naziv se ne spaja po sinonimima ni bez kvačica', () {
      final lines = demandFor(
        source('e1', [
          const Ingredient(name: 'šećer', quantity: 10, unit: 'g'),
          const Ingredient(name: 'secer', quantity: 10, unit: 'g'),
        ]),
      );
      expect(lines, hasLength(2));
    });
  });

  group('identitet potražnje po unosu', () {
    test('dve pojave istog recepta imaju odvojene potrebe', () {
      const ingredients = [
        Ingredient(name: 'pirinač', quantity: 200, unit: 'g'),
      ];
      final monday = demandFor(source('pon', ingredients));
      final friday = demandFor(source('pet', ingredients, servings: 4));
      expect(monday.single.key == friday.single.key, isFalse);
      expect(monday.single.micros, toMicros(200));
      expect(friday.single.micros, toMicros(400));
    });

    test('ponovno računanje istog izvora daje isti ključ', () {
      const ingredients = [
        Ingredient(name: 'pirinač', quantity: 200, unit: 'g'),
      ];
      expect(
        demandFor(source('pon', ingredients)).single.key,
        demandFor(source('pon', ingredients, servings: 3)).single.key,
      );
    });
  });

  group('zbir za listu', () {
    test('sabira uporedive potrebe i pamti izvore', () {
      final needs = summarize([
        ...demandFor(
          source('pon', [
            const Ingredient(name: 'mleko', quantity: 0.5, unit: 'l'),
          ]),
        ),
        ...demandFor(
          source('pet', [
            const Ingredient(name: 'Mleko', quantity: 250, unit: 'ml'),
          ]),
        ),
        ...demandFor(source('sre', [const Ingredient(name: 'mleko')])),
      ]);
      expect(needs, hasLength(2));
      final known = needs.firstWhere((n) => !n.isUnknown);
      expect(known.micros, toMicros(750));
      expect(known.sourceIds, ['pon', 'pet']);
      final unknown = needs.firstWhere((n) => n.isUnknown);
      expect(unknown.sourceIds, ['sre']);
    });
  });

  group('prikaz', () {
    test('veće količine u kg i l', () {
      expect(displayAmount(toMicros(1500), 'g'), (quantity: 1.5, unit: 'kg'));
      expect(displayAmount(toMicros(750), 'ml'), (quantity: 750.0, unit: 'ml'));
      expect(displayAmount(toMicros(2000), 'ml'), (quantity: 2.0, unit: 'l'));
      expect(displayAmount(toMicros(3), 'kom'), (quantity: 3.0, unit: 'kom'));
    });
  });

  group('rečnik v2 (036)', () {
    DemandSource v2(
      String id,
      List<Ingredient> ingredients, {
      int baseServings = 2,
      int servings = 2,
      Map<String, FrozenConversion> conversions = const {},
    }) => DemandSource(
      id: id,
      baseServings: baseServings,
      servings: servings,
      ingredients: ingredients,
      dictionaryVersion: 2,
      conversions: conversions,
    );

    test('ključ: food id kad postoji, inače v1 tekst', () {
      expect(
        dictionaryIngredientKey('Jaja', 2, foodId: 'f_jaje'),
        'food:f_jaje',
      );
      expect(dictionaryIngredientKey('Češnjak', 2), 'v1:beli luk');
      expect(dictionaryIngredientKey('Jaja', 1, foodId: 'f_jaje'), 'v1:jaja');
      expect(dictionaryIngredientKey('Jaja', 0, foodId: 'f_jaje'), 'jaja');
      expect(() => dictionaryIngredientKey('x', 3), throwsArgumentError);
    });

    test('v2 jedinice kao v1', () {
      expect(normalizeUnit('grama', dictionaryVersion: 2).group, 'mass');
      expect(normalizeUnit('grama').group, 'unit:grama');
    });

    test('SC-001: jaja i jaje istog food id-ja su jedna potreba', () {
      final a = demandFor(
        v2('A', const [
          Ingredient(name: 'jaja', quantity: 3, unit: 'kom', foodId: 'f_jaje'),
        ], baseServings: 4),
      );
      final b = demandFor(
        v2('B', const [
          Ingredient(name: 'jaje', quantity: 2, unit: 'kom', foodId: 'f_jaje'),
        ]),
      );
      final needs = summarize([...a, ...b]);
      expect(needs, hasLength(1));
      expect(needs.single.ingredient, 'food:f_jaje');
      expect(needs.single.unitGroup, 'count:kom');
      expect(needs.single.micros, 3500000);
    });

    test('zamrznuta konverzija: 2 čena + 10 g = 20 g', () {
      final lines = demandFor(
        v2(
          'S',
          const [
            Ingredient(
              name: 'beli luk',
              quantity: 2,
              unit: 'čena',
              foodId: 'f_beli_luk',
            ),
            Ingredient(
              name: 'češnjak',
              quantity: 10,
              unit: 'g',
              foodId: 'f_beli_luk',
            ),
          ],
          conversions: {
            conversionKey('f_beli_luk', 'Čena'): (
              factorMicros: 5000000,
              baseUnit: 'g',
            ),
          },
        ),
      );
      expect(lines, hasLength(1));
      expect(lines.single.key.unitGroup, 'mass');
      expect(lines.single.baseUnit, 'g');
      expect(lines.single.micros, 20000000);
    });

    test('konverzija važi samo uz food id', () {
      final lines = demandFor(
        v2(
          'S',
          const [Ingredient(name: 'beli luk', quantity: 2, unit: 'čena')],
          conversions: {
            conversionKey('f_beli_luk', 'čena'): (
              factorMicros: 5000000,
              baseUnit: 'g',
            ),
          },
        ),
      );
      expect(lines.single.key.unitGroup, 'unit:čena');
    });

    test('imam/nemam: kašika bez konverzije ostaje svoja grupa', () {
      final lines = demandFor(
        v2('S', const [
          Ingredient(name: 'so', quantity: 1, unit: 'kašika', foodId: 'f_so'),
          Ingredient(name: 'so', quantity: 5, unit: 'g', foodId: 'f_so'),
        ]),
      );
      expect([for (final l in lines) l.key.unitGroup], ['unit:kašika', 'mass']);
    });

    test('konverzija sa razlomkom zaokružuje na pola naviše', () {
      final lines = demandFor(
        v2(
          'S',
          const [
            Ingredient(
              name: 'šećer',
              quantity: 1,
              unit: 'kašičica',
              foodId: 'f_secer',
            ),
          ],
          servings: 3,
          conversions: {
            conversionKey('f_secer', 'kašičica'): (
              factorMicros: 2500001,
              baseUnit: 'g',
            ),
          },
        ),
      );
      // 2 500 001 × 3/2 = 3 750 001,5 → 3 750 002
      expect(lines.single.micros, 3750002);
    });
  });
}
