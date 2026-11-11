// Pravi SQL migraciju zajedničkog kataloga namirnica (036) iz pregledanog
// CSV-a. Ugovor: specs/036-food-catalog/contracts/catalog-csv.md.
// Usage: dart run scripts/catalog_seed.dart [csv] [izlaz.sql]
import 'dart:io';

import 'package:tavli/domain/food_catalog_csv.dart';

void main(List<String> args) {
  final input = args.isNotEmpty ? args[0] : 'supabase/catalog/foods.csv';
  final output = args.length > 1
      ? args[1]
      : 'supabase/migrations/20261112120200_food_catalog_seed.sql';
  try {
    final entries = parseCatalogCsv(File(input).readAsStringSync());
    File(output).writeAsStringSync(catalogSeedSql(entries));
    stdout.writeln('${entries.length} namirnica → $output');
  } on FormatException catch (e) {
    stderr.writeln('$input: ${e.message}');
    exitCode = 1;
  }
}
