// Nutritivne vrednosti zajedničkih namirnica iz USDA FoodData Central
// (SR Legacy, CC0). Mapiranje namirnica na USDA zapise je pregledan CSV
// (`supabase/catalog/nutrition_map.csv`); brojevi se uvek čitaju iz izvora,
// nikad ih ne određuje čovek ni AI.

/// Oznaka izvora koja se upisuje uz vrednosti (verzija skupa podataka).
const nutritionSourceId = 'usda-sr-legacy-2018-04';

const nutritionMapHeader = ['food_id', 'fdc_id', 'usda_description'];

/// USDA identifikatori nutrijenata (kcal, proteini, masti, ugljeni hidrati).
const _nutrientIds = {
  '1008': 'kcal',
  '1003': 'protein',
  '1004': 'fat',
  '1005': 'carbs',
};

final _amountPattern = RegExp(r'^\d+(\.\d+)?$');

/// Vrednosti na 100 g, tačno onako kako piše u izvoru.
class NutritionRow {
  const NutritionRow({
    required this.foodId,
    required this.fdcId,
    required this.kcal,
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  final String foodId;
  final int fdcId;
  final String kcal;
  final String protein;
  final String fat;
  final String carbs;
}

/// Čita mapiranje i USDA fajlove i vraća po jedan red za svaku namirnicu.
/// Baca [FormatException] sa brojem reda na prvu grešku: nepoznata ili
/// ponovljena namirnica, zapis kog nema u izvoru, opis koji se ne poklapa sa
/// zapisom (pogrešan id) ili zapis kome fali neki od četiri nutrijenta.
List<NutritionRow> buildNutritionRows({
  required String mapCsv,
  required Set<String> catalogIds,
  required String usdaFoodCsv,
  required String usdaFoodNutrientCsv,
}) {
  final lines = _lines(mapCsv);
  if (lines.isEmpty || !_sameList(_fields(lines.first), nutritionMapHeader)) {
    throw const FormatException('red 1: zaglavlje nije ispravno');
  }
  final entries = <(String, int, String)>[];
  final seen = <String>{};
  for (var i = 1; i < lines.length; i++) {
    final row = i + 1;
    Never fail(String what) => throw FormatException('red $row: $what');
    final f = _fields(lines[i]);
    if (f.length != nutritionMapHeader.length) {
      fail('očekivano ${nutritionMapHeader.length} kolona, ima ${f.length}');
    }
    final [foodId, fdc, description] = f;
    if (!catalogIds.contains(foodId)) {
      fail('namirnice „$foodId“ nema u katalogu');
    }
    if (!seen.add(foodId)) fail('namirnica „$foodId“ se ponavlja');
    final fdcId = int.tryParse(fdc);
    if (fdcId == null) fail('fdc_id „$fdc“ nije broj');
    entries.add((foodId, fdcId, description));
  }

  final wanted = {for (final e in entries) '${e.$2}'};
  final descriptions = <String, String>{};
  for (final line in _lines(usdaFoodCsv).skip(1)) {
    final f = _fields(line);
    if (f.length >= 3 && wanted.contains(f[0])) descriptions[f[0]] = f[2];
  }
  final values = <String, Map<String, String>>{};
  for (final line in _lines(usdaFoodNutrientCsv).skip(1)) {
    final f = _fields(line);
    if (f.length < 4 || !wanted.contains(f[1])) continue;
    final nutrient = _nutrientIds[f[2]];
    if (nutrient == null) continue;
    values.putIfAbsent(f[1], () => {})[nutrient] = f[3];
  }

  return [
    for (final (foodId, fdcId, description) in entries)
      () {
        Never fail(String what) => throw FormatException('$foodId: $what');
        final actual = descriptions['$fdcId'];
        if (actual == null) fail('USDA zapis $fdcId ne postoji u izvoru');
        if (actual != description) {
          fail('opis „$description“ se ne poklapa sa USDA zapisom „$actual“');
        }
        final n = values['$fdcId'] ?? const <String, String>{};
        for (final key in _nutrientIds.values) {
          final v = n[key];
          if (v == null || !_amountPattern.hasMatch(v)) {
            fail('USDA zapis $fdcId nema ispravnu vrednost za $key');
          }
        }
        return NutritionRow(
          foodId: foodId,
          fdcId: fdcId,
          kcal: n['kcal']!,
          protein: n['protein']!,
          fat: n['fat']!,
          carbs: n['carbs']!,
        );
      }(),
  ];
}

/// SQL migracija: samo zajedničke namirnice koje još nemaju vrednosti, pa se
/// ponovno pokretanje i ručna ispravka nikad ne gaze.
String nutritionSeedSql(List<NutritionRow> rows) {
  final b = StringBuffer(
    '-- Nutritivne vrednosti na 100 g, USDA FoodData Central (SR Legacy 2018-04,\n'
    '-- CC0). Generisano: dart run scripts/nutrition_seed.dart\n',
  );
  for (final r in rows) {
    b.writeln(
      'update public.foods set kcal_100 = ${r.kcal}, '
      'protein_100 = ${r.protein}, fat_100 = ${r.fat}, '
      'carbs_100 = ${r.carbs}, '
      "nutrition_source = '$nutritionSourceId', "
      "nutrition_ref = '${r.fdcId}' "
      "where id = '${r.foodId}' and household_id is null "
      'and kcal_100 is null;',
    );
  }
  return b.toString();
}

List<String> _lines(String csv) => [
  for (final line in csv.split(RegExp(r'\r?\n')))
    if (line.trim().isNotEmpty) line,
];

bool _sameList(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

/// Polja jednog reda: navodnici štite zarez, `""` je navodnik.
List<String> _fields(String line) {
  final out = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == ',' && !quoted) {
      out.add(field.toString());
      field.clear();
    } else {
      field.write(c);
    }
  }
  if (quoted) throw const FormatException('nepotpun red (navodnik)');
  out.add(field.toString());
  return out;
}
