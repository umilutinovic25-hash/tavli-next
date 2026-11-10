import '../domain/ids.dart';
import '../domain/recipe.dart';
import '../domain/step_links.dart';
import 'ai_models.dart';
import 'ai_router.dart';
import 'prompts.dart';

class NotARecipeException implements Exception {
  const NotARecipeException();

  @override
  String toString() => 'Na slici nije pronađen recept.';
}

/// Funkcije aplikacije koje prave i menjaju recepte preko [AIRouter]-a.
class RecipeAI {
  RecipeAI(this._router, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AIRouter _router;
  final DateTime Function() _clock;

  Future<AIResult<Recipe>> fromImage(AIImage image, {String? imagePath}) {
    return _router
        .run(
          AIRequest(
            system: recipeSystemPrompt,
            prompt: recipeFromImagePrompt(),
            images: [image],
            temperature: 0.1,
          ),
          (json) {
            if (json['error'] == 'not_a_recipe') {
              throw const NotARecipeException();
            }
            return _build(json, RecipeSource.photo, imagePath: imagePath);
          },
        )
        .then(_stampModel);
  }

  Future<AIResult<Recipe>> fromDishName(
    String dishName, {
    int servings = 2,
    String? notes,
  }) {
    return _router
        .run(
          AIRequest(
            system: recipeSystemPrompt,
            prompt: recipeFromNamePrompt(
              dishName,
              servings: servings,
              notes: notes,
            ),
            temperature: 0.7,
          ),
          (json) => _build(json, RecipeSource.ai),
        )
        .then(_stampModel);
  }

  /// Vraća novu verziju recepta; id, izvor i slika ostaju isti.
  Future<AIResult<Recipe>> refine(Recipe current, String instruction) {
    return _router
        .run(
          AIRequest(
            system: recipeSystemPrompt,
            prompt: refineRecipePrompt(current, instruction),
          ),
          (json) {
            final next = Recipe.fromAiJson(
              json,
              id: current.id,
              source: current.source,
              createdAt: current.createdAt,
              imagePath: current.imagePath,
            );
            // Isti sastojak (po nazivu) i isti tekst koraka zadržavaju veze.
            return next.copyWith(
              ingredients: carryIngredientIds(
                current.ingredients,
                next.ingredients,
              ),
              stepUses: realignStepUses(
                current.steps,
                current.stepUses,
                next.steps,
              ),
            );
          },
        )
        .then(_stampModel);
  }

  Recipe _build(
    Map<String, dynamic> json,
    RecipeSource source, {
    String? imagePath,
  }) => Recipe.fromAiJson(
    json,
    id: newId(),
    source: source,
    createdAt: _clock(),
    imagePath: imagePath,
  );

  AIResult<Recipe> _stampModel(AIResult<Recipe> r) {
    final v = r.value;
    return AIResult(
      Recipe(
        id: v.id,
        title: v.title,
        servings: v.servings,
        prepMinutes: v.prepMinutes,
        ingredients: v.ingredients,
        steps: v.steps,
        stepUses: v.stepUses,
        source: v.source,
        imagePath: v.imagePath,
        createdAt: v.createdAt,
        answeredBy: r.model.label,
      ),
      r.model,
      r.attempts,
      origin: r.origin,
    );
  }
}
