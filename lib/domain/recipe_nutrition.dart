import 'food.dart';
import 'recipe.dart';
import 'shopping_demand.dart';

/// Kalorije i makroi (g) za jednu porciju.
class NutritionTotals {
  const NutritionTotals({
    required this.kcal,
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  final double kcal;
  final double protein;
  final double fat;
  final double carbs;
}

/// Vrednost po porciji recepta i pokrivenost: [counted] od [total] sastojaka
/// je ušlo u zbir („računato za 7 od 8 sastojaka“).
class RecipeNutrition {
  const RecipeNutrition({
    required this.perServing,
    required this.counted,
    required this.total,
  });

  final NutritionTotals perServing;
  final int counted;
  final int total;

  bool get isComplete => counted == total;
}

/// Vrednost po porciji (kcal, proteini, masti, ugljeni hidrati) iz sastojaka
/// recepta, na uređaju: grami sastojka puta vrednost namirnice na 100 g,
/// zbir podeljen brojem porcija. Sastojak bez namirnice, bez vrednosti,
/// bez količine ili sa jedinicom koja se ne može pretvoriti u grame ne ulazi
/// u zbir (nepoznato nije nula). Vraća null kad nijedan sastojak nije
/// pokriven ili porcije nisu ispravne, da se ne prikaže pogrešan broj.
RecipeNutrition? recipeNutritionPerServing(
  List<Ingredient> ingredients, {
  required int servings,
  required FoodCatalog catalog,
}) {
  if (servings < 1) return null;
  var kcal = 0.0, protein = 0.0, fat = 0.0, carbs = 0.0;
  var counted = 0;
  for (final i in ingredients) {
    final food = i.foodId == null ? null : catalog.byId(i.foodId!);
    final nutrition = food?.nutrition;
    if (food == null || nutrition == null) continue;
    final grams = ingredientGrams(i, food, catalog);
    if (grams == null) continue;
    final k = grams / 100;
    kcal += k * nutrition.kcal;
    protein += k * nutrition.protein;
    fat += k * nutrition.fat;
    carbs += k * nutrition.carbs;
    counted++;
  }
  if (counted == 0) return null;
  return RecipeNutrition(
    perServing: NutritionTotals(
      kcal: kcal / servings,
      protein: protein / servings,
      fat: fat / servings,
      carbs: carbs / servings,
    ),
    counted: counted,
    total: ingredients.length,
  );
}

/// Težina sastojka u gramima, ili null kad se ne može pouzdano odrediti:
/// konverzija namirnice (čen), pa mase (g, kg, dkg) direktno, zapremine (ml,
/// dl, kašika...) preko gustine ml namirnice i komadi preko težine komada.
double? ingredientGrams(Ingredient i, Food food, FoodCatalog catalog) {
  final q = i.quantity;
  if (q == null || !q.isFinite || q < 0) return null;
  final unit = i.unit?.trim() ?? '';
  final perUnit = food.unitGrams;

  double? fromBase(double base) => switch (food.baseUnit) {
    BaseUnit.g => base,
    BaseUnit.ml || BaseUnit.kom => perUnit == null ? null : base * perUnit,
  };

  if (unit.isNotEmpty) {
    final conversion = catalog.conversion(food.id, unit);
    if (conversion != null) {
      return fromBase(q * conversion.factorMicros / microsPerUnit);
    }
  }
  if (unit.isEmpty) {
    return food.baseUnit == BaseUnit.kom ? fromBase(q) : null;
  }
  final normalized = normalizeUnit(unit, dictionaryVersion: 3);
  return switch (normalized.group) {
    'mass' => q * normalized.factor,
    'volume' =>
      food.baseUnit == BaseUnit.ml ? fromBase(q * normalized.factor) : null,
    'count:kom' => food.baseUnit == BaseUnit.kom ? fromBase(q) : null,
    _ => null,
  };
}
