import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/day_rules.dart';
import '../../domain/meal_plan.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_format.dart';
import '../../domain/shopping_demand.dart' show maxServings, scaleQuantity;
import '../recipes/cooking_screen.dart';
import '../recipes/recipe_view.dart';
import 'meal_actions.dart';
import 'meal_away.dart';
import 'plan_format.dart';
import 'planning_providers.dart';
import 'rule_notes.dart';
import 'time_check_note.dart';

/// Odobren recept obroka i izmene: porcije, zamena, zaključavanje,
/// skuvano i uklanjanje. Prikazuje snimak iz plana, ne recept iz biblioteke.
class MealEntryDetail extends ConsumerWidget {
  const MealEntryDetail({
    super.key,
    required this.plan,
    required this.meal,
    this.onRemoved,
  });

  final MealPlan plan;
  final PlannedMeal meal;
  final VoidCallback? onRemoved;

  List<Widget> _ruleSection(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(dayRulesProvider).value ?? const [];
    final results = evaluateSlot(rules, meal.slot, meal.snapshot);
    final failing = [
      for (final r in results)
        if (r.fit == RuleFit.fail && r.rule.mode == RuleMode.required) r,
    ];
    return [
      RuleNotes(results, overrides: meal.ruleOverrides),
      for (final r in failing)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: meal.isCooked
                ? null
                : () => runMealEdit(
                    context,
                    () => ref
                        .read(mealPlanRepositoryProvider)
                        .setRuleOverride(
                          meal.id,
                          r.rule.id,
                          allowed: !meal.ruleOverrides.contains(r.rule.id),
                        ),
                  ),
            child: Text(
              meal.ruleOverrides.contains(r.rule.id)
                  ? 'Ukloni izuzetak'
                  : 'Dozvoli ovaj put',
              semanticsLabel: meal.ruleOverrides.contains(r.rule.id)
                  ? 'Ukloni izuzetak za ${r.rule.label}'
                  : 'Dozvoli ovaj put: ${r.rule.label}',
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.read(mealPlanRepositoryProvider);
    final snapshot = meal.snapshot;
    final protected = meal.isLocked || meal.isCooked;

    Future<void> remove() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ukloniti obrok iz plana?'),
          content: const Text(
            'Njegovi sastojci izlaze iz nabavke. Kupljeno ostaje.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Otkaži'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ukloni'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      if (await runMealEdit(context, () => repo.removeMeal(meal.id))) {
        onRemoved?.call();
      }
    }

    if (meal.isAway) {
      final previous = snapshot?.title;
      return ReadableScroll(
        children: [
          Text(
            '${dayLabel(meal.slot.date)} · ${meal.slot.type.label}',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Text(meal.awayTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Obrok van kuće: mesto je zauzeto i ništa se ne dodaje u '
            'nabavku. Ponovni predlog ga ne menja.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (previous != null)
                FilledButton.tonalIcon(
                  onPressed: protected
                      ? null
                      : () => runMealEdit(
                          context,
                          () => repo.restoreMeal(meal.id),
                          done: 'Vraćeno: „$previous“.',
                        ),
                  icon: const Icon(Icons.undo),
                  label: Text('Vrati „$previous“'),
                ),
              OutlinedButton.icon(
                onPressed: protected
                    ? null
                    : () => chooseAway(
                        context,
                        ref,
                        plan: plan,
                        slot: meal.slot,
                        current: meal,
                      ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Promeni razlog'),
              ),
              OutlinedButton.icon(
                onPressed: protected
                    ? null
                    : () => replaceMeal(context, ref, plan, meal),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Zameni jelom'),
              ),
              TextButton.icon(
                onPressed: protected ? null : remove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Ukloni iz plana'),
              ),
            ],
          ),
        ],
      );
    }

    return ReadableScroll(
      children: [
        Text(
          '${dayLabel(meal.slot.date)} · ${meal.slot.type.label}',
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Text(
          snapshot?.title ?? 'Recept nije dostupan',
          style: theme.textTheme.headlineSmall,
        ),
        TimeCheckNote(
          mealTimeCheck(
            snapshot,
            meal.slot.date,
            ref.watch(dayBudgetsProvider).value ?? const [],
          ),
          detailed: true,
        ),
        ..._ruleSection(context, ref),
        if (meal.isLocked || meal.isCooked) ...[
          const SizedBox(height: 4),
          Text(
            [
              if (meal.isLocked) 'Zaključano',
              if (meal.isCooked) 'Skuvano',
            ].join(' · '),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (snapshot != null) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => CookingScreen(
                        snapshot: snapshot,
                        servings: meal.servings,
                      ),
                    ),
                  ),
              icon: const Icon(Icons.soup_kitchen_outlined),
              label: const Text('Kreni sa kuvanjem'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            const Expanded(child: Text('Broj porcija')),
            IconButton(
              tooltip: 'Manje porcija',
              onPressed: meal.isCooked || meal.servings <= 1
                  ? null
                  : () => runMealEdit(
                      context,
                      () => repo.changeServings(meal.id, meal.servings - 1),
                    ),
              icon: const Icon(Icons.remove),
            ),
            Text('${meal.servings}', style: theme.textTheme.titleMedium),
            IconButton(
              tooltip: 'Više porcija',
              onPressed: meal.isCooked || meal.servings >= maxServings
                  ? null
                  : () => runMealEdit(
                      context,
                      () => repo.changeServings(meal.id, meal.servings + 1),
                    ),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: protected
                  ? null
                  : () => replaceMeal(context, ref, plan, meal),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Zameni jelo'),
            ),
            OutlinedButton.icon(
              onPressed: protected
                  ? null
                  : () => chooseAway(
                      context,
                      ref,
                      plan: plan,
                      slot: meal.slot,
                      current: meal,
                    ),
              icon: const Icon(Icons.restaurant_outlined),
              label: const Text('Obrok van kuće'),
            ),
            OutlinedButton.icon(
              onPressed: meal.isCooked
                  ? null
                  : () => runMealEdit(
                      context,
                      () => repo.setLocked(meal.id, locked: !meal.isLocked),
                    ),
              icon: Icon(meal.isLocked ? Icons.lock_open : Icons.lock_outline),
              label: Text(meal.isLocked ? 'Otključaj' : 'Zaključaj'),
            ),
            OutlinedButton.icon(
              onPressed: () => runMealEdit(
                context,
                () => repo.setCooked(meal.id, cooked: !meal.isCooked),
              ),
              icon: Icon(
                meal.isCooked ? Icons.undo : Icons.check_circle_outline,
              ),
              label: Text(
                meal.isCooked ? 'Nije skuvano' : 'Označi kao skuvano',
              ),
            ),
            TextButton.icon(
              onPressed: protected ? null : remove,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Ukloni iz plana'),
            ),
          ],
        ),
        if (protected) ...[
          const SizedBox(height: 4),
          Text(
            meal.isCooked
                ? 'Skuvan obrok se ne menja.'
                : 'Za zamenu ili uklanjanje prvo otključaj obrok.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (snapshot != null) ...[
          const SizedBox(height: 16),
          Text(
            'Sastojci za ${servingsLabel(meal.servings)}'
            '${snapshot.prepMinutes == null ? '' : ' · ${snapshot.prepMinutes} min'}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          for (final i in snapshot.ingredients)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '• ${ingredientLine(i.quantity == null ? i : Ingredient(
                        name: i.name,
                        quantity: scaleQuantity(i.quantity, baseServings: snapshot.baseServings, servings: meal.servings),
                        unit: i.unit,
                        category: i.category,
                        note: i.note,
                      ))}',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          if (snapshot.steps.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Priprema', style: theme.textTheme.titleMedium),
            for (final (n, step) in snapshot.steps.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${n + 1}. $step',
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
              ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Ovaj recept u planu nema korake pripreme.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ],
    );
  }
}
