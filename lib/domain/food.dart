import 'recipe.dart';
import 'shopping_demand.dart';
import 'shopping_sync.dart';

/// Osnovna jedinica namirnice: u njoj se meri zaliha i potreba.
enum BaseUnit { kom, g, ml }

/// Nutritivne vrednosti na 100 g sa izvorom (045). Nepoznato je odsustvo
/// objekta ([Food.nutrition] == null), nikad nula.
class Nutrition {
  const Nutrition({
    required this.kcal,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.source,
    required this.ref,
  });

  final double kcal;
  final double protein;
  final double fat;
  final double carbs;

  /// Izvor, npr. `usda-sr-legacy-2018-04`, i oznaka zapisa u njemu (FDC id).
  final String source;
  final String ref;
}

/// Namirnica iz kataloga (036). [householdId] je null za zajednički katalog,
/// inače je to sopstvena namirnica domaćinstva. Id se nikad ne menja.
class Food {
  const Food({
    required this.id,
    required this.name,
    required this.category,
    required this.baseUnit,
    this.householdId,
    this.nutrition,
    this.unitGrams,
  });

  final String id;
  final String? householdId;

  /// Vrednosti na 100 g; null kad su nepoznate.
  final Nutrition? nutrition;

  /// Gramska težina osnovne jedinice: komad (kom) ili gustina g/ml (ml);
  /// null za g namirnice (1 g je 1 g) i kad je nepoznata.
  final double? unitGrams;

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

  /// Namirnice čiji naziv ili alias sadrži [query] (posle normalizacije),
  /// svaka jednom, po nazivu; prazan upit vraća sve.
  List<Food> search(String query) {
    final q = ingredientKey(query);
    final ids = <String>{
      for (final f in _foods.values)
        if (f.name.contains(q)) f.id,
      for (final e in [..._shared.entries, ..._own.entries])
        if (e.key.contains(q)) e.value,
    };
    return [for (final id in ids) ?_foods[id]]
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  FoodConversion? conversion(String foodId, String unit) =>
      _conversions[(foodId, ingredientKey(unit))];

  Set<String> allergens(String foodId) => _allergens[foodId] ?? const {};
}

/// Sastojci sa popunjenom namirnicom po tačnom aliasu; izbor osobe
/// (postojeći `foodId`) se nikad ne menja, tekst ostaje isti.
List<Ingredient> matchFoods(List<Ingredient> items, FoodCatalog catalog) => [
  for (final i in items)
    i.foodId != null ? i : i.withFood(catalog.match(i.name)),
];

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

/// Predlog nove namirnice za nepotvrđen sastojak (npr. iz AI recepta). Samo
/// nacrt: upisuje ga osoba kroz formu, uvek kao sopstvenu namirnicu
/// domaćinstva (`FoodRepository.createOwn`); AI ne piše u katalog. Osnovna
/// jedinica se predlaže samo kad je jasna (g/kg, ml/l, kom), inače je bira
/// osoba.
FoodDraft? suggestFood(Ingredient ingredient) {
  if (ingredient.foodId != null) return null;
  final name = ingredientKey(ingredient.name);
  if (name.isEmpty) return null;
  final base = normalizeUnit(ingredient.unit, dictionaryVersion: 2).base;
  return FoodDraft(
    name: name,
    category: ingredientCategories.contains(ingredient.category)
        ? ingredient.category
        : 'ostalo',
    baseUnit: BaseUnit.values.asNameMap().containsKey(base) ? base : null,
  );
}

class ValidFoodDraft {
  const ValidFoodDraft._(this.name, this.category, this.baseUnit);

  final String name;
  final String category;
  final BaseUnit baseUnit;
}

/// Oznake alergena recepta iz namirnica njegovih sastojaka. `complete` je
/// false čim jedan sastojak nema potvrđenu namirnicu (ili je nema u
/// katalogu): tada prazan skup ne znači „bez alergena“.
({Set<String> codes, bool complete}) recipeAllergens(
  Recipe recipe,
  FoodCatalog catalog,
) {
  final codes = <String>{};
  var complete = true;
  for (final i in recipe.ingredients) {
    final id = i.foodId;
    if (id == null || catalog.byId(id) == null) {
      complete = false;
      continue;
    }
    codes.addAll(catalog.allergens(id));
  }
  return (codes: codes, complete: complete);
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
