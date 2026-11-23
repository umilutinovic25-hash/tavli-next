/// Pretraga recepata na uređaju: naziv i filteri po oznakama i vremenu
/// (specs/019-meal-selection-rules/contracts/recipe-search-contract.md).
///
/// Ista funkcija služi listi recepata, a kasnije i planu i predlogu iz
/// ostave. Radi nad receptima iz lokalne baze, pa radi i bez mreže.
library;

import 'dart:math' show sqrt;

import 'recipe.dart';
import 'recipe_format.dart';
import 'recipe_labels.dart';

/// Ponuđene granice vremena pripreme, u minutima.
const prepTimeLimits = [15, 30, 60];

/// Upit za pretragu. Prazan filter (`null`) ne sužava ništa; uključen
/// filter propušta samo recepte za koje je ta osobina poznata i odgovara.
class RecipeFilter {
  const RecipeFilter({
    this.query = '',
    this.meal,
    this.weight,
    this.dishKind,
    this.maxPrepMinutes,
  });

  static const none = RecipeFilter();

  /// Deo naziva; mala/velika slova i kvačice se ne razlikuju.
  final String query;
  final MealSuitability? meal;
  final DishWeight? weight;
  final DishKind? dishKind;

  /// Najviše toliko minuta pripreme.
  final int? maxPrepMinutes;

  /// Broj uključenih filtera, bez naziva.
  int get activeFilters =>
      [meal, weight, dishKind, maxPrepMinutes].where((f) => f != null).length;

  bool get hasFilters => activeFilters > 0;

  bool get isEmpty => query.trim().isEmpty && !hasFilters;

  RecipeFilter copyWith({
    String? query,
    MealSuitability? Function()? meal,
    DishWeight? Function()? weight,
    DishKind? Function()? dishKind,
    int? Function()? maxPrepMinutes,
  }) => RecipeFilter(
    query: query ?? this.query,
    meal: meal == null ? this.meal : meal(),
    weight: weight == null ? this.weight : weight(),
    dishKind: dishKind == null ? this.dishKind : dishKind(),
    maxPrepMinutes: maxPrepMinutes == null
        ? this.maxPrepMinutes
        : maxPrepMinutes(),
  );

  /// Isti naziv, bez filtera.
  RecipeFilter cleared() => RecipeFilter(query: query);

  @override
  bool operator ==(Object other) =>
      other is RecipeFilter &&
      other.query == query &&
      other.meal == meal &&
      other.weight == weight &&
      other.dishKind == dishKind &&
      other.maxPrepMinutes == maxPrepMinutes;

  @override
  int get hashCode =>
      Object.hash(query, meal, weight, dishKind, maxPrepMinutes);
}

/// Recepti koji ispunjavaju sve uslove iz [filter], istim redom.
List<Recipe> searchRecipes(Iterable<Recipe> recipes, RecipeFilter filter) {
  if (filter.isEmpty) return List.of(recipes);
  final q = normalizeForSearch(filter.query);
  return [
    for (final r in recipes)
      if (_matches(r, filter, q)) r,
  ];
}

/// Ranks locally cached recipe vectors by cosine similarity, then applies the
/// user's non-text filters. Recipes without a compatible vector are omitted.
List<Recipe> searchSemantically(
  Iterable<Recipe> recipes,
  RecipeFilter filter,
  List<double> queryVector,
  Map<String, List<double>> recipeVectors,
) {
  final ranked = <({Recipe recipe, double score, int order})>[];
  final filters = filter.copyWith(query: '');
  var order = 0;
  for (final recipe in recipes) {
    final currentOrder = order++;
    if (!_matches(recipe, filters, '')) continue;
    final vector = recipeVectors[recipe.id];
    if (vector == null || vector.length != queryVector.length) continue;
    final score = cosineSimilarity(queryVector, vector);
    if (score != null) {
      ranked.add((recipe: recipe, score: score, order: currentOrder));
    }
  }
  ranked.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.order.compareTo(b.order);
  });
  return [for (final match in ranked) match.recipe];
}

/// Cosine similarity; null means vectors are empty, incompatible or invalid.
double? cosineSimilarity(List<double> a, List<double> b) {
  if (a.isEmpty || a.length != b.length) return null;
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    final left = a[i];
    final right = b[i];
    if (!left.isFinite || !right.isFinite) return null;
    dot += left * right;
    normA += left * left;
    normB += right * right;
  }
  if (normA == 0 || normB == 0) return null;
  return dot / sqrt(normA * normB);
}

bool _matches(Recipe r, RecipeFilter f, String q) {
  if (q.isNotEmpty && !normalizeForSearch(r.title).contains(q)) return false;
  if (f.meal case final meal? when !r.labels.mealSet.contains(meal)) {
    return false;
  }
  if (f.weight case final weight? when r.labels.weightValue != weight) {
    return false;
  }
  if (f.dishKind case final kind? when r.labels.dishKindValue != kind) {
    return false;
  }
  if (f.maxPrepMinutes case final max?) {
    final minutes = r.prepMinutes;
    if (minutes == null || minutes > max) return false;
  }
  return true;
}
