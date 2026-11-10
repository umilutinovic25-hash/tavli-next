import 'recipe.dart';
import 'recipe_format.dart';

/// Svi neprazni uslovi moraju biti ispunjeni.
class RecipeSearchFilter {
  const RecipeSearchFilter({
    this.query = '',
    this.maxMinutes,
    this.includeIngredient = '',
    this.excludeIngredient = '',
  });

  final String query;
  final int? maxMinutes;
  final String includeIngredient;
  final String excludeIngredient;

  List<Recipe> apply(List<Recipe> recipes) {
    final include = normalizeForSearch(includeIngredient);
    final exclude = normalizeForSearch(excludeIngredient);
    return [
      for (final recipe in filterRecipes(recipes, query))
        if ((maxMinutes == null ||
                (recipe.prepMinutes != null &&
                    recipe.prepMinutes! > 0 &&
                    recipe.prepMinutes! <= maxMinutes!)) &&
            ((include.isEmpty && exclude.isEmpty) ||
                (recipe.ingredients.isNotEmpty &&
                    recipe.ingredients.every((i) => i.name.trim().isNotEmpty) &&
                    (include.isEmpty ||
                        recipe.ingredients.any(
                          (i) => normalizeForSearch(i.name).contains(include),
                        )) &&
                    (exclude.isEmpty ||
                        !recipe.ingredients.any(
                          (i) => normalizeForSearch(i.name).contains(exclude),
                        )))))
          recipe,
    ];
  }
}

class SavedRecipeSearch {
  const SavedRecipeSearch({
    required this.id,
    required this.name,
    required this.filter,
  });
  final String id;
  final String name;
  final RecipeSearchFilter filter;
}
