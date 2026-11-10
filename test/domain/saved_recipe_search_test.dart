import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/saved_recipe_search.dart';

Recipe recipe(String id, int? minutes, List<String> ingredients) => Recipe(
  id: id,
  title: 'Jelo $id',
  servings: 2,
  prepMinutes: minutes,
  ingredients: [for (final name in ingredients) Ingredient(name: name)],
  source: RecipeSource.manual,
  createdAt: DateTime.utc(2026),
);

void main() {
  test('kombinacija zahteva sve uslove i odbacuje nepoznate podatke', () {
    const filter = RecipeSearchFilter(
      query: 'jelo',
      maxMinutes: 30,
      includeIngredient: 'PILEĆ',
      excludeIngredient: 'kikiriki',
    );
    final recipes = [
      recipe('1', 30, ['Pileće meso', 'so']),
      recipe('2', 31, ['Pileće meso']),
      recipe('3', null, ['Pileće meso']),
      recipe('4', 20, ['Pileće meso', 'Kikiriki']),
      recipe('5', 20, []),
      recipe('6', 20, ['so']),
    ];
    expect(filter.apply(recipes).map((r) => r.id), ['1']);
    expect(
      const RecipeSearchFilter(excludeIngredient: 'so')
          .apply([
            recipe('empty', 10, []),
            recipe('ok', 10, ['brašno']),
          ])
          .map((r) => r.id),
      ['ok'],
    );
  });
  test('prazan filter čuva postojeću pretragu naslova', () {
    expect(
      const RecipeSearchFilter(query: 'ĆEVAP')
          .apply([recipe('ćevap', null, []), recipe('drugo', 10, [])])
          .map((r) => r.id),
      ['ćevap'],
    );
  });
}
