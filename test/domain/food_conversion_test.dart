import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/food_conversion.dart';
import 'package:tavli/domain/food_matcher.dart';

// Primeri iz specs/018-ingredient-catalog/unit-conversion-proposal.md (D1-010).
// Faktori su izmišljeni (sintetički); služe samo za proveru računa.

const grams = FoodBaseUnit.gram;
const ml = FoodBaseUnit.milliliter;
const piece = FoodBaseUnit.piece;

UnitConversion conv(
  double? q,
  String? unit,
  FoodBaseUnit target, {
  FoodConversionFactors factors = const FoodConversionFactors(),
  bool kitchen = false,
  String? packageId,
}) => convertQuantity(
  quantity: q,
  unit: unit,
  target: target,
  factors: factors,
  kitchenMeasures: kitchen,
  packageId: packageId,
);

void main() {
  group('tačne jedinice iste dimenzije', () {
    test('1 kg i 500 g iste namirnice daju 1500 g, tačno', () {
      final total = totalOf([conv(1, 'kg', grams), conv(500, 'g', grams)]);
      expect(total.micros, 1500 * 1000000);
      expect(total.approximate, isFalse);
      expect(total.review, isEmpty);
    });

    test('dkg, dl i l se prevode u osnovnu jedinicu bez faktora', () {
      expect(conv(3, 'dkg', grams), isA<Converted>());
      expect((conv(3, 'dkg', grams) as Converted).micros, 30 * 1000000);
      expect((conv(2, 'dl', ml) as Converted).micros, 200 * 1000000);
      expect((conv(1.5, 'l', ml) as Converted).micros, 1500 * 1000000);
    });
  });

  group('faktori za namirnicu', () {
    const egg = FoodConversionFactors(pieceWeightG: 50);

    test('2 jaja i 100 g jaja: osnova komad daje 4 komada, približno', () {
      final total = totalOf([
        conv(2, 'kom', piece, factors: egg),
        conv(100, 'g', piece, factors: egg),
      ]);
      expect(total.micros, 4 * 1000000);
      expect(total.approximate, isTrue);
    });

    test('isti ulazi traženi u gramima daju 200 g', () {
      final total = totalOf([
        conv(2, 'kom', grams, factors: egg),
        conv(100, 'g', grams, factors: egg),
      ]);
      expect(total.micros, 200 * 1000000);
      expect(total.approximate, isTrue);
    });

    test('250 ml brašna sa gustinom 0,6 g/ml je 150 g, približno', () {
      const flour = FoodConversionFactors(densityGPerMl: 0.6);
      final r = conv(250, 'ml', grams, factors: flour) as Converted;
      expect(r.micros, 150 * 1000000);
      expect(r.approximate, isTrue);
      expect(r.base, grams);
    });

    test('bez faktora zapremina se ne pretvara u grame', () {
      final r = conv(250, 'ml', grams);
      expect(r, isA<NeedsReview>());
      expect((r as NeedsReview).reason, ConversionReview.missingFactor);
    });

    test('faktor koji nije pozitivan i konačan važi kao da ga nema', () {
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        final r = conv(
          250,
          'ml',
          grams,
          factors: FoodConversionFactors(densityGPerMl: bad),
        );
        expect(r, isA<NeedsReview>(), reason: '$bad');
      }
    });
  });

  group('verzionisani faktori i domet domaćinstva', () {
    const shared = FoodConversionFactorRecord(
      id: 'shared-piece-v1',
      foodId: 'egg',
      kind: FoodConversionFactorKind.pieceWeightG,
      value: 50,
      source: 'reviewed-catalog',
      revision: 1,
      reviewed: true,
    );
    const home = FoodConversionFactorRecord(
      id: 'home-piece-v2',
      foodId: 'egg',
      kind: FoodConversionFactorKind.pieceWeightG,
      value: 60,
      source: 'household',
      revision: 2,
      householdId: 'home-a',
    );

    test('kućni faktor ima prednost i nosi izvor, reviziju i opseg', () {
      final resolved = resolveFoodConversionFactors(
        foodId: 'egg',
        householdId: 'home-a',
        currentRecords: [shared, home],
      );
      final converted = conv(2, 'kom', grams, factors: resolved) as Converted;

      expect(converted.micros, 120 * 1000000);
      expect(converted.factorEvidence, hasLength(1));
      expect(converted.factorEvidence.single.id, 'home-piece-v2');
      expect(converted.factorEvidence.single.source, 'household');
      expect(converted.factorEvidence.single.revision, 2);
      expect(converted.factorEvidence.single.householdId, 'home-a');
    });

    test('drugo domaćinstvo koristi pregledani deljeni faktor', () {
      final resolved = resolveFoodConversionFactors(
        foodId: 'egg',
        householdId: 'home-b',
        currentRecords: [shared, home],
      );
      final converted = conv(2, 'kom', grams, factors: resolved) as Converted;

      expect(converted.micros, 100 * 1000000);
      expect(converted.factorEvidence.single.id, 'shared-piece-v1');
      expect(converted.factorEvidence.single.householdId, isNull);
    });

    test('sukob kućnih faktora ne pada nazad na deljeni faktor', () {
      const conflictingHome = FoodConversionFactorRecord(
        id: 'home-piece-v3',
        foodId: 'egg',
        kind: FoodConversionFactorKind.pieceWeightG,
        value: 55,
        source: 'household',
        revision: 3,
        householdId: 'home-a',
      );
      final resolved = resolveFoodConversionFactors(
        foodId: 'egg',
        householdId: 'home-a',
        currentRecords: [shared, home, conflictingHome],
      );

      expect(
        conv(2, 'kom', grams, factors: resolved),
        isA<NeedsReview>().having(
          (r) => r.reason,
          'reason',
          ConversionReview.conflictingFactor,
        ),
      );
    });

    test('nepregledani deljeni faktor se ne koristi', () {
      const unreviewedShared = FoodConversionFactorRecord(
        id: 'shared-piece-unreviewed',
        foodId: 'egg',
        kind: FoodConversionFactorKind.pieceWeightG,
        value: 50,
        source: 'reviewed-catalog',
        revision: 1,
      );
      final resolved = resolveFoodConversionFactors(
        foodId: 'egg',
        householdId: 'home-a',
        currentRecords: [unreviewedShared],
      );

      expect(
        conv(2, 'kom', grams, factors: resolved),
        isA<NeedsReview>().having(
          (r) => r.reason,
          'reason',
          ConversionReview.missingFactor,
        ),
      );
    });

    test('odobrena konverzija zadržava staru reviziju kad stigne nova', () {
      final oldFactors = resolveFoodConversionFactors(
        foodId: 'egg',
        householdId: 'home-b',
        currentRecords: [shared],
      );
      final approved = conv(2, 'kom', grams, factors: oldFactors) as Converted;
      final saved = Converted.fromApprovedSnapshotJson(
        approved.toApprovedSnapshotJson(),
      );
      const updatedShared = FoodConversionFactorRecord(
        id: 'shared-piece-v2',
        foodId: 'egg',
        kind: FoodConversionFactorKind.pieceWeightG,
        value: 52,
        source: 'reviewed-catalog',
        revision: 2,
        reviewed: true,
      );
      final newFactors = resolveFoodConversionFactors(
        foodId: 'egg',
        householdId: 'home-b',
        currentRecords: [updatedShared],
      );
      final recalculated =
          conv(2, 'kom', grams, factors: newFactors) as Converted;

      expect(approved.micros, 100 * 1000000);
      expect(approved.factorEvidence.single.revision, 1);
      expect(saved.micros, approved.micros);
      expect(saved.factorEvidence.single.id, 'shared-piece-v1');
      expect(saved.factorEvidence.single.revision, 1);
      expect(recalculated.micros, 104 * 1000000);
      expect(recalculated.factorEvidence.single.revision, 2);
    });

    test('tačna konverzija ignoriše sukob faktora koji joj nije potreban', () {
      final resolved = resolveFoodConversionFactors(
        foodId: 'egg',
        householdId: 'home-a',
        currentRecords: [
          shared,
          home,
          const FoodConversionFactorRecord(
            id: 'home-density-a',
            foodId: 'egg',
            kind: FoodConversionFactorKind.densityGPerMl,
            value: 1,
            source: 'household',
            revision: 1,
            householdId: 'home-a',
          ),
          const FoodConversionFactorRecord(
            id: 'home-density-b',
            foodId: 'egg',
            kind: FoodConversionFactorKind.densityGPerMl,
            value: 1.1,
            source: 'household',
            revision: 2,
            householdId: 'home-a',
          ),
        ],
      );

      expect(conv(100, 'g', grams, factors: resolved), isA<Converted>());
    });

    test('kućni faktor za drugo domaćinstvo ne utiče na razrešenje', () {
      final resolved = resolveFoodConversionFactors(
        foodId: 'egg',
        householdId: 'home-b',
        currentRecords: [
          shared,
          home,
          const FoodConversionFactorRecord(
            id: 'other-home-piece',
            foodId: 'egg',
            kind: FoodConversionFactorKind.pieceWeightG,
            value: 80,
            source: 'household',
            revision: 1,
            householdId: 'home-c',
          ),
        ],
      );

      final converted = conv(2, 'kom', grams, factors: resolved) as Converted;
      expect(converted.micros, 100 * 1000000);
      expect(converted.factorEvidence.single.id, 'shared-piece-v1');
    });

    test('poreklo pakovanja se čuva uz konverziju', () {
      const packageRecord = FoodConversionFactorRecord(
        id: 'egg-carton-6-v1',
        foodId: 'egg',
        kind: FoodConversionFactorKind.packageAmount,
        value: 6,
        source: 'reviewed-catalog',
        revision: 1,
        unit: 'kom',
        packageId: 'carton-6',
        reviewed: true,
      );
      final resolved = resolveFoodConversionFactors(
        foodId: 'egg',
        householdId: 'home-b',
        currentRecords: [packageRecord],
      );
      final converted = conv(
        2,
        'pakovanje',
        piece,
        factors: resolved,
        packageId: 'carton-6',
      ) as Converted;

      expect(converted.micros, 12 * 1000000);
      expect(converted.factorEvidence.single.toJson(), {
        'id': 'egg-carton-6-v1',
        'food_id': 'egg',
        'kind': 'packageAmount',
        'value': 6.0,
        'source': 'reviewed-catalog',
        'revision': 1,
        'household_id': null,
        'unit': 'kom',
        'package_id': 'carton-6',
        'preparation_state': null,
      });
    });
  });

  group('kuhinjske mere', () {
    test('2 kašike i 1 kašičica su približno 35 ml', () {
      final total = totalOf([
        conv(2, 'kašika', ml, kitchen: true),
        conv(1, 'kašičica', ml, kitchen: true),
      ]);
      expect(total.micros, 35 * 1000000);
      expect(total.approximate, isTrue);
    });

    test('isti ulaz u gramima bez gustine ostaje za proveru', () {
      final r = conv(2, 'kašika', grams, kitchen: true);
      expect(r, isA<NeedsReview>());
      expect((r as NeedsReview).reason, ConversionReview.missingFactor);
    });

    test('kuhinjska mera je isključena dok izvor nije uključi', () {
      final r = conv(2, 'kašika', ml);
      expect((r as NeedsReview).reason, ConversionReview.unsupportedUnit);
    });
  });

  group('ono što ne sme da se pretvori', () {
    test('prstohvat soli ostaje original i traži "Proveri količinu"', () {
      final r = conv(1, 'prstohvat', grams);
      expect((r as NeedsReview).reason, ConversionReview.unsupportedUnit);
      final total = totalOf([conv(5, 'g', grams), r]);
      expect(total.micros, 5 * 1000000);
      expect(total.review, hasLength(1));
    });

    test('nepoznata ili neispravna količina traži proveru', () {
      for (final q in [null, 0.0, -2.0, double.nan, double.infinity]) {
        final r = conv(q, 'g', grams);
        expect(r, isA<NeedsReview>(), reason: '$q');
        expect(
          (r as NeedsReview).reason,
          ConversionReview.unknownQuantity,
          reason: '$q',
        );
      }
    });

    test('nepoznata jedinica ostaje za proveru', () {
      final r = conv(1, 'xyz', grams);
      expect((r as NeedsReview).reason, ConversionReview.unsupportedUnit);
    });
  });

  group('pakovanja', () {
    const factors = FoodConversionFactors(
      packages: {'p400': PackageAmount(400, 'g')},
    );

    test('dva izričito izabrana pakovanja od 400 g su približno 800 g', () {
      final r = conv(
        2,
        'pakovanje',
        grams,
        factors: factors,
        packageId: 'p400',
      ) as Converted;
      expect(r.micros, 800 * 1000000);
      expect(r.approximate, isTrue);
    });

    test('neodređeno pakovanje ostaje posebno', () {
      final r = conv(1, 'pakovanje', grams, factors: factors);
      expect((r as NeedsReview).reason, ConversionReview.unverifiedPackage);
    });

    test('nepoznat identifikator pakovanja nije izmišljen', () {
      final r = conv(
        1,
        'pakovanje',
        grams,
        factors: factors,
        packageId: 'nema',
      );
      expect((r as NeedsReview).reason, ConversionReview.unverifiedPackage);
    });
    test('neto jedinica pakovanja mora biti masa, zapremina ili komadi', () {
      const bad = FoodConversionFactors(
        packages: {
          'cup': PackageAmount(1, 'šolja'),
          'pinch': PackageAmount(1, 'prstohvat'),
          'unknown': PackageAmount(1, 'xyz'),
          'nested': PackageAmount(1, 'pakovanje'),
          'zero': PackageAmount(0, 'g'),
          'nan': PackageAmount(double.nan, 'g'),
        },
      );
      for (final id in bad.packages.keys) {
        final r = conv(
          1,
          'pakovanje',
          ml,
          factors: bad,
          kitchen: true,
          packageId: id,
        );
        expect(
          (r as NeedsReview).reason,
          ConversionReview.unverifiedPackage,
          reason: id,
        );
      }
    });

    test('pakovanje u zapremini i komadima je ispravna neto jedinica', () {
      const f = FoodConversionFactors(
        packages: {'l': PackageAmount(1, 'l'), 'k': PackageAmount(6, 'kom')},
      );
      expect(
        (conv(
          2,
          'pakovanje',
          ml,
          factors: f,
          packageId: 'l',
        ) as Converted).micros,
        2000 * 1000000,
      );
      expect(
        (conv(
          2,
          'pakovanje',
          piece,
          factors: f,
          packageId: 'k',
        ) as Converted).micros,
        12 * 1000000,
      );
    });
  });

  group('granice celobrojnih vrednosti', () {
    test('nepredstavljiva količina nije izuzetak ni tiho ograničenje', () {
      for (final q in [1e303, 1e13, 1e300]) {
        final r = conv(q, 'g', grams);
        expect(r, isA<NeedsReview>(), reason: '$q');
        expect((r as NeedsReview).reason, ConversionReview.outOfRange);
      }
    });

    test('rezultat faktora koji prelazi granicu ide u proveru', () {
      final r = conv(
        1e12,
        'l',
        grams,
        factors: const FoodConversionFactors(densityGPerMl: 1e9),
      );
      expect((r as NeedsReview).reason, ConversionReview.outOfRange);
    });

    test('zbir dve ispravne vrednosti ne sme da pređe u negativno', () {
      final a = conv(5e12, 'g', grams);
      final b = conv(5e12, 'g', grams);
      expect(a, isA<Converted>());
      final t = totalOf([a, b]);
      expect(t.micros, greaterThanOrEqualTo(0));
      expect(t.micros, (a as Converted).micros);
      expect(t.review.single.reason, ConversionReview.outOfRange);
    });
  });
}
