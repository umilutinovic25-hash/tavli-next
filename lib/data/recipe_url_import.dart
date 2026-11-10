import 'package:supabase/supabase.dart';

import '../domain/ids.dart';
import '../domain/recipe.dart';

class RecipeUrlImportException implements Exception {
  const RecipeUrlImportException({
    this.noRecipe = false,
    this.rateLimited = false,
  });
  final bool noRecipe;

  /// Nalog je potrošio dozvoljen broj uvoza (10 u minuti, 60 dnevno).
  final bool rateLimited;
}

abstract class RecipeUrlImporter {
  Future<Recipe> fetch(String url);
}

class SupabaseRecipeUrlImporter implements RecipeUrlImporter {
  SupabaseRecipeUrlImporter(this.client, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  final SupabaseClient? client;
  final DateTime Function() clock;

  @override
  Future<Recipe> fetch(String url) async {
    final current = client;
    if (current == null) throw const RecipeUrlImportException();
    try {
      final response = await current.functions.invoke(
        'recipe-url-import',
        body: {'url': url},
      );
      final body = response.data;
      if (body is! Map<String, dynamic>) throw const FormatException();
      final result = body['recipe'];
      final sourceUrl = body['sourceUrl'];
      if (result is! Map<String, dynamic> || sourceUrl is! String) {
        throw const FormatException();
      }
      final title = result['title'];
      final items = result['ingredients'];
      final steps = result['steps'];
      final servings = result['servings'];
      if (title is! String ||
          title.trim().isEmpty ||
          items is! List ||
          items.isEmpty ||
          items.any((item) => item is! String || item.trim().isEmpty) ||
          steps is! List ||
          steps.any((step) => step is! String) ||
          (servings != null &&
              (servings is! int || servings < 1 || servings > 99))) {
        throw const FormatException();
      }
      return Recipe(
        id: newId(),
        title: title,
        servings: servings as int? ?? 2,
        ingredients: [
          for (final item in items) Ingredient(name: item as String),
        ],
        steps: [for (final step in steps) step as String],
        source: RecipeSource.url,
        sourceUrl: sourceUrl,
        createdAt: clock(),
      );
    } on FunctionException catch (e) {
      throw RecipeUrlImportException(
        noRecipe: e.status == 422,
        rateLimited: e.status == 429,
      );
    } on Exception {
      throw const RecipeUrlImportException();
    }
  }
}
