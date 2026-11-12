/// Alergije po osobi (039) i zaštitna provera sastojaka. Čista logika, bez
/// Fluttera; ograničenja su ista kao u SQL migraciji `member_allergies`.
library;

import 'food.dart';
import 'recipe.dart';
import 'shopping_sync.dart' show ingredientKey;
import 'user_preferences.dart' show normalizeItems;

/// Nazivi EU alergena za AI upit (engleski, jednoznačni).
const euAllergenPromptNames = <String, String>{
  'gluten': 'gluten',
  'crustaceans': 'crustaceans',
  'eggs': 'eggs',
  'fish': 'fish',
  'peanuts': 'peanuts',
  'soy': 'soy',
  'milk': 'milk',
  'nuts': 'tree nuts',
  'celery': 'celery',
  'mustard': 'mustard',
  'sesame': 'sesame',
  'sulphites': 'sulphites',
  'lupin': 'lupin',
  'molluscs': 'molluscs',
};

/// Alergije jedne osobe u jednom domaćinstvu. Id je `domaćinstvo:osoba`,
/// pa dva uređaja iste osobe pišu isti red.
class PersonAllergies {
  PersonAllergies({
    required this.householdId,
    required this.userId,
    Iterable<String> codes = const [],
    Iterable<String> custom = const [],
  }) : codes = Set.unmodifiable(codes),
       custom = List.unmodifiable(normalizeItems(custom)) {
    for (final c in this.codes) {
      if (!euAllergens.containsKey(c)) {
        throw ArgumentError.value(c, 'codes', 'Nepoznat alergen');
      }
    }
  }

  final String householdId;
  final String userId;

  /// Kodovi iz [euAllergens].
  final Set<String> codes;

  /// Slobodan unos (mala slova, bez ponavljanja).
  final List<String> custom;

  String get id => memberAllergyId(householdId, userId);

  bool get isEmpty => codes.isEmpty && custom.isEmpty;
}

String memberAllergyId(String householdId, String userId) =>
    '$householdId:$userId';

/// Unija alergija svih članova aktivnog domaćinstva: važi za svaki obrok.
class HouseholdAllergies {
  const HouseholdAllergies._(this.codes, this.custom);

  factory HouseholdAllergies.union(Iterable<PersonAllergies> members) {
    final codes = <String>{};
    // Stavke su već normalizovane po osobi; ograničenje od 30 važi po
    // osobi, ne za uniju.
    final custom = <String>{};
    for (final m in members) {
      codes.addAll(m.codes);
      custom.addAll(m.custom);
    }
    return HouseholdAllergies._(
      Set.unmodifiable(codes),
      List.unmodifiable(custom),
    );
  }

  static const none = HouseholdAllergies._({}, []);

  final Set<String> codes;
  final List<String> custom;

  bool get isEmpty => codes.isEmpty && custom.isEmpty;

  /// Za prikaz: EU nazivi po redosledu Uredbe, pa slobodan unos.
  List<String> get labels => [
    for (final MapEntry(:key, :value) in euAllergens.entries)
      if (codes.contains(key)) value,
    ...custom,
  ];

  /// Za AI upit: engleski EU nazivi, pa slobodan unos.
  List<String> get promptTerms => [
    for (final MapEntry(:key, :value) in euAllergenPromptNames.entries)
      if (codes.contains(key)) value,
    ...custom,
  ];
}

/// Sastojak koji pogađa alergiju; [allergen] je naziv za prikaz.
class AllergyHit {
  const AllergyHit(this.ingredient, this.allergen);

  final String ingredient;
  final String allergen;

  @override
  bool operator ==(Object other) =>
      other is AllergyHit &&
      other.ingredient == ingredient &&
      other.allergen == allergen;

  @override
  int get hashCode => Object.hash(ingredient, allergen);

  @override
  String toString() => 'AllergyHit($ingredient, $allergen)';
}

class AllergyCheck {
  const AllergyCheck(this.hits, {required this.unconfirmed});

  final List<AllergyHit> hits;

  /// Bar jedan sastojak nema poznatu namirnicu, a domaćinstvo ima
  /// alergije: recept se prihvata, ali uz oznaku.
  final bool unconfirmed;

  /// Pogođeni alergeni (nazivi), svaki jednom, redom pojavljivanja.
  List<String> get allergens => {for (final h in hits) h.allergen}.toList();
}

final _wordSplit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

List<String> _words(String text) => [
  for (final w in ingredientKey(text).split(_wordSplit))
    if (w.isNotEmpty) w,
];

/// Proverava sastojke prema alergijama domaćinstva. Namirnica sastojka je
/// njegov `foodId`, inače tačan alias. EU alergen pogađa preko kataloga;
/// slobodan unos preko kataloga ili kad naziv sadrži sve reči unosa kao
/// cele reči (lažna uzbuna je prihvatljiva, propust nije).
AllergyCheck checkAllergens(
  Iterable<Ingredient> ingredients,
  FoodCatalog catalog,
  HouseholdAllergies allergies,
) {
  if (allergies.isEmpty) return const AllergyCheck([], unconfirmed: false);
  final customFood = {
    for (final term in allergies.custom) term: catalog.match(term),
  };
  final hits = <AllergyHit>[];
  var unconfirmed = false;
  for (final i in ingredients) {
    final foodId = i.foodId ?? catalog.match(i.name);
    final known = foodId != null && catalog.byId(foodId) != null;
    if (!known) unconfirmed = true;
    if (known) {
      final codes = catalog.allergens(foodId);
      for (final MapEntry(:key, :value) in euAllergens.entries) {
        if (allergies.codes.contains(key) && codes.contains(key)) {
          hits.add(AllergyHit(i.name, value));
        }
      }
    }
    final words = _words(i.name).toSet();
    for (final term in allergies.custom) {
      final termWords = _words(term);
      final byFood = known && customFood[term] == foodId;
      final byName = termWords.isNotEmpty && words.containsAll(termWords);
      if (byFood || byName) hits.add(AllergyHit(i.name, term));
    }
  }
  return AllergyCheck(hits, unconfirmed: unconfirmed);
}

/// AI ni posle ponovnog zahteva nije vratio recept bez alergena.
class AllergenViolation implements Exception {
  const AllergenViolation(this.allergens);

  final List<String> allergens;

  @override
  String toString() =>
      'Nije pronađen recept bez alergena članova domaćinstva '
      '(${allergens.join(', ')}). Promeni zahtev i pokušaj ponovo.';
}

/// Šta treba za proveru AI recepta: katalog na uređaju i unija alergija.
typedef AllergyContext = ({FoodCatalog catalog, HouseholdAllergies allergies});
