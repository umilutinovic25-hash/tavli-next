import 'recipe.dart';
import 'shopping_sync.dart';

/// Osnovna jedinica namirnice: u njoj se meri zaliha i potreba.
enum BaseUnit { kom, g, ml }

/// Namirnica iz kataloga (036). [householdId] je null za zajednički katalog,
/// inače je to sopstvena namirnica domaćinstva. Id se nikad ne menja.
class Food {
  const Food({
    required this.id,
    required this.name,
    required this.category,
    required this.baseUnit,
    this.householdId,
  });

  final String id;
  final String? householdId;

  /// Nominativ jednine, mala slova (prikaz).
  final String name;
  final String category;
  final BaseUnit baseUnit;

  bool get isShared => householdId == null;
}

/// Normalizovan tekst koji pokazuje na namirnicu.
class FoodAlias {
  const FoodAlias({
    required this.foodId,
    required this.alias,
    this.householdId,
  });

  final String foodId;
  final String? householdId;
  final String alias;
}

/// Jedna [unit] namirnice je [factorMicros] milionitih delova njene osnovne
/// jedinice (čen belog luka = 5 g → 5 000 000).
class FoodConversion {
  const FoodConversion({
    required this.foodId,
    required this.unit,
    required this.factorMicros,
  });

  final String foodId;
  final String unit;
  final int factorMicros;
}

/// Nepromenljiv pogled na katalog na uređaju (zajednički + domaćinstvo).
class FoodCatalog {
  FoodCatalog({
    Iterable<Food> foods = const [],
    Iterable<FoodAlias> aliases = const [],
    Iterable<FoodConversion> conversions = const [],
    Iterable<({String foodId, String code})> allergens = const [],
  }) {
    for (final f in foods) {
      _foods[f.id] = f;
    }
    for (final a in aliases) {
      final key = ingredientKey(a.alias);
      // Zajednički alias se nikad ne zaklanja sopstvenim (research R8).
      if (a.householdId == null) {
        _shared[key] = a.foodId;
      } else {
        _own.putIfAbsent(key, () => a.foodId);
      }
    }
    for (final c in conversions) {
      _conversions[(c.foodId, ingredientKey(c.unit))] = c;
    }
    for (final a in allergens) {
      _allergens.putIfAbsent(a.foodId, () => {}).add(a.code);
    }
  }

  static final empty = FoodCatalog();

  final _foods = <String, Food>{};
  final _shared = <String, String>{};
  final _own = <String, String>{};
  final _conversions = <(String, String), FoodConversion>{};
  final _allergens = <String, Set<String>>{};

  Iterable<Food> get foods => _foods.values;

  Food? byId(String id) => _foods[id];

  /// Id namirnice čiji je alias tačno [text] posle normalizacije; bez
  /// približnog poklapanja.
  String? match(String text) {
    final key = ingredientKey(text);
    if (key.isEmpty) return null;
    return _shared[key] ?? _own[key];
  }

  FoodConversion? conversion(String foodId, String unit) =>
      _conversions[(foodId, ingredientKey(unit))];

  Set<String> allergens(String foodId) => _allergens[foodId] ?? const {};
}

/// Nacrt sopstvene namirnice pre upisa (osoba ili AI predlog). [validate]
/// baca [FormatException] na pokvaren nacrt, pa ništa ne ide u bazu.
class FoodDraft {
  const FoodDraft({
    required this.name,
    required this.category,
    required this.baseUnit,
  });

  final String name;
  final String category;
  final String? baseUnit;

  static const maxNameLength = 60;

  ValidFoodDraft validate() {
    final n = ingredientKey(name);
    if (n.isEmpty) throw const FormatException('Namirnica nema naziv');
    if (n.length > maxNameLength) {
      throw const FormatException('Naziv namirnice je predugačak');
    }
    if (!ingredientCategories.contains(category)) {
      throw const FormatException('Nepoznata kategorija');
    }
    final unit = BaseUnit.values.asNameMap()[baseUnit];
    if (unit == null) throw const FormatException('Nepoznata osnovna jedinica');
    return ValidFoodDraft._(n, category, unit);
  }
}

class ValidFoodDraft {
  const ValidFoodDraft._(this.name, this.category, this.baseUnit);

  final String name;
  final String category;
  final BaseUnit baseUnit;
}

/// 14 alergena iz EU Uredbe 1169/2011, Prilog II: kod → naziv za prikaz.
/// Isti kodovi su u serverskoj tabeli `allergens`.
const euAllergens = <String, String>{
  'gluten': 'gluten',
  'crustaceans': 'rakovi',
  'eggs': 'jaja',
  'fish': 'riba',
  'peanuts': 'kikiriki',
  'soy': 'soja',
  'milk': 'mleko',
  'nuts': 'orašasti plodovi',
  'celery': 'celer',
  'mustard': 'slačica',
  'sesame': 'susam',
  'sulphites': 'sulfiti',
  'lupin': 'lupina',
  'molluscs': 'mekušci',
};
