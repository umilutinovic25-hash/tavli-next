import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tavli_ui/tavli_ui.dart';

import '../../app/animations/empty_basket.dart';
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
import 'shopping_counts.dart';
import 'shopping_frame.dart';
import 'shopping_list_view.dart';
import 'shopping_providers.dart';
import 'store_price_summary.dart';

/// Tab Nabavka: po planu (nedelja ili ceo plan) ili po receptu (bez plana).
class ShoppingScreen extends ConsumerStatefulWidget {
  const ShoppingScreen({super.key});

  @override
  ConsumerState<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends ConsumerState<ShoppingScreen> {
  @override
  Widget build(BuildContext context) {
    final view = ref.watch(shoppingViewProvider);
    final plansAsync = ref.watch(mealPlansProvider);
    final recipeAsync = ref.watch(recipeShoppingProvider);
    final plans = plansAsync.value;
    final recipeItems = recipeAsync.value;
    if (view.mode == null) {
      final failed = plansAsync.hasError || recipeAsync.hasError;
      if (!failed &&
          !plansAsync.isLoading &&
          !recipeAsync.isLoading &&
          plans != null &&
          recipeItems != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final currentPlans = ref.read(mealPlansProvider);
          final currentItems = ref.read(recipeShoppingProvider);
          if (currentPlans.hasError ||
              currentItems.hasError ||
              currentPlans.isLoading ||
              currentItems.isLoading ||
              !currentPlans.hasValue ||
              !currentItems.hasValue) {
            return;
          }
          ref
              .read(shoppingViewProvider.notifier)
              .initializeMode(
                hasPlan: currentPlans.requireValue.isNotEmpty,
                hasRecipeItems: currentItems.requireValue.isNotEmpty,
              );
        });
      }
      return Scaffold(
        appBar: const TabAppBar(),
        body: SafeArea(
          child: failed
              ? _ShoppingLoadError(
                  onRetry: () {
                    ref.invalidate(mealPlansProvider);
                    ref.invalidate(recipeShoppingProvider);
                  },
                )
              : const TavliLoading(),
        ),
      );
    }
    if (!plansAsync.hasError &&
        !recipeAsync.hasError &&
        !plansAsync.isLoading &&
        !recipeAsync.isLoading &&
        plans != null &&
        plans.isEmpty &&
        recipeItems != null &&
        recipeItems.isEmpty) {
      return Scaffold(
        appBar: const TabAppBar(),
        body: SafeArea(
          child: _ScrollableState(
            child: TavliEmptyState(
              art: const EmptyBasket(),
              title: 'Nabavka je prazna',
              message:
                  'Dodaj sastojke iz plana obroka ili iz pojedinačnog recepta.',
              // Dugmad u redu kada staju, inače jedno ispod drugog; obe
              // vrste su iste visine.
              action: OverflowBar(
                alignment: MainAxisAlignment.center,
                overflowAlignment: OverflowBarAlignment.center,
                spacing: TavliSpacing.small,
                overflowSpacing: TavliSpacing.small,
                children: [
                  TavliButton.primary(
                    label: 'Pogledaj recepte',
                    glyph: TavliIcons.recipes,
                    onPressed: () => context.go('/recipes'),
                  ),
                  TavliButton.secondary(
                    label: 'Napravi plan',
                    glyph: TavliIcons.plan,
                    onPressed: () => context.go('/plan/new'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final mode = view.mode!;
    final modeChoice = TavliChoice<ShoppingMode>.segmented(
      options: const [
        TavliOption(ShoppingMode.plan, 'Po planu'),
        TavliOption(ShoppingMode.recipe, 'Po receptu'),
      ],
      selected: mode,
      onChanged: (m) => ref.read(shoppingViewProvider.notifier).setMode(m),
    );
    return Scaffold(
      appBar: const TabAppBar(),
      body: SafeArea(
        child: switch (mode) {
          ShoppingMode.plan => _PlanShopping(mode: modeChoice),
          ShoppingMode.recipe => _RecipeShopping(mode: modeChoice),
        },
      ),
    );
  }
}

/// Prazno stanje koje se pomera kada ne staje (veliki tekst, nizak ekran),
/// a inače stoji u sredini.
class _ScrollableState extends StatelessWidget {
  const _ScrollableState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(child: child),
      ),
    ),
  );
}

class _ShoppingLoadError extends StatelessWidget {
  const _ShoppingLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _ScrollableState(
    child: TavliEmptyState(
      glyph: TavliIcons.info,
      title: 'Nabavka trenutno ne može da se prikaže.',
      action: TavliButton.primary(label: 'Pokušaj ponovo', onPressed: onRetry),
    ),
  );
}

class _PlanShopping extends ConsumerWidget {
  const _PlanShopping({required this.mode});

  final Widget mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(mealPlansProvider);
    return plans.when(
      loading: () => ShoppingFrame(mode: mode, body: const TavliLoading()),
      error: (_, _) => ShoppingFrame(
        mode: mode,
        body: _ShoppingLoadError(
          onRetry: () => ref.invalidate(mealPlansProvider),
        ),
      ),
      data: (list) {
        final plan = selectedPlan(
          list,
          ref.watch(planViewProvider),
          ref.watch(clockProvider)(),
        );
        if (plan == null) {
          return ShoppingFrame(mode: mode, body: const _NoPlan());
        }
        return _PlanPeriod(mode: mode, plans: list, plan: plan);
      },
    );
  }
}

/// „Po planu“ bez plana. Kad postoji nabavka po receptu, kaže koliko čeka u
/// tabu „Po receptu“, da ekran ne izgleda kao da nabavke nema.
class _NoPlan extends ConsumerWidget {
  const _NoPlan();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipeAsync = ref.watch(recipeShoppingProvider);
    if (recipeAsync.hasError) {
      return _ShoppingLoadError(
        onRetry: () => ref.invalidate(recipeShoppingProvider),
      );
    }
    if (recipeAsync.isLoading && !recipeAsync.hasValue) {
      return const TavliLoading();
    }
    final recipeItems = recipeAsync.value ?? const <ShoppingItemRow>[];
    final open = recipeItems.where((i) => !i.isBought).length;
    return _ScrollableState(
      child: TavliEmptyState(
        glyph: TavliIcons.plan,
        title: 'Još nemaš plan',
        message: 'Nabavka po planu nastaje iz sačuvanog plana obroka.',
        // „Po receptu“ je već izbor iznad, pa ovde nema drugog dugmeta.
        action: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: TavliSpacing.large,
          children: [
            if (recipeItems.isNotEmpty)
              TavliNotice(
                message: open > 0
                    ? 'U „Po receptu“ te čeka ${itemsCount(open)} za kupovinu.'
                    : 'Sve iz nabavke po receptu je kupljeno.',
              ),
            Center(
              child: TavliButton.primary(
                label: 'Napravi plan',
                glyph: TavliIcons.add,
                onPressed: () => context.go('/plan/new'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanPeriod extends ConsumerWidget {
  const _PlanPeriod({
    required this.mode,
    required this.plans,
    required this.plan,
  });

  final Widget mode;
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
    if (shopping.hasError) {
      return ShoppingFrame(
        mode: mode,
        body: _ShoppingLoadError(
          onRetry: () => ref.invalidate(planShoppingProvider(plan.id)),
        ),
      );
    }
    final all = shopping.value ?? const <PlanShoppingItem>[];
    final wholePlan = view.wholePlan && periods.length > 1;

    // Nedelje se biraju po rednom broju; „Ceo plan“ je poseban izbor.
    const whole = 0;
    final filters = <Widget>[
      if (plans.length > 1) _PlanPicker(plans: plans, plan: plan),
      TavliChoice<int>.chips(
        options: [
          for (final p in periods) TavliOption(p.number, 'Nedelja ${p.number}'),
          if (periods.length > 1) const TavliOption(whole, 'Ceo plan'),
        ],
        selected: wholePlan ? whole : week.number,
        onChanged: (n) {
          if (n == whole) return controller.selectWholePlan();
          for (final p in periods) {
            if (p.number == n) controller.selectWeek(p.range.start);
          }
        },
      ),
      Text(
        wholePlan
            ? '${rangeLabel(plan.range)} · zbir svih nedelja'
            : rangeLabel(week.range),
        style: theme.textTheme.titleMedium,
      ),
    ];

    if (shopping.isLoading && !shopping.hasValue) {
      return ShoppingFrame(
        mode: mode,
        filters: filters,
        body: const TavliLoading(),
      );
    }
    if (wholePlan) {
      return _WholePlan(
        mode: mode,
        filters: filters,
        items: [for (final i in all) i.item],
      );
    }
    final repo = ref.read(shoppingRepositoryProvider);
    return ShoppingItemsList(
      mode: mode,
      filters: filters,
      items: [
        for (final i in all)
          if (i.weekStart == week.range.start) i.item,
      ],
      listId: () => repo.weekList(plan.id, week),
      emptyText: 'Za ovu nedelju nema šta da se kupi.',
    );
  }
}

/// Izbor plana kada ih ima više: dugme sa opsegom izabranog plana otvara
/// meni sa planovima.
class _PlanPicker extends ConsumerWidget {
  const _PlanPicker({required this.plans, required this.plan});

  final List<MealPlan> plans;
  final MealPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Semantics(
      label: 'Izaberi plan',
      child: TavliButton.secondary(
        label: rangeLabel(plan.range),
        glyph: TavliIcons.plan,
        onPressed: () {
          final box = context.findRenderObject()! as RenderBox;
          unawaited(
            showTavliActionMenu(
              context,
              title: 'Izaberi plan',
              position: box.localToGlobal(box.size.bottomLeft(Offset.zero)),
              actions: [
                for (final p in plans)
                  TavliMenuAction(
                    rangeLabel(p.range),
                    onSelected: () =>
                        ref.read(planViewProvider.notifier).selectPlan(p.id),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

/// Ceo plan: zbir nedelja po namirnici. Štikliranje beleži kupovinu u
/// nedeljnim stavkama, pa nedelje i ceo plan pokazuju istu kupovinu.
class _WholePlan extends ConsumerStatefulWidget {
  const _WholePlan({
    required this.mode,
    required this.filters,
    required this.items,
  });

  final Widget mode;
  final List<Widget> filters;
  final List<ShoppingItemRow> items;

  @override
  ConsumerState<_WholePlan> createState() => _WholePlanState();
}

class _WholePlanState extends ConsumerState<_WholePlan> {
  String? _selected;

  static String _key(PlanTotal t) => '${t.ingredient}/${t.unitGroup}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final received = ref.watch(receivedItemsProvider).value ?? const {};
    final byId = {for (final i in widget.items) i.id: i};
    final totals = ShoppingRepository.totalsOf(widget.items);
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final withDetail = hasShoppingDetail(context, constraints);
        PlanTotal? selected;
        if (withDetail) {
          for (final t in totals) {
            if (_key(t) == _selected) selected = t;
          }
          selected ??= open.firstOrNull ?? done.firstOrNull;
        }
        final selectedBought = selected != null && done.contains(selected);

        Widget row(PlanTotal t) {
          final bought = done.contains(t);
          final isReceived =
              bought && ids(t, bought: true).every(received.contains);
          final detail = [
            if (!bought) amount(t.openMicros, t) ?? 'Proveri količinu',
            if (amount(t.boughtMicros, t) case final b?) 'kupljeno $b',
            if (isReceived) 'U ostavi',
          ].join(' · ');
          return TavliCheckRow(
            title: t.name,
            detail: detail.isEmpty ? null : detail,
            checked: bought,
            onChanged: isReceived
                ? null
                : (_) => unawaited(
                    setBought(
                      context,
                      ref,
                      ids(t, bought: bought),
                      t.name,
                      bought: !bought,
                    ),
                  ),
            selected: selected == t,
            onSelect: withDetail
                ? () => setState(() => _selected = _key(t))
                : null,
          );
        }

        return ShoppingFrame(
          mode: widget.mode,
          filters: widget.filters,
          detail: selected == null
              ? null
              : ShoppingItemDetail(
                  key: ValueKey(_key(selected)),
                  name: selected.name,
                  amount: selectedBought
                      ? amount(selected.boughtMicros, selected)
                      : amount(selected.openMicros, selected),
                  ids: ids(selected, bought: selectedBought),
                  bought: selectedBought,
                ),
          children: [
            ...groupedRows(
              open: open,
              bought: done,
              category: (t) => t.category,
              row: row,
              emptyText: 'Za ovaj plan nema šta da se kupi.',
              allBoughtText: 'Sve je kupljeno.',
              text: theme.textTheme,
              colors: theme.colorScheme,
            ),
            StorePriceSummary(items: widget.items),
          ],
        );
      },
    );
  }
}

class _RecipeShopping extends ConsumerWidget {
  const _RecipeShopping({required this.mode});

  final Widget mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(recipeShoppingProvider);
    final preparationsAsync = ref.watch(preparationsProvider);
    if (items.hasError || preparationsAsync.hasError) {
      return ShoppingFrame(
        mode: mode,
        body: _ShoppingLoadError(
          onRetry: () {
            ref.invalidate(recipeShoppingProvider);
            ref.invalidate(preparationsProvider);
          },
        ),
      );
    }
    if ((items.isLoading && !items.hasValue) ||
        (preparationsAsync.isLoading && !preparationsAsync.hasValue)) {
      return ShoppingFrame(mode: mode, body: const TavliLoading());
    }
    final preparations = preparationsAsync.value ?? const [];
    final repo = ref.read(shoppingRepositoryProvider);
    return ShoppingItemsList(
      mode: mode,
      header: [
        if (preparations.isNotEmpty) ...[
          const TavliSectionHeader(
            'Recepti u nabavci',
            style: TavliSectionHeaderStyle.bold,
          ),
          TavliListGroup(
            children: [for (final p in preparations) _PreparationTile(p)],
          ),
          const SizedBox(height: TavliSpacing.medium),
        ],
      ],
      items: items.value ?? const [],
      listId: repo.recipeList,
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
    return TavliListRow(
      title: p.snapshot.title,
      subtitle:
          '${servingsLabel(p.servings)} · ${ingredientsCount(n)} za kupovinu',
      leading: const TavliIcon(TavliIcons.recipes),
      trailing: TavliIconButton(
        glyph: TavliIcons.delete,
        semanticLabel: 'Ukloni iz nabavke',
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          await ref.read(shoppingRepositoryProvider).removeSource(p.id);
          showTavliMessageOn(
            messenger,
            'Uklonjeno iz nabavke: ${p.snapshot.title}. Kupljeno ostaje.',
          );
        },
      ),
    );
  }
}
