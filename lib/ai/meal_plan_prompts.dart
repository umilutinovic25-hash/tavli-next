import 'dart:convert';

import '../domain/meal_plan.dart';
import '../domain/recipe.dart';

const mealPlanSystemPrompt = '''
You are the meal-planning assistant inside "Tavli", a recipe and shopping app.
Always answer with ONE JSON object and nothing else.
All human-readable text must be in Serbian (Latin script).
Suggest varied, realistic home cooking with ingredients that are easy to find
in Serbian supermarkets. Use metric units. Ingredient names are lowercase base
names without quantities.''';

/// Raspored jedne nedelje: po jedno jelo za svako mesto.
String planOutlinePrompt({
  required List<MealSlot> slots,
  required int servings,
  required List<({String id, String title})> library,
  List<String> alreadyPlanned = const [],
  String? wishes,
  List<String> pantry = const [],
  List<String> rules = const [],
}) {
  final slotsJson = jsonEncode([
    for (final s in slots) {'date': s.date.toString(), 'meal': s.type.name},
  ]);
  final libraryJson = jsonEncode([
    for (final r in library) {'id': r.id, 'title': r.title},
  ]);
  return '''
Plan one dish for EVERY slot below, and nothing else: no extra or missing slots.
The household eats $servings servings per meal.
${rules.isEmpty ? '' : 'Day rules (follow every required rule exactly; follow preferred rules when possible):\n${rules.map((r) => '- $r').join('\n')}\n'}${wishes == null || wishes.trim().isEmpty ? '' : 'Wishes of the household: ${wishes.trim()}\n'}${pantry.isEmpty ? '' : 'Prefer using what is at home: ${jsonEncode(pantry)}\n'}${alreadyPlanned.isEmpty ? '' : 'Already planned in other weeks (avoid repeating too often): ${jsonEncode(alreadyPlanned)}\n'}You may reuse the household's own saved recipes by their "id"; never invent ids.
Library: $libraryJson
Slots: $slotsJson
Return:
{"meals": [{"date": "YYYY-MM-DD", "meal": "breakfast" | "lunch" | "dinner",
  "recipeId": string | null, // id from Library, or null for a new dish
  "title": string}]}''';
}

/// Sažeci novih recepata (naziv i sastojci, bez koraka).
String recipeSummariesPrompt(List<String> titles) =>
    '''
Write a short recipe summary for each dish below, exactly once each, with the
same title. No preparation steps.
Recipes: ${jsonEncode(titles)}
Return:
{"recipes": [{
  "title": string,
  "servings": integer,      // 1–20, servings the quantities make
  "prepMinutes": integer | null,
  "ingredients": [{
    "name": string,
    "quantity": number | null,
    "unit": string | null,  // g, kg, ml, l, kom, kašika, kašičica, šolja, prstohvat, čen, glavica
    "category": one of ${jsonEncode(ingredientCategories)},
    "note": string | null
  }]
}]}''';
