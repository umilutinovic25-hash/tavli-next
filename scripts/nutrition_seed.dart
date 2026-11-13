// Pravi SQL migraciju nutritivnih vrednosti zajedničkih namirnica iz USDA
// FoodData Central (SR Legacy, CSV). Brojevi se čitaju iz USDA fajlova; skripta
// odbija mapiranje čiji se opis ne poklapa sa USDA zapisom.
// USDA fajlove (food.csv, food_nutrient.csv) preuzmi sa
// https://fdc.nal.usda.gov/download-datasets (SR Legacy, CSV) i raspakuj van repoa.
// Pravi i migraciju težine komada i gustine (kom/ml namirnice) iz food_portion.csv.
// Usage: dart run scripts/nutrition_seed.dart <usda-direktorijum> [izlaz.sql]
import 'dart:io';

import 'package:tavli/domain/food_catalog_csv.dart';
import 'package:tavli/domain/food_nutrition_csv.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run scripts/nutrition_seed.dart <usda-dir> [izlaz.sql]',
    );
    exitCode = 2;
    return;
  }
  final usda = args[0];
  final output = args.length > 1
      ? args[1]
      : 'supabase/migrations/20261113190100_food_nutrition_seed.sql';
  const mapPath = 'supabase/catalog/nutrition_map.csv';
  try {
    final catalog = parseCatalogCsv(
      File('supabase/catalog/foods.csv').readAsStringSync(),
    );
    final rows = buildNutritionRows(
      mapCsv: File(mapPath).readAsStringSync(),
      catalogIds: {for (final e in catalog) e.food.id},
      usdaFoodCsv: File('$usda/food.csv').readAsStringSync(),
      usdaFoodNutrientCsv: File('$usda/food_nutrient.csv').readAsStringSync(),
    );
    File(output).writeAsStringSync(nutritionSeedSql(rows));
    stdout.writeln(
      '${rows.length} od ${catalog.length} namirnica '
      '(${(100 * rows.length / catalog.length).toStringAsFixed(0)}%) → $output',
    );
    const weightsPath = 'supabase/catalog/unit_weights.csv';
    const weightsOutput =
        'supabase/migrations/20261113200100_food_unit_weights_seed.sql';
    final weights = buildUnitWeightRows(
      weightsCsv: File(weightsPath).readAsStringSync(),
      baseUnits: {for (final e in catalog) e.food.id: e.food.baseUnit.name},
      usdaPortionCsv: File('$usda/food_portion.csv').readAsStringSync(),
    );
    File(weightsOutput).writeAsStringSync(unitWeightSeedSql(weights));
    stdout.writeln('${weights.length} težina → $weightsOutput');
  } on FormatException catch (e) {
    stderr.writeln('$mapPath: ${e.message}');
    exitCode = 1;
  }
}
