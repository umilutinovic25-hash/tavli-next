import 'food.dart';
import 'recipe.dart';
import 'shopping_demand.dart';
import 'shopping_sync.dart';

/// Jedan red `supabase/catalog/foods.csv`: zajednička namirnica sa aliasima
/// (naziv je prvi), konverzijama i alergenima.
class CatalogEntry {
  const CatalogEntry({
    required this.food,
    required this.aliases,
    required this.conversions,
    required this.allergens,
  });

  final Food food;
  final List<String> aliases;
  final List<FoodConversion> conversions;
  final List<String> allergens;
}

const catalogCsvHeader = [
  'id',
  'name',
  'category',
  'base_unit',
  'aliases',
  'conversions',
  'allergens',
];

final _idPattern = RegExp(r'^f_[a-z0-9_]{1,60}$');
final _factorPattern = RegExp(r'^[1-9][0-9]*$');

/// Čita katalog po `specs/036-food-catalog/contracts/catalog-csv.md`. Baca
/// [FormatException] sa brojem reda na prvu grešku; ništa se ne pogađa.
List<CatalogEntry> parseCatalogCsv(String csv) {
  final lines = csv.split(RegExp(r'\r?\n'));
  if (lines.isEmpty || _join(_fields(lines.first)) != _join(catalogCsvHeader)) {
    throw const FormatException('red 1: zaglavlje nije ispravno');
  }
  final ids = <String>{};
  final aliases = <String>{};
  final entries = <CatalogEntry>[];
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    final row = i + 1;
    Never fail(String what) => throw FormatException('red $row: $what');

    final f = _fields(line);
    if (f.length != catalogCsvHeader.length) {
      fail('očekivano ${catalogCsvHeader.length} kolona, ima ${f.length}');
    }
    final [id, name, category, unitName, aliasField, convField, allergenField] =
        f;
    if (!_idPattern.hasMatch(id)) fail('id „$id“ nije oblika f_…');
    if (!ids.add(id)) fail('id „$id“ se ponavlja');
    if (name.isEmpty || name != ingredientKey(name)) {
      fail('naziv „$name“ nije normalizovan');
    }
    if (!ingredientCategories.contains(category)) {
      fail('nepoznata kategorija „$category“');
    }
    final unit = BaseUnit.values.asNameMap()[unitName];
    if (unit == null) fail('nepoznata osnovna jedinica „$unitName“');

    final names = [name, ..._list(aliasField)];
    for (final a in names) {
      if (a != ingredientKey(a)) fail('alias „$a“ nije normalizovan');
      if (!aliases.add(a)) fail('alias „$a“ se ponavlja');
    }

    final conversions = <FoodConversion>[];
    for (final c in _list(convField)) {
      final parts = c.split('=');
      final u = parts.first;
      if (parts.length != 2 ||
          u.isEmpty ||
          u != ingredientKey(u) ||
          !_factorPattern.hasMatch(parts.last) ||
          _isCovered(u, unit)) {
        fail('konverzija „$c“ nije ispravna');
      }
      conversions.add(
        FoodConversion(
          foodId: id,
          unit: u,
          factorMicros: int.parse(parts.last),
        ),
      );
    }

    final allergens = _list(allergenField);
    for (final a in allergens) {
      if (!euAllergens.containsKey(a)) fail('nepoznat alergen „$a“');
    }

    entries.add(
      CatalogEntry(
        food: Food(id: id, name: name, category: category, baseUnit: unit),
        aliases: names,
        conversions: conversions,
        allergens: allergens,
      ),
    );
  }
  return entries;
}

/// Jedinice koje obračun već pretvara (g↔kg, ml↔l, kom). Izuzetak je gustina:
/// ml za namirnicu u g i g za namirnicu u ml.
bool _isCovered(String unit, BaseUnit base) {
  final group = normalizeUnit(unit).group;
  if (group.startsWith('unit:')) return false;
  if (base == BaseUnit.g && unit == 'ml') return false;
  if (base == BaseUnit.ml && unit == 'g') return false;
  return true;
}

List<String> _list(String field) => field.isEmpty ? const [] : field.split('|');

String _join(List<String> f) => f.join(',');

/// Polja jednog CSV reda; navodnici omogućavaju zarez u polju (`""` = `"`).
List<String> _fields(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quoted) {
      if (ch == '"' && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else if (ch == '"') {
        quoted = false;
      } else {
        buf.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  out.add(buf.toString());
  return out;
}
