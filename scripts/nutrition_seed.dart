// Pravi SQL migraciju nutritivnih vrednosti zajedničkih namirnica iz USDA
// FoodData Central (SR Legacy, CSV). Brojevi se čitaju iz USDA fajlova; skripta
// odbija mapiranje čiji se opis ne poklapa sa USDA zapisom.
// USDA fajlove (food.csv, food_nutrient.csv) preuzmi sa
// https://fdc.nal.usda.gov/download-datasets (SR Legacy, CSV) i raspakuj van repoa.
// Pravi i migraciju težine komada i gustine (kom/ml namirnice) iz food_portion.csv.
// Usage: dart run scripts/nutrition_seed.dart <usda-dir> <nutrition.sql> <weights.sql>
import 'dart:io';

import 'package:tavli/domain/food_catalog_csv.dart';
import 'package:tavli/domain/food_nutrition_csv.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln(
      'Usage: dart run scripts/nutrition_seed.dart <usda-dir> '
      '<novi-nutrition.sql> <novi-weights.sql>',
    );
    exitCode = 2;
    return;
  }
  final usda = args[0];
  final output = File(args[1]);
  final weightsOutput = File(args[2]);
  const mapPath = 'supabase/catalog/nutrition_map.csv';
  final created = <File>[];
  try {
    if (output.absolute.uri.normalizePath() ==
        weightsOutput.absolute.uri.normalizePath()) {
      throw const FormatException(
        'Izlazi moraju biti dva različita nova fajla.',
      );
    }
    for (final file in [output, weightsOutput]) {
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw FormatException('Izlaz već postoji: ${file.path}');
      }
    }
    final catalog = parseCatalogCsv(
      File('supabase/catalog/foods.csv').readAsStringSync(),
    );
    final rows = buildNutritionRows(
      mapCsv: File(mapPath).readAsStringSync(),
      catalogIds: {for (final e in catalog) e.food.id},
      usdaFoodCsv: File('$usda/food.csv').readAsStringSync(),
      usdaFoodNutrientCsv: File('$usda/food_nutrient.csv').readAsStringSync(),
    );
    const weightsPath = 'supabase/catalog/unit_weights.csv';
    final weights = buildUnitWeightRows(
      weightsCsv: File(weightsPath).readAsStringSync(),
      baseUnits: {for (final e in catalog) e.food.id: e.food.baseUnit.name},
      usdaPortionCsv: File('$usda/food_portion.csv').readAsStringSync(),
    );
    // Oba ulaza proveravamo pre prvog upisa. Postojeći izlaz se nikad ne
    // prepisuje, ni ako se pojavi između provere i stvaranja fajla.
    for (final (file, sql) in [
      (output, nutritionSeedSql(rows)),
      (weightsOutput, unitWeightSeedSql(weights)),
    ]) {
      file.createSync(exclusive: true);
      created.add(file);
      file.writeAsStringSync(sql);
    }
    stdout.writeln(
      '${rows.length} od ${catalog.length} namirnica '
      '(${(100 * rows.length / catalog.length).toStringAsFixed(0)}%) → ${output.path}',
    );
    stdout.writeln('${weights.length} težina → ${weightsOutput.path}');
  } on FormatException catch (e) {
    stderr.writeln('$mapPath: ${e.message}');
    exitCode = 1;
  } on FileSystemException catch (e) {
    // Uklanjamo samo nove izlaze koje je ovo izvršavanje već napravilo.
    for (final file in created) {
      if (file.existsSync()) file.deleteSync();
    }
    stderr.writeln('nutrition_seed: $e');
    exitCode = 1;
  }
}
