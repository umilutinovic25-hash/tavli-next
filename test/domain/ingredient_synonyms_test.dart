import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_demand.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/domain/supply_allocation.dart';

void main() {
  test('potvrđeni nazivi spajaju se samo uz kompatibilne mere', () {
    final lines = demandFor(
      const DemandSource(
        id: 'a',
        baseServings: 2,
        servings: 2,
        dictionaryVersion: 1,
        ingredients: [
          Ingredient(name: 'Beli luk', quantity: 100, unit: 'g'),
          Ingredient(name: 'Češnjak', quantity: 50, unit: 'gram'),
          Ingredient(name: 'češnjak', quantity: 2, unit: 'komad'),
          Ingredient(name: 'kravlje mleko', quantity: 1, unit: 'l'),
          Ingredient(name: 'ovseno mleko', quantity: 1, unit: 'l'),
        ],
      ),
    );
    expect(lines, hasLength(4));
    expect(lines.first.micros, toMicros(150));
    expect(lines[1].key.unitGroup, 'count:kom');
    expect(lines[2].key.ingredient, isNot(lines[3].key.ingredient));
  });

  test('stari snimak čuva staro pravilo, novi pamti verziju', () {
    final old = RecipeSnapshot.fromJson({
      'title': 'Jelo',
      'servings': 2,
      'ingredients': [
        {'name': 'beli luk', 'quantity': 1, 'unit': 'g'},
        {'name': 'češnjak', 'quantity': 1, 'unit': 'g'},
      ],
    });
    List<DemandLine> lines(RecipeSnapshot s) => demandFor(
      DemandSource(
        id: 'a',
        baseServings: 2,
        servings: 2,
        ingredients: s.ingredients,
        dictionaryVersion: s.dictionaryVersion,
      ),
    );
    expect(lines(old), hasLength(2));
    final approved = old.withCurrentDictionary();
    expect(lines(RecipeSnapshot.fromJson(approved.toJson())), hasLength(1));
    expect(lines(RecipeSnapshot.fromJson(old.toJson())), hasLength(2));
  });

  test('stari i novi izvori dele jednu stvarnu zalihu', () {
    DemandLine line(String id, int version) => demandFor(
      DemandSource(
        id: id,
        baseServings: 2,
        servings: 2,
        dictionaryVersion: version,
        ingredients: const [
          Ingredient(name: 'beli luk', quantity: 100, unit: 'g'),
        ],
      ),
    ).single;
    final old = line('old', 0), current = line('new', 1);
    final result = allocateSupply(
      [
        DemandRequest(old, DemandOrder(date: DateTime.utc(2026))),
        DemandRequest(current, DemandOrder(date: DateTime.utc(2026, 1, 2))),
      ],
      [
        Supply(
          id: 's',
          origin: SupplyOrigin.pantry,
          ingredient: 'beli luk',
          unitGroup: 'mass',
          micros: toMicros(150),
          dictionaryIngredient: 'v1:beli luk',
          dictionaryUnitGroup: 'mass',
        ),
      ],
    );
    expect(result.remaining(old.key), 0);
    expect(result.remaining(current.key), toMicros(50));
  });
}
