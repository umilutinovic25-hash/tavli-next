import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/animations/empty_basket.dart';
import '../../app/placeholder_screen.dart';
import '../../app/section_heading.dart';
import '../../app/tab_app_bar.dart';
import '../../data/database.dart';
import '../../data/shopping_repository.dart';
import '../../domain/meal_plan.dart';
import '../../domain/plan_calendar.dart';
import '../../domain/recipe_format.dart';
import '../../domain/shopping_demand.dart';
import '../../providers.dart';
import '../planning/plan_format.dart';
import '../planning/planning_providers.dart';
import '../recipes/recipe_providers.dart';
import 'shopping_list_view.dart';
import 'shopping_providers.dart';

/// Tab Nabavka: po planu (nedelja ili ceo plan) ili po receptu (bez plana).
class ShoppingScreen extends ConsumerWidget {
  const ShoppingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(shoppingViewProvider);
    final plans = ref.watch(mealPlansProvider).value;
    final recipeItems = ref.watch(recipeShoppingProvider).value;
    if (plans != null &&
        plans.isEmpty &&
        recipeItems != null &&
        recipeItems.isEmpty) {
      return EmptyStateScreen(
        art: const EmptyBasket(),
        title: 'Nabavka je prazna',
        body: 'Dodaj sastojke iz plana obroka ili iz pojedinačnog recepta.',
        action: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => context.go('/recipes'),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Pogledaj recepte'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go('/plan/new'),
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Napravi plan'),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: const TabAppBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SegmentedButton<ShoppingMode>(
                    segments: const [
                      ButtonSegment(
                        value: ShoppingMode.plan,
                        icon: Icon(Icons.calendar_month_outlined),
                        label: Text('Po planu'),
                      ),
                      ButtonSegment(
                        value: ShoppingMode.recipe,
                        icon: Icon(Icons.menu_book_outlined),
                        label: Text('Po receptu'),
                      ),
                    ],
                    selected: {view.mode},
                    onSelectionChanged: (s) => ref
                        .read(shoppingViewProvider.notifier)
                        .setMode(s.single),
                  ),
                ),
                Expanded(
                  child: switch (view.mode) {
                    ShoppingMode.plan => const _PlanShopping(),
                    ShoppingMode.recipe => const _RecipeShopping(),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanShopping extends ConsumerWidget {
  const _PlanShopping();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(mealPlansProvider);
    return plans.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) =>
          const Center(child: Text('Nabavka trenutno ne može da se prikaže.')),
      data: (list) {
        final plan = selectedPlan(
          list,
          ref.watch(planViewProvider),
          ref.watch(clockProvider)(),
        );
        if (plan == null) return const _NoPlan();
        return _PlanPeriod(plans: list, plan: plan);
      },
    );
  }
}

class _NoPlan extends ConsumerWidget {
  const _NoPlan();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          Icons.calendar_month_outlined,
          size: 56,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Još nemaš plan',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Nabavka po planu se pravi iz sačuvanog plana. Za jedan recept '
          'izaberi „Po receptu“.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Center(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => context.go('/plan/new'),
                icon: const Icon(Icons.add),
                label: const Text('Napravi plan'),
              ),
              OutlinedButton(
                onPressed: () => ref
                    .read(shoppingViewProvider.notifier)
                    .setMode(ShoppingMode.recipe),
                child: const Text('Po receptu'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanPeriod extends ConsumerWidget {
  const _PlanPeriod({required this.plans, required this.plan});

  final List<MealPlan> plans;
  final MealPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final view = ref.watch(shoppingViewProvider);
    final controller = ref.read(shoppingViewProvider.notifier);
    final today = CivilDate.today(ref.watch(clockProvider));
    final periods = weekPeriods(plan.range);
    final week = selectedWeek(periods, view, today);
    final shopping = ref.watch(planShoppingProvider(plan.id));
    final all = shopping.value ?? const <PlanShoppingItem>[];

    final header = <Widget>[
      const SectionHeading(
        title: 'Nabavka',
        subtitle: 'Od plana do pune korpe.',
      ),
      const SizedBox(height: 24),
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
            if (id != null) ref.read(planViewProvider.notifier).selectPlan(id);
          },
        ),
        const SizedBox(height: 12),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in periods)
            ChoiceChip(
              label: Text('Nedelja ${p.number}'),
              selected: !view.wholePlan && p == week,
              onSelected: (_) => controller.selectWeek(p.range.start),
            ),
          if (periods.length > 1)
            ChoiceChip(
              label: const Text('Ceo plan'),
              selected: view.wholePlan,
              onSelected: (_) => controller.selectWholePlan(),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        view.wholePlan && periods.length > 1
            ? '${rangeLabel(plan.range)} · zbir svih nedelja'
            : rangeLabel(week.range),
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
    ];

    if (shopping.isLoading && !shopping.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (view.wholePlan && periods.length > 1) {
      return _WholePlan(header: header, items: [for (final i in all) i.item]);
    }
    return ShoppingItemsList(
      header: header,
      items: [
        for (final i in all)
          if (i.weekStart == week.range.start) i.item,
      ],
      listId: () =>
          ref.read(shoppingRepositoryProvider).weekList(plan.id, week),
      emptyText: 'Za ovu nedelju nema šta da se kupi.',
    );
  }
}

/// Ceo plan: zbir nedelja po namirnici. Štikliranje beleži kupovinu u
/// nedeljnim stavkama, pa nedelje i ceo plan pokazuju istu kupovinu.
class _WholePlan extends ConsumerWidget {
  const _WholePlan({required this.header, required this.items});

  final List<Widget> header;
  final List<ShoppingItemRow> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final received = ref.watch(receivedItemsProvider).value ?? const {};
    final byId = {for (final i in items) i.id: i};
    final totals = ShoppingRepository.totalsOf(items);
    final open = [
      for (final t in totals)
        if (t.openMicros > 0 || t.hasUnknown) t,
    ];
    final done = [
      for (final t in totals)
        if (t.openMicros == 0 && !t.hasUnknown) t,
    ];
    List<String> ids(PlanTotal t, {required bool bought}) => [
      for (final id in t.itemIds)
        if (byId[id] case final i? when i.isBought == bought) id,
    ];

    String? amount(int micros, PlanTotal t) {
      if (micros == 0) return null;
      final a = displayAmount(micros, t.baseUnit);
      return amountLabel(a.quantity, a.unit);
    }

    Widget tile(PlanTotal t, {required bool bought}) {
      final isReceived =
          bought && ids(t, bought: true).every(received.contains);
      final subtitle = [
        if (!bought) amount(t.openMicros, t) ?? 'Proveri količinu',
        if (amount(t.boughtMicros, t) case final b?) 'kupljeno $b',
        if (isReceived) 'U ostavi',
      ].join(' · ');
      void toggle() => unawaited(
        setBought(
          context,
          ref,
          ids(t, bought: bought),
          t.name,
          bought: !bought,
        ),
      );
      return ListTile(
        contentPadding: EdgeInsets.zero,
        minTileHeight: 56,
        leading: Checkbox(
          value: bought,
          onChanged: isReceived ? null : (_) => toggle(),
        ),
        title: Text(
          t.name,
          style: bought
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : null,
        ),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        onTap: isReceived ? null : toggle,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        ...header,
        if (open.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              done.isEmpty
                  ? 'Za ovaj plan nema šta da se kupi.'
                  : 'Sve je kupljeno.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final (category, list) in byCategory(open, (t) => t.category)) ...[
          CategoryHeader(categoryLabel(category)),
          for (final t in list) tile(t, bought: false),
        ],
        if (done.isNotEmpty) ...[
          const Divider(height: 32),
          Text('Kupljeno · ${done.length}', style: theme.textTheme.titleMedium),
          for (final t in done) tile(t, bought: true),
        ],
      ],
    );
  }
}

class _RecipeShopping extends ConsumerWidget {
  const _RecipeShopping();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(recipeShoppingProvider);
    if (items.isLoading && !items.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final preparations = ref.watch(preparationsProvider).value ?? const [];
    return ShoppingItemsList(
      header: [
        const SectionHeading(
          title: 'Nabavka',
          subtitle: 'Od plana do pune korpe.',
        ),
        const SizedBox(height: 24),
        if (preparations.isNotEmpty) ...[
          Text(
            'Recepti u nabavci',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final p in preparations) _PreparationTile(p),
          const SizedBox(height: 12),
        ],
      ],
      items: items.value ?? const [],
      listId: () => ref.read(shoppingRepositoryProvider).recipeList(),
      emptyText:
          'Otvori recept i izaberi „Proveri sastojke“ da dodaš ono što '
          'nemaš.',
    );
  }
}

class _PreparationTile extends ConsumerWidget {
  const _PreparationTile(this.preparation);

  final RecipePreparation preparation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = preparation;
    final n = p.snapshot.ingredients.length;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.menu_book_outlined),
      title: Text(p.snapshot.title),
      subtitle: Text(
        '${servingsLabel(p.servings)} · ${ingredientsCount(n)} za kupovinu',
      ),
      trailing: IconButton(
        tooltip: 'Ukloni iz nabavke',
        icon: const Icon(Icons.remove_shopping_cart_outlined),
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          await ref.read(shoppingRepositoryProvider).removeSource(p.id);
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  'Uklonjeno iz nabavke: ${p.snapshot.title}. Kupljeno ostaje.',
                ),
              ),
            );
        },
      ),
    );
  }
}

/// "1 sastojak", "2 sastojka", "5 sastojaka" (11–14 su "sastojaka").
String ingredientsCount(int n) {
  final lastTwo = n % 100;
  final last = n % 10;
  if (last == 1 && lastTwo != 11) return '$n sastojak';
  if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
    return '$n sastojka';
  }
  return '$n sastojaka';
}
