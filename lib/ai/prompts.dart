import 'dart:convert';

import '../domain/recipe.dart';
import '../domain/user_preferences.dart';

final _recipeSchema =
    '''
{
  "title": string,
  "servings": integer,
  "prepMinutes": integer | null,
  "ingredients": [
    {
      "name": string,            // osnovni naziv, npr. "crni luk", bez količine
      "quantity": number | null, // npr. 0.5; null za "po ukusu"
      "unit": string | null,     // g, kg, ml, l, kom, kašika, kašičica, šolja, prstohvat, čen, glavica
      "category": one of ${jsonEncode(ingredientCategories)},
      "note": string | null      // npr. "sitno iseckan"
    }
  ],
  "steps": [string]
}''';

final recipeSystemPrompt = '''
You are the cooking assistant inside "Tavli", a recipe and shopping list app.
Always answer with ONE JSON object and nothing else.
All human-readable text must be in Serbian (Latin script).
Use metric units. Ingredient names are lowercase base names without quantities.
Recipe JSON schema:
$_recipeSchema''';

String _dietForPrompt(FoodDiet diet) => switch (diet) {
  FoodDiet.vegetarian => 'vegetarian',
  FoodDiet.vegan => 'vegan',
  FoodDiet.glutenFree => 'gluten-free',
  FoodDiet.lactoseFree => 'lactose-free',
};

/// Blok sa preferencijama domaćinstva za AI upit. Alergije su prve i
/// zabranjene su; prazno kad nema unosa (null ili podrazumevano stanje).
String preferencesBlock(UserPreferences? preferences) {
  final p = preferences;
  if (p == null || p.isEmpty) return '';
  final lines = [
    if (p.allergies.isNotEmpty)
      'ALLERGIES: the dish must NOT contain any of these, not as an ingredient '
          'and not hidden in another ingredient: ${jsonEncode(p.allergies)}.',
    if (p.diet.isNotEmpty)
      'Diet: every dish must be ${p.diet.map(_dietForPrompt).join(', ')}.',
    if (p.dislikes.isNotEmpty)
      'Dislikes: avoid these when possible: ${jsonEncode(p.dislikes)}.',
    'Household size: ${p.servings} people (the servings requested below '
        'still set the quantities).',
  ];
  return 'Household preferences (follow them):\n'
      '${lines.map((l) => '- $l').join('\n')}\n\n';
}

String recipeFromImagePrompt({UserPreferences? preferences}) =>
    '''${preferencesBlock(preferences)}Read the recipe from this image (printed, handwritten or a screenshot) and
return it in the recipe JSON schema. Keep the original quantities; translate
to Serbian if needed. If something is unreadable, make a sensible guess and
mention it in that ingredient's "note".
If the image does not contain a recipe, return {"error": "not_a_recipe"}.''';

String recipeFromNamePrompt(
  String dishName, {
  required int servings,
  String? notes,
  UserPreferences? preferences,
}) =>
    '''${preferencesBlock(preferences)}Create a home-cooking recipe for: "$dishName".
Servings: $servings.
${notes == null || notes.isEmpty ? '' : 'Extra wishes: $notes\n'}Use ingredients that are easy to find in Serbian supermarkets.
Return it in the recipe JSON schema.''';

String refineRecipePrompt(
  Recipe current,
  String instruction, {
  UserPreferences? preferences,
}) =>
    '''${preferencesBlock(preferences)}Here is the current recipe:
${jsonEncode(current.toAiJson())}

Change it according to this request: "$instruction"
Keep everything that the request does not affect.
Return the whole updated recipe in the recipe JSON schema.''';
