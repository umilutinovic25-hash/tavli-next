import 'recipe.dart';
import 'shopping_sync.dart';

/// Količine se porede u fiksnoj preciznosti od šest decimala: kao ceo broj
/// milionitih delova osnovne jedinice (g, ml, kom...).
const microsPerUnit = 1000000;

/// Porcije unosa plana i pripreme su 1–20, kao pri pravljenju recepta.
const minServings = 1;
const maxServings = 20;

/// Grupa jedinica za sastojak bez poznate količine; uvek ide na proveru.
const unknownGroup = 'unknown';

/// Pretvara količinu u milionite delove. Negativna i nekonačna vrednost nije
/// potvrđena količina, pa baca [ArgumentError].
int toMicros(double quantity) {
  if (!quantity.isFinite || quantity < 0) {
    throw ArgumentError.value(quantity, 'quantity', 'Neispravna količina');
  }
  return (quantity * microsPerUnit).round();
}

double fromMicros(int micros) => micros / microsPerUnit;

typedef NormalizedUnit = ({String group, String base, int factor});

const _units = <String, NormalizedUnit>{
  'g': (group: 'mass', base: 'g', factor: 1),
  'gr': (group: 'mass', base: 'g', factor: 1),
  'kg': (group: 'mass', base: 'g', factor: 1000),
  'ml': (group: 'volume', base: 'ml', factor: 1),
  'l': (group: 'volume', base: 'ml', factor: 1000),
  'kom': (group: 'count:kom', base: 'kom', factor: 1),
  'kom.': (group: 'count:kom', base: 'kom', factor: 1),
};

/// Rečnik v3 (043): kuhinjske mere. dl i dkg su tačni, ostalo je približno.
const _unitsV3 = <String, NormalizedUnit>{
  'dl': (group: 'volume', base: 'ml', factor: 100),
  'dkg': (group: 'mass', base: 'g', factor: 10),
  'čaša': (group: 'volume', base: 'ml', factor: 200),
  'šolja': (group: 'volume', base: 'ml', factor: 250),
  'kašika': (group: 'volume', base: 'ml', factor: 15),
  'kašičica': (group: 'volume', base: 'ml', factor: 5),
};

/// Kuhinjske mere sa približnom zapreminom; dl i dkg su tačni.
const _approximateV3 = {'čaša', 'šolja', 'kašika', 'kašičica'};

/// Oblici bez dijakritika i množina koji vode na kanonske v3 mere.
const _v3Aliases = <String, String>{
  'casa': 'čaša',
  'čaše': 'čaša',
  'case': 'čaša',
  'solja': 'šolja',
  'šolje': 'šolja',
  'solje': 'šolja',
  'kasika': 'kašika',
  'kašike': 'kašika',
  'kasike': 'kašika',
  'kasicica': 'kašičica',
  'kašičice': 'kašičica',
  'kasicice': 'kašičica',
};

/// Samo g↔kg i ml↔l se pretvaraju; komadi se sabiraju sa komadima. Ostale
/// jedinice su uporedive samo kad su iste (bez gustine i "kašika u ml").
NormalizedUnit normalizeUnit(String? unit, {int dictionaryVersion = 0}) {
  final u = (unit ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  // V1 is immutable: all aliases below have the same factor as the old
  // spelling, so a physical stock amount has one shared capacity.
  // V2 (036) uses the same frozen unit aliases as v1.
  final alias = dictionaryVersion >= 1
      ? const {
          'gram': 'g',
          'grama': 'g',
          'mililitar': 'ml',
          'mililitara': 'ml',
          'komad': 'kom',
          'komada': 'kom',
          'kasika': 'kašika',
        }[u]
      : null;
  final canonical = alias ?? u;
  if (dictionaryVersion >= 3) {
    final v3 = _unitsV3[_v3Aliases[canonical] ?? canonical];
    if (v3 != null) return v3;
  }
  return _units[canonical] ??
      (group: 'unit:$canonical', base: canonical, factor: 1);
}

/// Da li je pretvaranje jedinice približno (kuhinjska mera, samo v3); zbir
/// koji je sadrži nosi znak ~. Tačna pretvaranja (kg u g, dl u ml) ne.
bool unitIsApproximate(String? unit, {int dictionaryVersion = 0}) {
  if (dictionaryVersion < 3) return false;
  final u = (unit ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final canonical = const {'kasika': 'kašika'}[u] ?? u;
  return _approximateV3.contains(_v3Aliases[canonical] ?? canonical);
}

/// V0 preserves the original matching rule. Published dictionaries are frozen.
/// V2 (036): a confirmed catalog food is its own identity; an unconfirmed
/// ingredient keeps the v1 text identity.
String dictionaryIngredientKey(String name, int version, {String? foodId}) {
  final key = ingredientKey(name);
  if (version == 0) return key;
  if (version >= 2 && foodId != null) return 'food:$foodId';
  if (version < 1 || version > 3) {
    throw ArgumentError.value(version, 'version');
  }
  final canonical = const {'češnjak': 'beli luk'}[key] ?? key;
  return 'v1:$canonical';
}

/// Konverzija namirnice zamrznuta u snimku v2: jedna jedinica je
/// `factorMicros` milionitih delova osnovne jedinice `baseUnit` (g, ml, kom).
typedef FrozenConversion = ({int factorMicros, String baseUnit});

/// Ključ zamrznute konverzije: namirnica + normalizovana jedinica.
String conversionKey(String foodId, String unit) =>
    '$foodId|${ingredientKey(unit)}';

/// Grupa uporedivih jedinica za osnovnu jedinicu namirnice.
NormalizedUnit baseUnitGroup(String baseUnit) =>
    _units[baseUnit] ?? (group: 'unit:$baseUnit', base: baseUnit, factor: 1);

void _checkServings(int value, String name, {bool upper = true}) {
  if (value < minServings || (upper && value > maxServings)) {
    throw ArgumentError.value(value, name, 'Porcije van opsega');
  }
}

/// Količina sastojka za [servings] porcija recepta pravljenog za
/// [baseServings]. Nepoznata količina ostaje nepoznata.
double? scaleQuantity(
  double? quantity, {
  required int baseServings,
  required int servings,
}) {
  _checkServings(baseServings, 'baseServings', upper: false);
  _checkServings(servings, 'servings');
  return quantity == null ? null : quantity * servings / baseServings;
}

/// Jedan izvor potražnje: planirani obrok ili samostalna priprema recepta,
/// sa odobrenim sastojcima i porcijama.
class DemandSource {
  const DemandSource({
    required this.id,
    required this.baseServings,
    required this.servings,
    required this.ingredients,
    this.dictionaryVersion = 0,
    this.conversions = const {},
  });

  final int dictionaryVersion;

  /// Konverzije zamrznute pri potvrdi (samo v2), po [conversionKey].
  final Map<String, FrozenConversion> conversions;
  final String id;
  final int baseServings;
  final int servings;
  final List<Ingredient> ingredients;
}

/// Identitet potražnje: izvor + sastojak + grupa uporedivih jedinica. Isti
/// recept dva puta u planu ima dva izvora, pa i dve odvojene potrebe.
typedef DemandKey = ({String sourceId, String ingredient, String unitGroup});

class DemandLine {
  const DemandLine({
    required this.key,
    required this.name,
    required this.category,
    required this.micros,
    required this.baseUnit,
    this.notes = const [],
  });

  final DemandKey key;
  final String name;
  final String category;

  /// Potrebna količina u [baseUnit]; `null` kad količina nije poznata.
  final int? micros;
  final String baseUnit;
  final List<String> notes;

  bool get isUnknown => micros == null;

  /// Nepoznata količina se nikad ne oduzima brojčano; osoba je proverava.
  bool get needsReview => isUnknown;
}

/// Potrebe jednog izvora, skalirane na njegove porcije. Redovi istog sastojka
/// se spajaju samo kad su jedinice uporedive.
List<DemandLine> demandFor(DemandSource source) {
  _checkServings(source.baseServings, 'baseServings', upper: false);
  _checkServings(source.servings, 'servings');
  final merged = <DemandKey, DemandLine>{};
  for (final i in source.ingredients) {
    final v2 = source.dictionaryVersion == 2;
    final frozen = v2 && i.foodId != null && i.unit != null
        ? source.conversions[conversionKey(i.foodId!, i.unit!)]
        : null;
    final unit = frozen != null
        ? baseUnitGroup(frozen.baseUnit)
        : normalizeUnit(i.unit, dictionaryVersion: source.dictionaryVersion);
    final q = i.quantity;
    final known = q != null && q.isFinite && q >= 0;
    final key = (
      sourceId: source.id,
      ingredient: dictionaryIngredientKey(
        i.name,
        source.dictionaryVersion,
        foodId: v2 ? i.foodId : null,
      ),
      unitGroup: known ? unit.group : unknownGroup,
    );
    final base = !known
        ? null
        : frozen != null
        ? (toMicros(q) * frozen.factorMicros + microsPerUnit ~/ 2) ~/
              microsPerUnit
        : toMicros(q) * unit.factor;
    final micros = base == null
        ? null
        : _scale(base, source.servings, source.baseServings);
    final prev = merged[key];
    merged[key] = DemandLine(
      key: key,
      name: prev?.name ?? i.name.trim(),
      category: prev?.category ?? i.category,
      micros: prev == null
          ? micros
          : (micros == null ? null : prev.micros! + micros),
      baseUnit: prev?.baseUnit ?? unit.base,
      notes: [...?prev?.notes, if (i.note != null) i.note!],
    );
  }
  return merged.values.toList();
}

int _scale(int micros, int servings, int base) =>
    (micros * servings + base ~/ 2) ~/ base;

/// Zbir istih sastojaka iz više izvora za prikaz liste. Izvori ostaju
/// vidljivi; nepoznate količine se ne sabiraju sa poznatim.
class ShoppingNeed {
  const ShoppingNeed({
    required this.ingredient,
    required this.unitGroup,
    required this.name,
    required this.category,
    required this.micros,
    required this.baseUnit,
    required this.sourceIds,
  });

  final String ingredient;
  final String unitGroup;
  final String name;
  final String category;
  final int? micros;
  final String baseUnit;
  final List<String> sourceIds;

  bool get isUnknown => micros == null;
}

List<ShoppingNeed> summarize(Iterable<DemandLine> lines) {
  final groups = <(String, String), List<DemandLine>>{};
  for (final l in lines) {
    groups.putIfAbsent((l.key.ingredient, l.key.unitGroup), () => []).add(l);
  }
  return [
    for (final MapEntry(key: (ingredient, group), value: ls) in groups.entries)
      ShoppingNeed(
        ingredient: ingredient,
        unitGroup: group,
        name: ls.first.name,
        category: ls.first.category,
        micros: group == unknownGroup
            ? null
            : ls.fold<int>(0, (sum, l) => sum + l.micros!),
        baseUnit: ls.first.baseUnit,
        sourceIds: {for (final l in ls) l.key.sourceId}.toList(),
      ),
  ];
}

/// Količina za prikaz: od 1000 g/ml naviše u kg/l.
({double quantity, String unit}) displayAmount(int micros, String baseUnit) {
  final q = fromMicros(micros);
  if (q >= 1000 && baseUnit == 'g') return (quantity: q / 1000, unit: 'kg');
  if (q >= 1000 && baseUnit == 'ml') return (quantity: q / 1000, unit: 'l');
  return (quantity: q, unit: baseUnit);
}
