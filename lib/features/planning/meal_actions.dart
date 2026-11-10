import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/meal_plan_ai.dart';
import '../../data/meal_plan_repository.dart';
import '../../domain/day_rules.dart';
import '../../domain/meal_plan.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_format.dart';
import '../../domain/shopping_source.dart';
import '../../providers.dart';
import '../recipes/recipe_providers.dart';
import '../settings/ai_error_text.dart';
import 'planning_providers.dart';

void _say(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Poruka za grešku izmene obroka.
String mealErrorText(Object e) => switch (e) {
  StaleDraftException() =>
    'Plan je u međuvremenu promenjen. Pogledaj ga i pokušaj ponovo.',
  ProtectedMealException() => 'Obrok je zaključan ili skuvan.',
  MealNotFoundException() => 'Obrok više nije u planu.',
  RuleViolationException() =>
    'Jelo krši obavezno pravilo dana. Izaberi drugo ili dozvoli izuzetak.',
  PlanGenerationFailed(:final error) => aiErrorText(error),
  _ => 'Izmena nije sačuvana. Pokušaj ponovo.',
};

/// Izvršava izmenu obroka; grešku prikazuje kao poruku.
Future<bool> runMealEdit(
  BuildContext context,
  Future<void> Function() edit, {
  String? done,
}) async {
  try {
    await edit();
    if (done != null && context.mounted) _say(context, done);
    return true;
  } on Exception catch (e) {
    if (context.mounted) _say(context, mealErrorText(e));
    return false;
  }
}

/// Odakle dolazi zamena jednog jela.
enum ReplacementSource { ai, library }

/// Pita da li AI predlaže drugo jelo ili osoba bira svoj recept.
Future<ReplacementSource?> pickReplacementSource(BuildContext context) =>
    showModalBottomSheet<ReplacementSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Predloži drugo'),
              subtitle: const Text('AI predlaže novo jelo za ovaj obrok'),
              onTap: () => Navigator.pop(context, ReplacementSource.ai),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Iz mojih recepata'),
              onTap: () => Navigator.pop(context, ReplacementSource.library),
            ),
          ],
        ),
      ),
    );

/// Izbor recepta iz biblioteke; null kad osoba odustane ili nema recepata.
Future<Recipe?> pickLibraryRecipe(BuildContext context, WidgetRef ref) async {
  final recipes = await ref.read(recipeRepositoryProvider).getAll();
  if (!context.mounted) return null;
  if (recipes.isEmpty) {
    _say(context, 'Još nemaš sačuvanih recepata.');
    return null;
  }
  return showModalBottomSheet<Recipe>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Izaberi recept')),
            for (final r in recipes)
              ListTile(
                title: Text(r.title),
                subtitle: Text(servingsLabel(r.servings)),
                onTap: () => Navigator.pop(context, r),
              ),
          ],
        ),
      ),
    ),
  );
}

/// "Zameni jelo": AI predlog ili recept iz biblioteke, uvek uz pregled
/// pre prihvatanja. Ako se plan u međuvremenu promeni, zamena se odbija.
Future<void> replaceMeal(
  BuildContext context,
  WidgetRef ref,
  MealPlan plan,
  PlannedMeal meal,
) async {
  final choice = await pickReplacementSource(context);
  if (choice == null || !context.mounted) return;
  final repo = ref.read(mealPlanRepositoryProvider);
  final base = PlanBase(
    planId: plan.id,
    fingerprint: await repo.fingerprint(plan.id),
  );
  final request = PlanRequest(
    range: plan.range,
    mealTypes: plan.mealTypes,
    servings: meal.servings,
    usePantry: plan.usePantry,
    wishes: meal.snapshot == null
        ? null
        : 'Nešto drugačije od: ${meal.snapshot!.title}',
    only: {meal.slot},
  );
  if (!context.mounted) return;
  final draft = choice == ReplacementSource.ai
      ? await _proposeOne(context, ref, request, base)
      : await _pickFromLibrary(context, ref, request, base);
  if (draft == null || !context.mounted) return;
  final next = draft.snapshotFor(meal.slot);
  if (next == null) return;
  final violations = blockingViolations(
    evaluateSlot(
      await ref.read(dayRuleRepositoryProvider).getAll(),
      meal.slot,
      next,
    ),
    const {},
  );
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Pregled izmena'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${meal.snapshot?.title ?? 'Obrok'} → ${next.title}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Sastojci za ${servingsLabel(next.baseServings)}:'),
            for (final i in next.ingredients) Text('• ${ingredientLine(i)}'),
            const SizedBox(height: 8),
            Text('Obrok zadržava ${servingsLabel(meal.servings)}.'),
            for (final v in violations) ...[
              const SizedBox(height: 8),
              Text(
                '${ruleResultText(v)}. Prihvatanjem dozvoljavaš izuzetak '
                'samo za ovaj obrok.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Otkaži'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Prihvati'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await runMealEdit(
    context,
    () => repo.approve(
      draft,
      overrides: {
        if (violations.isNotEmpty)
          meal.slot: {for (final v in violations) v.rule.id},
      },
    ),
    done: 'Jelo je zamenjeno.',
  );
}

Future<PlanDraft?> _proposeOne(
  BuildContext context,
  WidgetRef ref,
  PlanRequest request,
  PlanBase base,
) async {
  final cancel = PlanCancellation();
  final library = await ref.read(recipeRepositoryProvider).getAll();
  if (!context.mounted) return null;
  final work = ref
      .read(mealPlanAIProvider)
      .propose(
        request,
        library: library,
        resume: PlanDraft(request: request, base: base),
        cancel: cancel,
      );
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) {
        unawaited(
          work.whenComplete(() {
            if (dialog.mounted) Navigator.pop(dialog);
          }),
        );
        return AlertDialog(
          content: const Row(
            children: [
              SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(width: 16),
              Expanded(child: Text('Tražim drugo jelo…')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancel.cancel();
                Navigator.pop(dialog);
              },
              child: const Text('Prekini'),
            ),
          ],
        );
      },
    ),
  );
  try {
    final draft = await work;
    return cancel.isCancelled ? null : draft;
  } on PlanGenerationCancelled {
    return null;
  } on PlanGenerationFailed catch (e) {
    if (!cancel.isCancelled && context.mounted) _say(context, mealErrorText(e));
    return null;
  }
}

Future<PlanDraft?> _pickFromLibrary(
  BuildContext context,
  WidgetRef ref,
  PlanRequest request,
  PlanBase base,
) async {
  final picked = await pickLibraryRecipe(context, ref);
  if (picked == null) return null;
  final slot = request.slots.single;
  return PlanDraft(
    request: request,
    proposals: {
      slot: SlotProposal(title: picked.title, libraryRecipeId: picked.id),
    },
    libraryRecipes: {picked.id: RecipeSnapshot.fromRecipe(picked)},
    base: base,
  );
}
