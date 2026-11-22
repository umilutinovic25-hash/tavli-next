/// Attributed reference values for a food, expressed per 100 g of edible food.
///
/// A missing nutrient is unknown and stays null; it is never interpreted as
/// zero. Source, version, and reference identify the exact record used.
final class FoodNutrition {
  FoodNutrition({
    this.kcalPer100g,
    this.proteinGramsPer100g,
    this.fatGramsPer100g,
    this.carbsGramsPer100g,
    required String source,
    required String sourceVersion,
    required String sourceRef,
  }) : source = _requiredText(source, 'source'),
       sourceVersion = _requiredText(sourceVersion, 'sourceVersion'),
       sourceRef = _requiredText(sourceRef, 'sourceRef') {
    _validate(kcalPer100g, 'kcalPer100g');
    _validate(proteinGramsPer100g, 'proteinGramsPer100g');
    _validate(fatGramsPer100g, 'fatGramsPer100g');
    _validate(carbsGramsPer100g, 'carbsGramsPer100g');
  }

  final double? kcalPer100g;
  final double? proteinGramsPer100g;
  final double? fatGramsPer100g;
  final double? carbsGramsPer100g;
  final String source;
  final String sourceVersion;
  final String sourceRef;

  static String _requiredText(String value, String name) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(value, name, 'Ne sme biti prazno');
    }
    return trimmed;
  }

  static void _validate(double? value, String name) {
    if (value != null && (!value.isFinite || value < 0)) {
      throw ArgumentError.value(value, name, 'Očekuje se konačan broj >= 0');
    }
  }
}
