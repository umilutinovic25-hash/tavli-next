import '../domain/allergy.dart';
import '../domain/food.dart' show FoodCatalog;
import '../domain/ids.dart';
import '../domain/recipe.dart';
import '../domain/step_links.dart';
import '../domain/user_preferences.dart';
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
  RecipeAI(
    this._router, {
    DateTime Function()? clock,
    this._preferences,
    this._allergyContext,
  }) : _clock = clock ?? DateTime.now;

  final AIRouter _router;
  final DateTime Function() _clock;

  /// Preferencije domaćinstva za svaki upit; bez njih nema bloka.
  final Future<UserPreferences> Function()? _preferences;

  /// Katalog i unija alergija za zaštitnu proveru (039); bez njih nema
  /// provere (demo i stari testovi).
  final Future<AllergyContext> Function()? _allergyContext;

  Future<UserPreferences> _loadPreferences() =>
      _preferences?.call() ?? Future.value(UserPreferences.defaults);

  Future<AllergyContext> _loadAllergies() =>
      _allergyContext?.call() ??
      Future.value((
        catalog: FoodCatalog.empty,
        allergies: HouseholdAllergies.none,
      ));

  /// Pita AI; ako recept ima alergen kog nije bilo u [baseline], pita još
  /// jednom uz spisak pogodaka. Ako ni drugi odgovor nije čist, baca
  /// [AllergenViolation]. Ponovni zahtev nije [FormatException]: taj bi
  /// ponovio isti upit i menjao model.
  Future<AIResult<Recipe>> _guarded(
    AllergyContext ctx,
    Future<AIResult<Recipe>> Function(List<AllergyHit> avoid) ask, {
    Recipe? baseline,
  }) async {
    final allowed = baseline == null
        ? const <String>{}
        : checkAllergens(
            baseline.ingredients,
            ctx.catalog,
            ctx.allergies,
          ).allergens.toSet();
    List<AllergyHit> newHits(Recipe r) => [
      for (final h in checkAllergens(
        r.ingredients,
        ctx.catalog,
        ctx.allergies,
      ).hits)
        if (!allowed.contains(h.allergen)) h,
    ];

    final first = await ask(const []);
    final hits = newHits(first.value);
    if (hits.isEmpty) return first;
    final second = await ask(hits);
    final again = newHits(second.value);
    if (again.isEmpty) return second;
    throw AllergenViolation({for (final h in again) h.allergen}.toList());
  }

  Future<AIResult<Recipe>> fromImage(AIImage image, {String? imagePath}) async {
    final prefs = await _loadPreferences();
    // Recept sa slike se ne odbija (osoba uvozi baš taj recept); upozorenje
    // o alergenima je u pregledu.
    final ctx = await _loadAllergies();
    return _router
        .run(
          AIRequest(
            system: recipeSystemPrompt,
            prompt: recipeFromImagePrompt(
              preferences: prefs,
              allergies: ctx.allergies.promptTerms,
            ),
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
  }) async {
    final prefs = await _loadPreferences();
    final ctx = await _loadAllergies();
    return _guarded(
      ctx,
      (avoid) => _router
          .run(
            AIRequest(
              system: recipeSystemPrompt,
              prompt: recipeFromNamePrompt(
                dishName,
                servings: servings,
                notes: notes,
                preferences: prefs,
                allergies: ctx.allergies.promptTerms,
                avoid: avoid,
              ),
              temperature: 0.7,
            ),
            (json) => _build(json, RecipeSource.ai),
          )
          .then(_stampModel),
    );
  }

  /// Vraća novu verziju recepta; id, izvor i slika ostaju isti.
  /// Odbija se samo nov alergen: onaj koji je već bio u [current] (npr.
  /// recept sa slike) ne sprečava izmenu.
  Future<AIResult<Recipe>> refine(Recipe current, String instruction) async {
    final prefs = await _loadPreferences();
    final ctx = await _loadAllergies();
    return _guarded(
      ctx,
      baseline: current,
      (avoid) => _refineOnce(current, instruction, prefs, ctx, avoid),
    );
  }

  Future<AIResult<Recipe>> _refineOnce(
    Recipe current,
    String instruction,
    UserPreferences prefs,
    AllergyContext ctx,
    List<AllergyHit> avoid,
  ) {
    return _router
        .run(
          AIRequest(
            system: recipeSystemPrompt,
            prompt: refineRecipePrompt(
              current,
              instruction,
              preferences: prefs,
              allergies: ctx.allergies.promptTerms,
              avoid: avoid,
            ),
          ),
          // Potvrđeno vreme ostaje; AI ga ne menja.
          (json) {
            final next = Recipe.fromAiJson(
              json,
              id: current.id,
              source: current.source,
              createdAt: current.createdAt,
              imagePath: current.imagePath,
              sourceUrl: current.sourceUrl,
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
              activeMinutes: current.activeMinutes,
              totalMinutes: current.totalMinutes,
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
        activeMinutes: v.activeMinutes,
        totalMinutes: v.totalMinutes,
        source: v.source,
        imagePath: v.imagePath,
        sourceUrl: v.sourceUrl,
        createdAt: v.createdAt,
        answeredBy: r.model.label,
      ),
      r.model,
      r.attempts,
      origin: r.origin,
    );
  }
}
