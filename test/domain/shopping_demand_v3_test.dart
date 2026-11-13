import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/shopping_demand.dart';

NormalizedUnit v3(String unit) => normalizeUnit(unit, dictionaryVersion: 3);
bool approx(String unit, int version) =>
    unitIsApproximate(unit, dictionaryVersion: version);

void main() {
  group('rečnik v3: kuhinjske mere', () {
    test('približne mere se pretvaraju u ml i nose znak približno', () {
      for (final (names, factor) in [
        (['čaša', 'Čaša', 'čaše', 'casa'], 200),
        (['šolja', 'šolje', 'solja'], 250),
        (['kašika', 'kašike', 'kasika'], 15),
        (['kašičica', 'kašičice', 'kasicica'], 5),
      ]) {
        for (final name in names) {
          final u = v3(name);
          expect((u.group, u.base, u.factor), ('volume', 'ml', factor));
          expect(approx(name, 3), true, reason: name);
        }
      }
    });

    test('dl i dkg su tačna pretvaranja bez znaka približno', () {
      final dl = v3('dl');
      expect((dl.group, dl.base, dl.factor), ('volume', 'ml', 100));
      expect(approx('dl', 3), false);
      final dkg = v3('dkg');
      expect((dkg.group, dkg.base, dkg.factor), ('mass', 'g', 10));
      expect(approx('dkg', 3), false);
    });

    test('g, kg, ml, l i kom ostaju isti i tačni', () {
      expect(v3('kg').factor, 1000);
      expect(approx('kg', 3), false);
      expect(v3('l').group, 'volume');
      expect(v3('kom').group, 'count:kom');
    });

    test('v2 se ne menja: čaša ostaje samostalna jedinica', () {
      expect(normalizeUnit('čaša', dictionaryVersion: 2).group, 'unit:čaša');
      expect(approx('čaša', 2), false);
    });

    test('v3 ključ sastojka: namirnica kao u v2, tekst kao u v1', () {
      expect(dictionaryIngredientKey('Jogurt', 3, foodId: 'f1'), 'food:f1');
      expect(
        dictionaryIngredientKey('Jogurt', 3),
        dictionaryIngredientKey('Jogurt', 1),
      );
    });
  });
}
