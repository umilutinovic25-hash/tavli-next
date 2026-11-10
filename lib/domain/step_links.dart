/// Veze sastojaka i koraka pripreme. Koraci ostaju tekst; veza pamti tekst
/// koraka i id sastojka, pa premeštanje ili izmena koraka (i u starijoj
/// verziji aplikacije) vezu nikad ne prebacuje na drugi korak ili sastojak.
library;

import 'recipe.dart';
import 'recipe_format.dart' show normalizeForSearch;

/// Sastojak (po id-ju) koji se koristi u koraku, uz opcionu količinu.
/// Bez količine: raspodela nije poznata i ne izmišlja se.
class StepUse {
  const StepUse({required this.ingredientId, this.quantity, this.unit});

  final String ingredientId;
  final double? quantity;
  final String? unit;

  /// null kad zapis nema id sastojka.
  static StepUse? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['ingredientId'];
    if (id is! String || id.isEmpty) return null;
    final q = json['quantity'];
    final unit = json['unit'];
    return StepUse(
      ingredientId: id,
      quantity: q is num && q > 0 ? q.toDouble() : null,
      unit: unit is String && unit.trim().isNotEmpty ? unit.trim() : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'ingredientId': ingredientId,
    if (quantity != null) 'quantity': quantity,
    if (unit != null) 'unit': unit,
  };

  @override
  bool operator ==(Object other) =>
      other is StepUse &&
      other.ingredientId == ingredientId &&
      other.quantity == quantity &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(ingredientId, quantity, unit);
}

/// Upotrebe po koracima, poravnate sa [steps]: zapis za korak se traži po
/// istom tekstu (ponovljen tekst redom). Korak bez zapisa nema veze.
List<List<StepUse>> readStepLinks(List<String> steps, Object? raw) {
  final entries = <(String, List<StepUse>)>[
    if (raw is List)
      for (final e in raw)
        if (e is Map<String, dynamic> && e['text'] is String)
          (
            e['text'] as String,
            [
              if (e['uses'] case final List<dynamic> uses)
                for (final u in uses) ?StepUse.tryParse(u),
            ],
          ),
  ];
  final used = List.filled(entries.length, false);
  return [
    for (final step in steps)
      () {
        for (var i = 0; i < entries.length; i++) {
          if (!used[i] && entries[i].$1 == step) {
            used[i] = true;
            return List<StepUse>.unmodifiable(entries[i].$2);
          }
        }
        return const <StepUse>[];
      }(),
  ];
}

/// Zapis veza; null kad nijedan korak nema veze (recept ostaje kao v1).
List<Map<String, dynamic>>? writeStepLinks(
  List<String> steps,
  List<List<StepUse>> uses,
) {
  final out = [
    for (final (i, step) in steps.indexed)
      if (i < uses.length && uses[i].isNotEmpty)
        {
          'text': step,
          'uses': [for (final u in uses[i]) u.toJson()],
        },
  ];
  return out.isEmpty ? null : out;
}

/// Upotrebe premeštene na nove korake po tekstu (izmena spiska koraka).
List<List<StepUse>> realignStepUses(
  List<String> oldSteps,
  List<List<StepUse>> oldUses,
  List<String> newSteps,
) => readStepLinks(newSteps, writeStepLinks(oldSteps, oldUses));

/// Sastojci bez id-ja dobijaju nov id; postojeći id se ne menja.
List<Ingredient> withIngredientIds(
  List<Ingredient> items,
  String Function() newId,
) => [for (final i in items) i.id == null ? i.withId(newId()) : i];

/// Novi spisak sastojaka (npr. iz AI izmene) preuzima id-jeve starog po
/// istom nazivu, redom; ostali ostaju bez id-ja.
List<Ingredient> carryIngredientIds(
  List<Ingredient> previous,
  List<Ingredient> next,
) {
  final free = [
    for (final p in previous)
      if (p.id != null) p,
  ];
  return [
    for (final n in next)
      if (n.id != null)
        n
      else
        () {
          final key = normalizeForSearch(n.name);
          final i = free.indexWhere((p) => normalizeForSearch(p.name) == key);
          if (i < 0) return n;
          return n.withId(free.removeAt(i).id!);
        }(),
  ];
}

/// Upotreba čiji sastojak više nije u receptu.
bool isUnresolved(StepUse use, List<Ingredient> ingredients) =>
    !ingredients.any((i) => i.id == use.ingredientId);

/// Sastojak čije upotrebe u koracima zajedno prelaze količinu u receptu.
class UseConflict {
  const UseConflict(this.ingredient, this.usedQuantity);

  final Ingredient ingredient;
  final double usedQuantity;
}

/// Sabira samo upotrebe sa količinom u istoj jedinici kao sastojak (ili bez
/// jedinice). Recept se ne menja; sukob se samo prijavljuje.
List<UseConflict> useConflicts(
  List<Ingredient> ingredients,
  List<List<StepUse>> uses,
) {
  String unitKey(String? u) => (u ?? '').trim().toLowerCase();
  return [
    for (final i in ingredients)
      if (i.id != null && i.quantity != null)
        if (_sum(i, uses, unitKey) case final total?
            when total > i.quantity! + 1e-9)
          UseConflict(i, total),
  ];
}

double? _sum(
  Ingredient i,
  List<List<StepUse>> uses,
  String Function(String?) unitKey,
) {
  double? total;
  for (final step in uses) {
    for (final u in step) {
      if (u.ingredientId != i.id || u.quantity == null) continue;
      if (u.unit != null && unitKey(u.unit) != unitKey(i.unit)) continue;
      total = (total ?? 0) + u.quantity!;
    }
  }
  return total;
}
