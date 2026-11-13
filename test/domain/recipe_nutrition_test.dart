import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/food.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/recipe_nutrition.dart';

Nutrition n(double kcal, double p, double f, double c) => Nutrition(
  kcal: kcal,
  protein: p,
  fat: f,
  carbs: c,
  source: 'test',
  ref: '1',
);

final catalog = FoodCatalog(
  foods: [
    Food(
      id: 'f_krompir',
      name: 'krompir',
      category: 'ostalo',
      baseUnit: BaseUnit.g,
      nutrition: n(77, 2, 0.1, 17),
    ),
    Food(
      id: 'f_beli_luk',
      name: 'beli luk',
      category: 'ostalo',
      baseUnit: BaseUnit.g,
      nutrition: n(149, 6, 0.5, 33),
    ),
    Food(
      id: 'f_jaje',
      name: 'jaje',
      category: 'ostalo',
      baseUnit: BaseUnit.kom,
      nutrition: n(143, 12, 9.5, 0.7),
      unitGrams: 50,
    ),
    Food(
      id: 'f_mleko',
      name: 'mleko',
      category: 'ostalo',
      baseUnit: BaseUnit.ml,
      nutrition: n(61, 3, 3, 5),
      unitGrams: 1.03,
    ),
    Food(
      id: 'f_ulje',
      name: 'ulje',
      category: 'ostalo',
      baseUnit: BaseUnit.ml,
      nutrition: n(884, 0, 100, 0),
      unitGrams: 0.92,
    ),
    Food(
      id: 'f_jabuka',
      name: 'jabuka',
      category: 'ostalo',
      baseUnit: BaseUnit.kom,
      nutrition: n(52, 0.3, 0.2, 14),
      unitGrams: 182,
    ),
    Food(
      id: 'f_brasno',
      name: 'brašno',
      category: 'ostalo',
      baseUnit: BaseUnit.g,
      nutrition: n(364, 10, 1, 76),
    ),
    const Food(
      id: 'f_kajmak',
      name: 'kajmak',
      category: 'ostalo',
      baseUnit: BaseUnit.g,
    ),
    Food(
      id: 'f_jogurt',
      name: 'jogurt',
      category: 'ostalo',
      baseUnit: BaseUnit.ml,
      nutrition: n(61, 3.5, 3.3, 4.7),
    ),
  ],
  conversions: [
    const FoodConversion(
      foodId: 'f_beli_luk',
      unit: 'čen',
      factorMicros: 5000000,
    ),
  ],
);

Ingredient item(String id, double? q, String? unit) =>
    Ingredient(name: id, foodId: id, quantity: q, unit: unit);

RecipeNutrition? calc(List<Ingredient> items, {int servings = 1}) =>
    recipeNutritionPerServing(items, servings: servings, catalog: catalog);

void main() {
  test('grami puta vrednost na 100 g, podeljeno porcijama', () {
    final r = calc([item('f_krompir', 200, 'g')], servings: 2)!;
    expect(r.perServing.kcal, closeTo(77, 1e-9));
    expect(r.perServing.protein, closeTo(2, 1e-9));
    expect(r.perServing.fat, closeTo(0.1, 1e-9));
    expect(r.perServing.carbs, closeTo(17, 1e-9));
    expect((r.counted, r.total), (1, 1));
  });

  test('kg i dkg se pretvaraju u grame za svaku osnovnu jedinicu', () {
    expect(
      calc([item('f_krompir', 1, 'kg')])!.perServing.kcal,
      closeTo(770, 1e-9),
    );
    // dkg: 10 g po jedinici, i za komadnu namirnicu (jabuka, 20 dkg = 200 g).
    expect(
      calc([item('f_jabuka', 20, 'dkg')])!.perServing.kcal,
      closeTo(104, 1e-9),
    );
  });

  test('konverzija namirnice: 2 čena belog luka = 10 g', () {
    final r = calc([item('f_beli_luk', 2, 'čen')])!;
    expect(r.perServing.kcal, closeTo(14.9, 1e-9));
  });

  test('komad: težina komada iz kataloga (3 jajeta = 150 g)', () {
    final withUnit = calc([item('f_jaje', 3, 'kom')])!;
    final noUnit = calc([item('f_jaje', 3, null)])!;
    expect(withUnit.perServing.kcal, closeTo(214.5, 1e-9));
    expect(noUnit.perServing.kcal, closeTo(214.5, 1e-9));
  });

  test('ml: gustina iz kataloga; kašika je 15 ml', () {
    expect(
      calc([item('f_mleko', 250, 'ml')])!.perServing.kcal,
      closeTo(250 * 1.03 * 0.61, 1e-9),
    );
    expect(
      calc([item('f_ulje', 2, 'kašika')])!.perServing.fat,
      closeTo(2 * 15 * 0.92, 1e-9),
    );
    expect(
      calc([item('f_mleko', 2, 'dl')])!.perServing.kcal,
      closeTo(200 * 1.03 * 0.61, 1e-9),
    );
  });

  test('ne ulazi u zbir: bez namirnice, bez vrednosti, bez količine, '
      'nepoznata ili nemoguća jedinica', () {
    final r = calc([
      item('f_krompir', 100, 'g'),
      const Ingredient(name: 'so', quantity: 5, unit: 'g'),
      item('f_kajmak', 100, 'g'),
      item('f_beli_luk', null, 'g'),
      item('f_brasno', 1, 'čaša'),
      item('f_jogurt', 100, 'ml'),
      item('f_jaje', 2, 'prstohvat'),
    ])!;
    expect(r.perServing.kcal, closeTo(77, 1e-9));
    expect((r.counted, r.total), (1, 7));
  });

  test('ništa pokriveno: nema rezultata umesto pogrešnog broja', () {
    expect(
      calc([item('f_kajmak', 100, 'g'), item('f_jogurt', 100, 'ml')]),
      isNull,
    );
    expect(calc(const []), isNull);
  });

  test('neispravna količina ili porcije se ne računaju', () {
    expect(calc([item('f_krompir', -5, 'g')]), isNull);
    expect(calc([item('f_krompir', double.nan, 'g')]), isNull);
    expect(calc([item('f_krompir', 100, 'g')], servings: 0), isNull);
  });

  test('više sastojaka se sabira', () {
    final r = calc([
      item('f_krompir', 200, 'g'),
      item('f_jaje', 2, 'kom'),
    ], servings: 2)!;
    // (154 + 143) / 2
    expect(r.perServing.kcal, closeTo(148.5, 1e-9));
    expect((r.counted, r.total), (2, 2));
  });
}
