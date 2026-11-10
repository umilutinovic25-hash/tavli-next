import '../domain/meal_plan.dart';
import '../domain/plan_calendar.dart';
import '../domain/recipe.dart';
import '../domain/shopping_demand.dart' show maxServings, minServings;
import '../domain/shopping_source.dart';
import '../domain/time_budget.dart';
import '../domain/user_preferences.dart';
import 'ai_models.dart';
import 'ai_router.dart';
import 'meal_plan_prompts.dart';

/// Najviše novih recepata u jednom zahtevu.
const recipeSummaryBatch = 3;

/// Najviše recepata iz biblioteke koji se nude AI-ju u jednom rasporedu.
const maxLibraryInPrompt = 60;

/// Osoba je prekinula generisanje; sprema se između grupa.
class PlanCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Grupa nije uspela; [draft] ima sve što je gotovo pre toga.
class PlanGenerationFailed implements Exception {
  const PlanGenerationFailed(this.draft, this.error);

  final PlanDraft draft;
  final Object error;

  @override
  String toString() => 'PlanGenerationFailed: $error';
}

/// Generisanje je prekinuto; [draft] ima sve što je gotovo pre prekida.
class PlanGenerationCancelled implements Exception {
  const PlanGenerationCancelled(this.draft);

  final PlanDraft draft;
}

/// Predlaže plan obroka preko [AIRouter]-a: raspored po nedeljnim delovima,
/// pa sažeci novih recepata u malim grupama. Ništa ne čuva; nacrt ostaje
/// u sesiji dok ga osoba ne odobri.
class MealPlanAI {
  MealPlanAI(this._router, {this._preferences});

  final AIRouter _router;

  /// Preferencije domaćinstva, čitaju se jednom po predlogu plana.
  final Future<UserPreferences> Function()? _preferences;

  /// Vraća pun nacrt. Kad grupa ne uspe baca [PlanGenerationFailed], a kad
  /// je [cancel] prekinut [PlanGenerationCancelled]; oba nose gotov deo,
  /// koji se predaje kao [resume] da se traži samo ono što nedostaje.
  Future<PlanDraft> propose(
    PlanRequest request, {
    List<Recipe> library = const [],
    PlanDraft? resume,
    PlanCancellation? cancel,
    void Function(PlanDraft draft)? onProgress,
  }) async {
    if (resume != null && !identical(resume.request, request)) {
      throw ArgumentError('Nastavak pripada drugom zahtevu');
    }
    var draft = resume ?? PlanDraft(request: request);
    final prefs = await _preferences?.call() ?? UserPreferences.defaults;
    final offered = library.take(maxLibraryInPrompt).toList();
    final byId = {for (final r in offered) r.id: r};

    Future<T> step<T>(Future<T> Function() run) async {
      if (cancel?.isCancelled ?? false) throw PlanGenerationCancelled(draft);
      try {
        return await run();
      } on Object catch (e) {
        throw PlanGenerationFailed(draft, e);
      }
    }

    for (final period in weekPeriods(request.range)) {
      final missing = [
        for (final s in draft.missingSlots)
          if (period.range.contains(s.date)) s,
      ];
      if (missing.isEmpty) continue;
      final planned = {for (final p in draft.proposals.values) p.title};
      Future<Map<MealSlot, SlotProposal>> outline(
        List<MealSlot> slots, {
        List<String> tooLong = const [],
      }) async => (await step(
        () => _router.run(
          AIRequest(
            system: mealPlanSystemPrompt,
            prompt: planOutlinePrompt(
              slots: slots,
              servings: request.servings,
              library: [
                for (final r in offered)
                  (
                    id: r.id,
                    title: r.title,
                    activeMinutes: r.activeMinutes,
                    totalMinutes: r.totalMinutes,
                  ),
              ],
              alreadyPlanned: planned.toList(),
              wishes: request.wishes,
              pantry: request.usePantry ? request.pantryNames : const [],
              rules: [
                for (final r in request.rules)
                  if (slots.any(r.appliesTo)) r.promptLine,
              ],
              timeLimits: _timeLimits(slots, request.budgets),
              tooLong: tooLong,
              preferences: prefs,
            ),
            temperature: 0.8,
          ),
          (json) => parseOutline(
            json,
            slots: slots,
            library: {for (final r in offered) r.id: r.title},
          ),
        ),
      )).value;

      var proposals = await outline(missing);
      // Recept iz biblioteke čije potvrđeno vreme prekoračuje dan traži se
      // još jednom, samo za ta mesta; ako ni tada ne staje, ostaje sa
      // oznakom „Preko vremena“ u pregledu.
      final over = _overBudget(proposals, byId, request.budgets);
      if (over.isNotEmpty) {
        final retry = await outline(
          over.keys.toList(),
          tooLong: {for (final p in over.values) p.title}.toList(),
        );
        proposals = {...proposals, ...retry};
      }
      draft = draft.copyWith(
        proposals: {...draft.proposals, ...proposals},
        libraryRecipes: {
          ...draft.libraryRecipes,
          for (final id
              in proposals.values.map((p) => p.libraryRecipeId).nonNulls)
            id: RecipeSnapshot.fromRecipe(byId[id]!),
        },
      );
      onProgress?.call(draft);
    }

    final missingKeys = draft.missingRecipeKeys;
    final titles = {
      for (final p in draft.proposals.values) ?p.draftRecipeKey: p.title,
    };
    for (var i = 0; i < missingKeys.length; i += recipeSummaryBatch) {
      final batch = [
        for (final key in missingKeys.skip(i).take(recipeSummaryBatch))
          titles[key]!,
      ];
      final result = await step(
        () => _router.run(
          AIRequest(
            system: mealPlanSystemPrompt,
            prompt: recipeSummariesPrompt(batch, preferences: prefs),
          ),
          (json) => parseSummaries(json, titles: batch),
        ),
      );
      draft = draft.copyWith(
        newRecipes: {...draft.newRecipes, ...result.value},
      );
      onProgress?.call(draft);
    }
    return draft;
  }
}

/// Redovi ograničenja za dane traženih mesta (bez dana bez ograničenja).
List<String> _timeLimits(List<MealSlot> slots, List<DayBudget> budgets) {
  final dates = {for (final s in slots) s.date}.toList()
    ..sort((a, b) => a.compareTo(b));
  return [
    for (final d in dates)
      if (budgetFor(budgets, d.weekday) case final b? when !b.isEmpty)
        timeLimitLine(d.toString(), b),
  ];
}

/// Mesta gde recept iz biblioteke sigurno ne staje u vreme svog dana.
Map<MealSlot, SlotProposal> _overBudget(
  Map<MealSlot, SlotProposal> proposals,
  Map<String, Recipe> library,
  List<DayBudget> budgets,
) => {
  for (final MapEntry(key: slot, value: p) in proposals.entries)
    if (p.libraryRecipeId case final id?)
      if (library[id] case final r?)
        if (checkTime(
              budget: budgetFor(budgets, slot.date.weekday),
              activeMinutes: r.activeMinutes,
              totalMinutes: r.totalMinutes,
            )?.fit ==
            TimeFit.exceeds)
          slot: p,
};

/// Čita raspored: tačno jedan predlog za svako od [slots]. Baca
/// [FormatException] za mesto koje nedostaje, ponavlja se ili nije traženo,
/// i za id recepta koji nije u [library] (id → naziv).
Map<MealSlot, SlotProposal> parseOutline(
  Map<String, dynamic> json, {
  required List<MealSlot> slots,
  required Map<String, String> library,
}) {
  final meals = json['meals'];
  if (meals is! List) throw const FormatException('Nema rasporeda');
  final wanted = slots.toSet();
  final result = <MealSlot, SlotProposal>{};
  for (final raw in meals) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Pokvaren obrok');
    }
    final date = CivilDate.parse(raw['date'] as String? ?? '');
    final type = MealType.tryParse(raw['meal']);
    if (type == null) throw const FormatException('Nepoznata vrsta obroka');
    final slot = MealSlot(date, type);
    if (!wanted.contains(slot)) {
      throw FormatException('Mesto nije traženo', '$slot');
    }
    if (result.containsKey(slot)) {
      throw FormatException('Mesto se ponavlja', '$slot');
    }
    final id = raw['recipeId'];
    if (id != null) {
      final title = id is String ? library[id] : null;
      if (title == null) throw const FormatException('Nepoznat recept');
      result[slot] = SlotProposal(title: title, libraryRecipeId: id as String);
      continue;
    }
    final title = (raw['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) throw const FormatException('Obrok nema naziv');
    result[slot] = SlotProposal(
      title: title,
      draftRecipeKey: draftRecipeKey(title),
    );
  }
  if (result.length != wanted.length) {
    throw const FormatException('Nedostaju mesta u rasporedu');
  }
  return result;
}

/// Čita sažetke: tačno jedan recept za svaki od [titles], po
/// [draftRecipeKey]. Baca [FormatException] za višak, manjak, duplikat,
/// porcije van 1–20 i recept bez sastojaka.
Map<String, RecipeSnapshot> parseSummaries(
  Map<String, dynamic> json, {
  required List<String> titles,
}) {
  final recipes = json['recipes'];
  if (recipes is! List) throw const FormatException('Nema recepata');
  final wanted = {for (final t in titles) draftRecipeKey(t): t.trim()};
  final result = <String, RecipeSnapshot>{};
  for (final raw in recipes) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Pokvaren recept');
    }
    final key = draftRecipeKey(raw['title'] as String? ?? '');
    if (!wanted.containsKey(key)) {
      throw FormatException('Recept nije tražen', key);
    }
    if (result.containsKey(key)) {
      throw FormatException('Recept se ponavlja', key);
    }
    final servings = raw['servings'];
    if (servings is! num ||
        servings != servings.roundToDouble() ||
        servings < minServings ||
        servings > maxServings) {
      throw const FormatException('Neispravne porcije');
    }
    final ingredients = raw['ingredients'];
    if (ingredients is! List || ingredients.isEmpty) {
      throw const FormatException('Recept nema sastojke');
    }
    final prep = raw['prepMinutes'];
    result[key] = RecipeSnapshot(
      title: wanted[key]!,
      baseServings: servings.toInt(),
      prepMinutes: prep is num && prep > 0 ? prep.round() : null,
      ingredients: [
        for (final i in ingredients)
          Ingredient.fromJson(i as Map<String, dynamic>),
      ],
    );
  }
  if (result.length != wanted.length) {
    throw const FormatException('Nedostaju recepti');
  }
  return result;
}
