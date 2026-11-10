import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/placeholder_screen.dart';
import '../../app/section_heading.dart';
import '../../app/tab_app_bar.dart';
import '../../domain/meal_plan.dart';
import '../../domain/plan_calendar.dart';
import '../../domain/recipe_format.dart';
import '../recipes/recipe_providers.dart';
import 'meal_entry_card.dart';
import 'meal_entry_detail.dart';
import 'plan_calendar.dart';
import 'plan_format.dart';
import 'plan_generation.dart';
import 'planning_providers.dart';

/// Širina od koje Plan prikazuje kalendar i recept jedan pored drugog.
const planWideWidth = 1000.0;

/// Tab Plan. Bez plana je glavna akcija "Napravi plan"; sa planom prikazuje
/// izabranu nedelju ili mesec, a glavna akcija je "Otvori nabavku".
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(mealPlansProvider);
    return plans.when(
      loading: () => const Scaffold(
        appBar: TabAppBar(),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const EmptyStateScreen(
        art: Icon(Icons.error_outline, size: 56),
        title: 'Plan trenutno ne može da se prikaže',
      ),
      data: (list) {
        final view = ref.watch(planViewProvider);
        final plan = selectedPlan(list, view, ref.watch(clockProvider)());
        if (plan == null) {
          return EmptyStateScreen(
            art: Icon(
              Icons.calendar_month_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: 'Još nemaš plan',
            body:
                'Izaberi nedelju ili mesec i obroke; predlog pregledaš '
                'pre čuvanja.',
            action: FilledButton.icon(
              onPressed: () => context.go('/plan/new'),
              icon: const Icon(Icons.add),
              label: const Text('Napravi plan'),
            ),
          );
        }
        return _PlanView(plans: list, plan: plan);
      },
    );
  }
}

class _PlanView extends ConsumerWidget {
  const _PlanView({required this.plans, required this.plan});

  final List<MealPlan> plans;
  final MealPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final view = ref.watch(planViewProvider);
    final controller = ref.read(planViewProvider.notifier);
    final today = CivilDate.today(ref.watch(clockProvider));
    final selected = selectedDate(plan, view, today);
    final meals = ref.watch(plannedMealsProvider(plan.id)).value ?? const [];
    final bySlot = {for (final m in meals) m.slot: m};
    final wide = MediaQuery.sizeOf(context).width >= planWideWidth;
    final week = weekOf(selected);
    final days = [
      for (final d in plan.range.days)
        if (week.contains(d)) d,
    ];
    PlannedMeal? openMeal;
    for (final m in meals) {
      if (m.id == view.entryId) openMeal = m;
    }

    void open(PlannedMeal meal) {
      if (wide) {
        controller.selectEntry(meal.id);
      } else {
        unawaited(context.push('/plan/${plan.id}/entries/${meal.id}'));
      }
    }

    Future<void> regenerate() async {
      final router = GoRouter.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final started = await ref
          .read(planGenerationProvider.notifier)
          .regenerate(plan, meals);
      if (started) {
        router.go('/plan/new/preview');
      } else {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Nema obroka za novi predlog: ostali su zaključani, skuvani '
                'ili prošli.',
              ),
            ),
          );
      }
    }

    final list = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (MediaQuery.textScalerOf(context).scale(16) <= 20) ...[
          const SectionHeading(
            eyebrow: 'Plan obroka',
            title: 'Tvoja nedelja, lakše.',
            subtitle: 'Sve za sledeći obrok, na jednom mestu.',
          ),
          const SizedBox(height: 24),
        ],
        if (plans.length > 1) ...[
          DropdownButtonFormField<String>(
            initialValue: plan.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Izaberi plan',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final p in plans)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    rangeLabel(p.range),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) {
              if (id != null) controller.selectPlan(id);
            },
          ),
          const SizedBox(height: 12),
        ],
        Text(rangeLabel(plan.range), style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '${mealsCount(meals.length)} · '
          '${servingsLabel(plan.defaultServings)} po obroku',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => context.go('/shopping'),
          icon: const Icon(Icons.shopping_basket_outlined),
          label: const Text('Otvori nabavku'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<PlanViewMode>(
              segments: const [
                ButtonSegment(value: PlanViewMode.week, label: Text('Nedelja')),
                ButtonSegment(value: PlanViewMode.month, label: Text('Mesec')),
              ],
              selected: {view.mode},
              onSelectionChanged: (s) => controller.setMode(s.single),
            ),
            TextButton.icon(
              onPressed: plan.range.contains(today)
                  ? () => controller.selectDate(today)
                  : null,
              icon: const Icon(Icons.today),
              label: const Text('Danas'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (view.mode == PlanViewMode.month)
          PlanMonthCalendar(
            plan: plan,
            meals: meals,
            selected: selected,
            today: today,
            onSelect: controller.selectDate,
          )
        else
          Row(
            children: [
              IconButton(
                tooltip: 'Prethodna nedelja',
                onPressed: days.first == plan.range.start
                    ? null
                    : () => controller.selectDate(days.first.addDays(-1)),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  rangeLabel(DateRange(days.first, days.last)),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Sledeća nedelja',
                onPressed: days.last == plan.range.end
                    ? null
                    : () => controller.selectDate(days.last.addDays(1)),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        for (final day in days) ...[
          const SizedBox(height: 20),
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                day == today ? '${dayLabel(day)} · danas' : dayLabel(day),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: day == selected ? theme.colorScheme.primary : null,
                ),
              ),
            ),
          ),
          for (final slot in plan.slots.where((s) => s.date == day))
            MealEntryCard(
              slot: slot,
              meal: bySlot[slot],
              selected: wide && bySlot[slot]?.id == view.entryId,
              onTap: () => open(bySlot[slot]!),
            ),
        ],
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: regenerate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Ponovo predloži'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go('/plan/new'),
              icon: const Icon(Icons.add),
              label: const Text('Napravi novi plan'),
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      appBar: const TabAppBar(),
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 440, child: list),
                const VerticalDivider(width: 1),
                Expanded(
                  child: openMeal == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.restaurant_outlined,
                                  size: 64,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'Izaberi obrok',
                                  style: theme.textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Izaberi obrok da vidiš recept.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : MealEntryDetail(
                          key: ValueKey(openMeal.id),
                          plan: plan,
                          meal: openMeal,
                          onRemoved: () => controller.selectEntry(null),
                        ),
                ),
              ],
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: list,
              ),
            ),
    );
  }
}

/// Obrok na telefonu, na svojoj adresi (`/plan/:planId/entries/:entryId`).
class MealEntryScreen extends ConsumerWidget {
  const MealEntryScreen({
    super.key,
    required this.planId,
    required this.entryId,
  });

  final String planId;
  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(mealPlanProvider(planId)).value;
    final meals = ref.watch(plannedMealsProvider(planId));
    PlannedMeal? meal;
    for (final m in meals.value ?? const <PlannedMeal>[]) {
      if (m.id == entryId) meal = m;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Obrok')),
      body: plan == null || meal == null
          ? Center(
              child: meals.isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Obrok nije pronađen.'),
            )
          : MealEntryDetail(
              plan: plan,
              meal: meal,
              onRemoved: () => context.go('/plan'),
            ),
    );
  }
}
