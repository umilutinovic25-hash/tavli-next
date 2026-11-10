// Due-score concept adapted from Grocy, Copyright (c) 2017-2026 Bernd Bestel.
// MIT notice and pinned source: ../../third_party/grocy/.
import 'plan_calendar.dart';
import 'recipe.dart';
import 'shopping_demand.dart';
import 'shopping_sync.dart';
import 'supply_allocation.dart';

/// Read-only projection iste Ostave i postojećih rezervacija.
class PantryStock {
  const PantryStock({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.confirmedAt,
    this.expiresAt,
    this.sourceShoppingItemId,
    this.reservedMicros = 0,
    this.reservedWhole = false,
  });
  final String id, name;
  final double? quantity;
  final String? unit, sourceShoppingItemId;
  final DateTime? confirmedAt, expiresAt;
  final int reservedMicros;
  final bool reservedWhole;
  String get canonicalId => sourceShoppingItemId ?? id;
}

class SuggestedIngredient {
  const SuggestedIngredient({
    required this.name,
    required this.baseUnit,
    required this.requiredMicros,
    required this.matchedMicros,
    required this.missingMicros,
    this.soonExpiry,
    this.selected = false,
  });
  final String name, baseUnit;
  final int? requiredMicros, missingMicros;
  final int matchedMicros;
  final DateTime? soonExpiry;
  final bool selected;
  bool get needsQuantityCheck =>
      missingMicros == null || (selected && matchedMicros == 0);
}

class RecipeSuggestion {
  RecipeSuggestion({
    required this.recipe,
    required this.servings,
    required List<SuggestedIngredient> ingredients,
    required this.dueScore,
    this.earliestExpiry,
    this.selectionSize = 0,
  }) : ingredients = List.unmodifiable(ingredients);
  final Recipe recipe;
  final int servings, dueScore, selectionSize;
  int get selectedIngredientCount => ingredients
      .where((i) => i.selected)
      .map((i) => dictionaryIngredientKey(i.name, 1))
      .toSet()
      .length;
  final List<SuggestedIngredient> ingredients;
  final DateTime? earliestExpiry;
  bool get ready =>
      ingredients.isNotEmpty && ingredients.every((i) => i.missingMicros == 0);
  int get coveredCount => ingredients.where((i) => i.missingMicros == 0).length;

  /// Nepoznata količina nije potvrđen manjak i traži posebnu proveru.
  bool get missingOneOrTwo {
    if (ingredients.any((i) => i.needsQuantityCheck)) return false;
    final missing = {
      for (final i in ingredients)
        if (i.missingMicros! > 0) ingredientKey(i.name),
    };
    return missing.isNotEmpty && missing.length <= 2;
  }

  List<String> get soonIngredients => [
    for (final i in ingredients)
      if (i.soonExpiry != null) i.name,
  ];
}

typedef _Lot = ({PantryStock stock, int micros});

/// Kandidati se računaju nezavisno, bez rezervisanja ili trošenja zaliha.
/// Brojčano pokriće računa postojeći allocateSupply; FEFO je stabilan red
/// njegovih lokalnih id-eva. SQL šema i expired težine Grocy-ja se ne prenose.
/// Brz izbor filtrira i rangira nazive; nikada ne dodaje potvrđenu zalihu.
List<RecipeSuggestion> suggestRecipes(
  List<Recipe> recipes,
  List<PantryStock> stock, {
  required DateTime now,
  int servings = 2,
  List<String> selectedIngredients = const [],
}) {
  if (servings < minServings || servings > maxServings) {
    throw ArgumentError.value(servings, 'servings');
  }
  final selectedKeys = selectedIngredients
      .map((name) => dictionaryIngredientKey(name, 1))
      .toSet();
  if (selectedIngredients.length > 3 ||
      selectedKeys.length != selectedIngredients.length ||
      selectedIngredients.any(
        (name) => name.trim().isEmpty || name.trim().length > 80,
      )) {
    throw ArgumentError.value(selectedIngredients, 'selectedIngredients');
  }
  final lots = _usableLots(stock, now);
  final byId = <String, _Lot>{
    for (var i = 0; i < lots.length; i++)
      i.toString().padLeft(10, '0'): lots[i],
  };
  final supplies = [
    for (final MapEntry(:key, :value) in byId.entries)
      Supply(
        id: key,
        origin: SupplyOrigin.pantry,
        ingredient: ingredientKey(value.stock.name),
        unitGroup: normalizeUnit(value.stock.unit).group,
        micros: value.micros,
      ),
  ];
  final results = <RecipeSuggestion>[];
  for (final recipe in recipes) {
    if (recipe.servings < 1) continue;
    final lines = demandFor(
      DemandSource(
        id: recipe.id,
        baseServings: recipe.servings,
        servings: servings,
        ingredients: [
          for (final i in recipe.ingredients)
            if (i.name.trim().isNotEmpty) _safeIngredient(i),
        ],
      ),
    ).where((l) => l.micros != 0).toList();
    if (lines.isEmpty) continue;
    if (selectedKeys.isNotEmpty &&
        !lines.any(
          (line) =>
              selectedKeys.contains(dictionaryIngredientKey(line.name, 1)),
        )) {
      continue;
    }
    final allocation = allocateSupply([
      for (final line in lines) DemandRequest(line, const DemandOrder()),
    ], supplies);
    final ingredients = <SuggestedIngredient>[];
    var dueScore = 0;
    DateTime? earliest;
    for (final line in lines) {
      DateTime? expiry;
      for (final a in allocation.allocations.where(
        (a) => a.demand == line.key,
      )) {
        final date = byId[a.supplyId]!.stock.expiresAt;
        if (date != null &&
            _urgency(date, now) > 0 &&
            (expiry == null || date.isBefore(expiry))) {
          expiry = date;
        }
      }
      if (expiry != null) {
        dueScore += _urgency(expiry, now);
        if (earliest == null || expiry.isBefore(earliest)) earliest = expiry;
      }
      final remaining = allocation.remaining(line.key);
      ingredients.add(
        SuggestedIngredient(
          name: line.name,
          baseUnit: line.baseUnit,
          requiredMicros: line.micros,
          missingMicros: remaining,
          matchedMicros: (line.micros ?? 0) - (remaining ?? 0),
          soonExpiry: expiry,
          selected: selectedKeys.contains(
            dictionaryIngredientKey(line.name, 1),
          ),
        ),
      );
    }
    if (selectedKeys.isEmpty && !ingredients.any((i) => i.matchedMicros > 0)) {
      continue;
    }
    results.add(
      RecipeSuggestion(
        recipe: recipe,
        servings: servings,
        ingredients: ingredients,
        dueScore: dueScore,
        earliestExpiry: earliest,
        selectionSize: selectedKeys.length,
      ),
    );
  }
  return results..sort(_compare);
}

List<_Lot> _usableLots(List<PantryStock> stock, DateTime now) {
  final physical = <String>{};
  final ordered = [...stock]..sort((a, b) => a.id.compareTo(b.id));
  final lots = <_Lot>[];
  for (final s in ordered) {
    final q = s.quantity;
    if (s.confirmedAt == null ||
        s.reservedWhole ||
        q == null ||
        q <= 0 ||
        !_safeAmount(q, s.unit) ||
        (s.expiresAt?.isBefore(now) ?? false) ||
        s.name.trim().isEmpty) {
      continue;
    }
    if (!physical.add(s.canonicalId)) continue;
    final total = toMicros(q) * normalizeUnit(s.unit).factor;
    final free = (total - s.reservedMicros.clamp(0, total)).clamp(0, total);
    if (free > 0) lots.add((stock: s, micros: free));
  }
  lots.sort((a, b) {
    final expiry = _compareExpiry(a.stock.expiresAt, b.stock.expiresAt);
    return expiry != 0 ? expiry : a.stock.id.compareTo(b.stock.id);
  });
  return lots;
}

bool _safeAmount(double q, String? unit) =>
    q.isFinite &&
    q >= 0 &&
    q * microsPerUnit * normalizeUnit(unit).factor <= 9007199254740991;

Ingredient _safeIngredient(Ingredient i) =>
    i.quantity == null || _safeAmount(i.quantity!, i.unit)
    ? i
    : Ingredient(
        name: i.name,
        unit: i.unit,
        category: i.category,
        note: i.note,
      );

int _urgency(DateTime expires, DateTime now) {
  if (expires.isBefore(now)) return 0;
  final days = CivilDate.fromDateTime(now.toLocal())
      .daysUntil(CivilDate.fromDateTime(expires.toLocal()));
  return days >= 0 && days <= 7 ? 8 - days : 0;
}

int _compareExpiry(DateTime? a, DateTime? b) => a == null
    ? (b == null ? 0 : 1)
    : b == null
    ? -1
    : a.compareTo(b);

int _compare(RecipeSuggestion a, RecipeSuggestion b) {
  var order = b.selectedIngredientCount.compareTo(a.selectedIngredientCount);
  if (order != 0) return order;
  order = _compareExpiry(a.earliestExpiry, b.earliestExpiry);
  if (order != 0) return order;
  order = b.dueScore.compareTo(a.dueScore);
  if (order != 0) return order;
  order = (b.coveredCount * a.ingredients.length).compareTo(
    a.coveredCount * b.ingredients.length,
  );
  if (order != 0) return order;
  order = ingredientKey(a.recipe.title)
      .compareTo(ingredientKey(b.recipe.title));
  return order != 0 ? order : a.recipe.id.compareTo(b.recipe.id);
}
