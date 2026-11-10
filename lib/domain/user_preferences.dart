/// Preferencije ishrane domaćinstva: ishrana, namirnice koje ne volimo,
/// alergije i broj osoba. Čista logika, bez Fluttera; ograničenja su ista
/// kao u SQL migraciji (broj stavki, dužina, raspon porcija).
library;

/// Vrste ishrane. Naziv (`name`) je vrednost koja se čuva u bazi.
enum FoodDiet {
  vegetarian('vegetarijanska'),
  vegan('veganska'),
  glutenFree('bez glutena'),
  lactoseFree('bez laktoze');

  const FoodDiet(this.label);

  /// Naziv u aplikaciji (srpski).
  final String label;
}

const minServings = 1;
const maxServings = 20;
const defaultServings = 2;

/// Najviše stavki u jednoj listi (ne volim, alergije).
const maxPreferenceItems = 30;

/// Najviše znakova u jednoj stavki.
const maxPreferenceItemLength = 40;

/// Normalizuje listu namirnica: sečenje razmaka, mala slova, bez praznih i
/// bez ponavljanja (zadržava prvo pojavljivanje). Baca [ArgumentError] za
/// previše stavki ili predugačku stavku.
List<String> normalizeItems(Iterable<String> raw) {
  final seen = <String>{};
  final result = <String>[];
  for (final item in raw) {
    final value = item.trim().toLowerCase();
    if (value.isEmpty || !seen.add(value)) continue;
    if (value.length > maxPreferenceItemLength) {
      throw ArgumentError.value(
        item,
        'stavka',
        'Najviše $maxPreferenceItemLength znakova',
      );
    }
    result.add(value);
  }
  if (result.length > maxPreferenceItems) {
    throw ArgumentError.value(
      raw,
      'lista',
      'Najviše $maxPreferenceItems stavki',
    );
  }
  return List.unmodifiable(result);
}

class UserPreferences {
  UserPreferences({
    Iterable<FoodDiet> diet = const [],
    Iterable<String> dislikes = const [],
    Iterable<String> allergies = const [],
    this.servings = defaultServings,
  }) : diet = Set.unmodifiable(diet),
       dislikes = normalizeItems(dislikes),
       allergies = normalizeItems(allergies) {
    if (servings < minServings || servings > maxServings) {
      throw ArgumentError.value(servings, 'servings', 'Od 1 do 20');
    }
  }

  /// Podrazumevano stanje: nema unosa, dva člana domaćinstva.
  static final UserPreferences defaults = UserPreferences();

  final Set<FoodDiet> diet;
  final List<String> dislikes;
  final List<String> allergies;
  final int servings;

  /// Nema ničega što treba poslati AI-ju.
  bool get isEmpty =>
      diet.isEmpty &&
      dislikes.isEmpty &&
      allergies.isEmpty &&
      servings == defaultServings;

  UserPreferences copyWith({
    Set<FoodDiet>? diet,
    List<String>? dislikes,
    List<String>? allergies,
    int? servings,
  }) => UserPreferences(
    diet: diet ?? this.diet,
    dislikes: dislikes ?? this.dislikes,
    allergies: allergies ?? this.allergies,
    servings: servings ?? this.servings,
  );

  @override
  bool operator ==(Object other) =>
      other is UserPreferences &&
      other.servings == servings &&
      _sameSet(other.diet, diet) &&
      _sameList(other.dislikes, dislikes) &&
      _sameList(other.allergies, allergies);

  @override
  int get hashCode => Object.hash(
    servings,
    Object.hashAllUnordered(diet),
    Object.hashAll(dislikes),
    Object.hashAll(allergies),
  );

  @override
  String toString() =>
      'UserPreferences(diet: $diet, dislikes: $dislikes, '
      'allergies: $allergies, servings: $servings)';
}

bool _sameSet(Set<FoodDiet> a, Set<FoodDiet> b) =>
    a.length == b.length && a.containsAll(b);

bool _sameList(List<String> a, List<String> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
