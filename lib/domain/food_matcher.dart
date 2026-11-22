import 'food_nutrition.dart';
import 'shopping_sync.dart';

/// Osnovna jedinica namirnice (ugovor o identitetu sastojka, verzija 1).
enum FoodBaseUnit { piece, gram, milliliter }

/// Namirnica iz kataloga. `id` je nepromenljiv UUID i ne izvodi se iz imena.
final class FoodIdentity {
  const FoodIdentity({
    required this.id,
    required this.slug,
    required this.name,
    required this.category,
    required this.baseUnit,
    this.nutrition,
  });

  final String id;
  final String slug;
  final String name;
  final String category;
  final FoodBaseUnit baseUnit;
  final FoodNutrition? nutrition;

  @override
  bool operator ==(Object other) => other is FoodIdentity && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Domaćinstvo u čijem opsegu se traži. Ugovor imenuje tip, ali ga ne
/// definiše; za sada nosi samo identifikator domaćinstva.
final class FoodLookupScope {
  const FoodLookupScope({required this.householdId});

  final String householdId;
}

sealed class FoodMatchResult {
  const FoodMatchResult();
}

/// Postoji dokaz da ulaz označava vraćenu namirnicu.
final class Matched extends FoodMatchResult {
  const Matched(this.food);

  final FoodIdentity food;
}

/// Nema pouzdanog poklapanja; originalni tekst ostaje upotrebljiv.
final class Unresolved extends FoodMatchResult {
  const Unresolved();
}

/// Predlog za postojeću vidljivu namirnicu (v1 ga nikad ne vraća).
final class Proposed extends FoodMatchResult {
  const Proposed(this.candidate);

  final FoodIdentity candidate;
}

abstract interface class FoodMatcher {
  Future<FoodMatchResult> findByName({
    required String originalText,
    required FoodLookupScope scope,
  });
}

/// Jedan red aliasa. `householdId == null` znači deljeni alias.
/// [withdrawn]: deljeni alias je povučen (`withdrawn_at`) i ne poklapa se.
final class AliasEntry {
  const AliasEntry({
    required this.food,
    required this.aliasNormalized,
    this.householdId,
    this.withdrawn = false,
  });

  final FoodIdentity food;
  final String aliasNormalized;
  final String? householdId;
  final bool withdrawn;
}

/// Namirnica kataloga i njen vlasnik. `householdId == null` = deljena.
/// [withdrawn]: deljena namirnica je povučena; nikad nije `Matched`, ni
/// preko imena ni preko aliasa koji pokazuju na nju.
final class CatalogFood {
  const CatalogFood(this.food, {this.householdId, this.withdrawn = false});

  final FoodIdentity food;
  final String? householdId;
  final bool withdrawn;
}

/// Matcher v1: samo tačan alias (ili kanonsko ime) preko `ingredientKey`.
/// Kanonska imena se indeksiraju iz `foods` sa vlasnikom namirnice, ne iz
/// redova aliasa, pa tuđi alias ne menja čiji je prioritet imena.
final class AliasFoodMatcher implements FoodMatcher {
  AliasFoodMatcher(
    List<AliasEntry> entries, {
    List<CatalogFood> foods = const [],
  }) : _entries = _activeEntries(entries, foods);

  /// Aktivni redovi: bez povučenih aliasa i bez svega što pokazuje na
  /// povučenu namirnicu; kanonska imena se dodaju kao aliasi vlasnika.
  static List<AliasEntry> _activeEntries(
    List<AliasEntry> entries,
    List<CatalogFood> foods,
  ) {
    final withdrawn = {
      for (final f in foods)
        if (f.withdrawn) f.food.id,
    };
    return [
      for (final e in entries)
        if (!e.withdrawn && !withdrawn.contains(e.food.id))
          AliasEntry(
            food: e.food,
            aliasNormalized: ingredientKey(e.aliasNormalized),
            householdId: e.householdId,
          ),
      for (final f in foods)
        if (!f.withdrawn)
          AliasEntry(
            food: f.food,
            aliasNormalized: ingredientKey(f.food.name),
            householdId: f.householdId,
          ),
    ];
  }

  final List<AliasEntry> _entries;

  @override
  Future<FoodMatchResult> findByName({
    required String originalText,
    required FoodLookupScope scope,
  }) async {
    final key = ingredientKey(originalText);
    if (key.isEmpty) return const Unresolved();
    final own = _foodsFor(key, scope.householdId);
    // Potvrda domaćinstva ima prednost nad deljenim aliasom.
    final foods = own.isNotEmpty ? own : _foodsFor(key, null);
    return foods.length == 1
        ? Matched(foods.values.single)
        : const Unresolved();
  }

  /// Namirnice čiji alias odgovara ključu; `householdId == null` = deljeni.
  Map<String, FoodIdentity> _foodsFor(String key, String? householdId) => {
    for (final e in _entries)
      if (e.householdId == householdId && e.aliasNormalized == key)
        e.food.id: e.food,
  };
}
