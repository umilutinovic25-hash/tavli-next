/// Red "Uskoro kuvam": recepti koje osoba želi uskoro da skuva, još bez
/// datuma. Stavka ne traži kupovinu; tek raspoređivanje pravi obrok u planu.
library;

import 'meal_plan.dart';
import 'shopping_demand.dart' show maxServings, minServings;
import 'shopping_source.dart';

class CookSoonItem {
  const CookSoonItem({
    required this.id,
    required this.snapshot,
    required this.servings,
    required this.position,
    required this.createdAt,
    this.recipeId,
  });

  final String id;

  /// Recept iz biblioteke; null kad je obrisan (snimak ostaje).
  final String? recipeId;
  final RecipeSnapshot snapshot;
  final int servings;
  final int position;
  final DateTime createdAt;
}

/// Porcije stavke reda: porcije recepta u granicama 1–20.
int cookSoonServings(int recipeServings) =>
    recipeServings.clamp(minServings, maxServings);

/// Nacrt koji stavku stavlja na [slot] sačuvanog plana. Ide kroz isto
/// odobrenje kao zamena jela: zastareo plan ([base]) se ne prepisuje, a
/// zaključan, skuvan ili prošao obrok se ne menja.
PlanDraft scheduleDraft({
  required CookSoonItem item,
  required MealPlan plan,
  required PlanBase base,
  required MealSlot slot,
}) {
  // Obrisan recept: id stavke nije u biblioteci, pa obrok čuva samo snimak.
  final libraryId = item.recipeId ?? 'cook-soon:${item.id}';
  return PlanDraft(
    request: PlanRequest(
      range: plan.range,
      mealTypes: plan.mealTypes,
      servings: item.servings,
      usePantry: plan.usePantry,
      only: {slot},
    ),
    proposals: {
      slot: SlotProposal(
        title: item.snapshot.title,
        libraryRecipeId: libraryId,
      ),
    },
    libraryRecipes: {libraryId: item.snapshot},
    base: base,
  );
}

/// Id-jevi reda posle premeštanja stavke [id] na mesto [index].
List<String> reorderedIds(List<CookSoonItem> items, String id, int index) {
  final ids = [for (final i in items) i.id];
  if (!ids.remove(id)) return ids;
  ids.insert(index.clamp(0, ids.length), id);
  return ids;
}
