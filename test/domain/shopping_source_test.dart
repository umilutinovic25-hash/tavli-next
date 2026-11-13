import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/food.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_demand.dart';
import 'package:tavli/domain/shopping_source.dart';

void main() {
  test('poreklo kupovine: obrok i priprema u oba smera', () {
    final sources = [
      ItemSource(
        title: 'Sarma',
        kind: ShoppingSourceKind.planEntry,
        servings: 4,
        date: CivilDate(2026, 11, 2),
        mealType: 'lunch',
      ),
      const ItemSource(
        title: 'Musaka',
        kind: ShoppingSourceKind.recipePreparation,
        servings: 2,
      ),
    ];
    final back = provenanceSources(provenanceJson(sources));
    expect(back.map((s) => s.title), ['Sarma', 'Musaka']);
    expect(back.first.date, CivilDate(2026, 11, 2));
    expect(back.first.mealType, 'lunch');
    expect(back.first.kind, ShoppingSourceKind.planEntry);
    expect(back.last.kind, ShoppingSourceKind.recipePreparation);
    expect(back.last.date, isNull);
  });

  test('raniji zapis (samo nazivi) i pokvaren zapis', () {
    expect(provenanceSources('{"sources":["Sarma"]}').single.title, 'Sarma');
    expect(provenanceSources(null), isEmpty);
    expect(provenanceSources('nije json'), isEmpty);
    expect(provenanceSources('{"sources":[42]}'), isEmpty);
  });

  test('zamrznut recept pripreme čuva samo sastojke koji fale', () {
    const recipe = RecipeSnapshot(
      title: 'Sarma',
      baseServings: 4,
      ingredients: [
        Ingredient(name: 'Kupus', quantity: 1, unit: 'kg'),
        Ingredient(name: 'Luk', quantity: 2, unit: 'kom'),
      ],
    );
    final missing = recipe.withIngredients([recipe.ingredients.first]);
    expect(missing.title, 'Sarma');
    expect(missing.baseServings, 4);
    expect(missing.ingredients.single.name, 'Kupus');
    final json = RecipeSnapshot.fromJson(missing.toJson());
    expect(json.ingredients.single.name, 'Kupus');
  });

  group('snimak v2 (036)', () {
    FoodCatalog catalog({int clove = 5000000}) => FoodCatalog(
      foods: const [
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
      ],
      aliases: const [
        FoodAlias(foodId: 'f_jaje', alias: 'jaja'),
        FoodAlias(foodId: 'f_beli_luk', alias: 'beli luk'),
      ],
      conversions: [
        FoodConversion(foodId: 'f_beli_luk', unit: 'čen', factorMicros: clove),
      ],
    );

    const recipe = RecipeSnapshot(
      title: 'Sos',
      baseServings: 2,
      ingredients: [
        Ingredient(name: 'Jaja', quantity: 2, unit: 'kom'),
        Ingredient(name: 'beli luk', quantity: 2, unit: 'čen'),
        Ingredient(name: 'zmajevo voće', quantity: 1, unit: 'kom'),
        Ingredient(name: 'luk', quantity: 1, unit: 'kom', foodId: 'own-izbor'),
      ],
    );

    List<DemandLine> lines(RecipeSnapshot s) => demandFor(
      DemandSource(
        id: 'x',
        baseServings: s.baseServings,
        servings: 2,
        ingredients: s.ingredients,
        dictionaryVersion: s.dictionaryVersion,
        conversions: s.conversions,
      ),
    );

    test('potvrda: verzija 2, foodId po aliasu, izbor osobe ostaje', () {
      final s = recipe.withCurrentDictionary(catalog());
      expect(s.dictionaryVersion, 3);
      expect(
        [for (final i in s.ingredients) i.foodId],
        ['f_jaje', 'f_beli_luk', null, 'own-izbor'],
      );
      expect(
        [for (final i in s.ingredients) i.name],
        ['Jaja', 'beli luk', 'zmajevo voće', 'luk'],
      );
      expect(s.conversions, {
        'f_beli_luk|čen': (factorMicros: 5000000, baseUnit: 'g'),
      });
    });

    test('JSON kružno čuva foodId i konverzije', () {
      final s = recipe.withCurrentDictionary(catalog());
      final back = RecipeSnapshot.fromJson(s.toJson());
      expect(back.dictionaryVersion, 3);
      expect(back.conversions, s.conversions);
      expect(back.ingredients.first.foodId, 'f_jaje');
      expect(back.toJson(), s.toJson());
    });

    test('kasnija ispravka kataloga ne menja odobren snimak', () {
      final approved = RecipeSnapshot.fromJson(
        recipe.withCurrentDictionary(catalog()).toJson(),
      );
      final luk = lines(approved)
          .firstWhere((l) => l.key.ingredient == 'food:f_beli_luk');
      expect(luk.micros, 10000000);
      // Katalog posle ispravke: čen = 4 g. Snimak i dalje računa 5 g.
      expect(
        catalog(clove: 4000000).conversion('f_beli_luk', 'čen')!.factorMicros,
        4000000,
      );
      final again = RecipeSnapshot.fromJson(approved.toJson());
      expect(
        lines(again)
            .firstWhere((l) => l.key.ingredient == 'food:f_beli_luk')
            .micros,
        10000000,
      );
    });

    test('bez kataloga: v2 bez konverzija, tekstualni ključ', () {
      final s = recipe.withCurrentDictionary();
      expect(s.dictionaryVersion, 3);
      expect(s.conversions, isEmpty);
      expect(s.ingredients.first.foodId, isNull);
      expect(lines(s).first.key.ingredient, 'v1:jaja');
    });

    test('withIngredients čuva verziju i konverzije', () {
      final s = recipe.withCurrentDictionary(catalog());
      final only = s.withIngredients([s.ingredients[1]]);
      expect(only.dictionaryVersion, 3);
      expect(only.conversions, s.conversions);
    });
  });
}
