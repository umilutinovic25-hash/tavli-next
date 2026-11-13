import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_demand.dart';

DemandSource source(int version, List<Ingredient> items, {String id = 's1'}) =>
    DemandSource(
      id: id,
      baseServings: 2,
      servings: 2,
      ingredients: items,
      dictionaryVersion: version,
    );

Ingredient item(String name, double q, String unit) =>
    Ingredient(name: name, quantity: q, unit: unit);

void main() {
  test('jogurt 1 čaša i 150 ml su jedna stavka od ~350 ml (v3)', () {
    final lines = demandFor(
      source(3, [item('jogurt', 1, 'čaša'), item('jogurt', 150, 'ml')]),
    );
    expect(lines, hasLength(1));
    expect(lines.single.micros, 350 * microsPerUnit);
    expect(lines.single.baseUnit, 'ml');
    expect(lines.single.approximate, true);
  });

  test('tačna pretvaranja nemaju znak približno (kg+g, dl+ml)', () {
    final mass = demandFor(
      source(3, [item('brašno', 1, 'kg'), item('brašno', 500, 'g')]),
    ).single;
    expect(mass.micros, 1500 * microsPerUnit);
    expect(mass.approximate, false);
    final volume = demandFor(
      source(3, [item('mleko', 2, 'dl'), item('mleko', 100, 'ml')]),
    ).single;
    expect(volume.micros, 300 * microsPerUnit);
    expect(volume.approximate, false);
  });

  test('v2 ostaje nepromenjen: čaša se ne spaja sa ml i nije približna', () {
    final lines = demandFor(
      source(2, [item('jogurt', 1, 'čaša'), item('jogurt', 150, 'ml')]),
    );
    expect(lines, hasLength(2));
    expect(lines.every((l) => !l.approximate), true);
  });

  test('zbir iz više izvora je približan ako je bar jedan deo približan', () {
    final needs = summarize([
      ...demandFor(source(3, [item('jogurt', 1, 'čaša')], id: 'a')),
      ...demandFor(source(3, [item('jogurt', 150, 'ml')], id: 'b')),
    ]);
    expect(needs, hasLength(1));
    expect(needs.single.micros, 350 * microsPerUnit);
    expect(needs.single.approximate, true);
  });

  test('komad i nepoznata količina se ne menjaju u v3', () {
    final lines = demandFor(
      source(3, [
        item('jaja', 3, 'kom'),
        const Ingredient(name: 'so', unit: 'kašičica'),
      ]),
    );
    expect(
      lines.firstWhere((l) => l.baseUnit == 'kom').micros,
      3 * microsPerUnit,
    );
    final unknown = lines.firstWhere((l) => l.isUnknown);
    expect(unknown.approximate, false);
  });
}
