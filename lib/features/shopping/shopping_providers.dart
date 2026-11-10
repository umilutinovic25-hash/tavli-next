import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/auth_controller.dart';
import '../../data/database.dart';
import '../../data/pantry_repository.dart';
import '../../data/shopping_repository.dart';
import '../../domain/plan_calendar.dart';
import '../../providers.dart';
import '../recipes/recipe_providers.dart';

/// Jedina instanca repozitorijuma Ostave prijavljenog domaćinstva.
final pantryRepositoryProvider = Provider<PantryRepository>(
  (ref) => PantryRepository(
    ref.watch(databaseProvider),
    scope: ref.watch(accountScopeProvider) ?? noAccountScope,
    writer: ref.watch(syncedWriterProvider),
    shopping: ref.watch(shoppingRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Stavke nedeljnih lista plana, uživo.
final planShoppingProvider = StreamProvider.autoDispose
    .family<List<PlanShoppingItem>, String>(
      (ref, planId) =>
          ref.watch(shoppingRepositoryProvider).watchPlanItems(planId),
    );

/// Stavke nabavke bez plana (recepti i ručne stavke), uživo.
final recipeShoppingProvider =
    StreamProvider.autoDispose<List<ShoppingItemRow>>(
      (ref) => ref.watch(shoppingRepositoryProvider).watchRecipeItems(),
    );

/// Tekuće pripreme recepata bez plana.
final preparationsProvider =
    StreamProvider.autoDispose<List<RecipePreparation>>(
      (ref) => ref.watch(shoppingRepositoryProvider).watchPreparations(),
    );

/// Kupljene stavke koje su već u ostavi.
final receivedItemsProvider = StreamProvider.autoDispose<Set<String>>(
  (ref) => ref.watch(pantryRepositoryProvider).watchReceivedItemIds(),
);

/// Po planu (nedelje ili ceo plan) ili po receptu (bez plana).
enum ShoppingMode { plan, recipe }

/// Šta Nabavka prikazuje. Plan se bira u `planViewProvider`, pa Nabavka
/// otvara isti plan kao Plan tab.
class ShoppingView {
  const ShoppingView({
    this.mode = ShoppingMode.plan,
    this.weekStart,
    this.wholePlan = false,
  });

  final ShoppingMode mode;

  /// Izabrana nedelja; null = nedelja sa današnjim danom, inače prva.
  final CivilDate? weekStart;
  final bool wholePlan;
}

class ShoppingViewController extends Notifier<ShoppingView> {
  @override
  ShoppingView build() {
    ref.watch(accountScopeProvider);
    return const ShoppingView();
  }

  void setMode(ShoppingMode mode) => state = ShoppingView(
    mode: mode,
    weekStart: state.weekStart,
    wholePlan: state.wholePlan,
  );

  void selectWeek(CivilDate start) =>
      state = ShoppingView(mode: state.mode, weekStart: start);

  void selectWholePlan() => state = ShoppingView(
    mode: state.mode,
    weekStart: state.weekStart,
    wholePlan: true,
  );
}

final shoppingViewProvider =
    NotifierProvider<ShoppingViewController, ShoppingView>(
      ShoppingViewController.new,
    );

/// Izabrana nedelja plana: iz izbora ako još postoji, inače današnja, inače
/// prva.
WeekPeriod selectedWeek(
  List<WeekPeriod> periods,
  ShoppingView view,
  CivilDate today,
) {
  for (final p in periods) {
    if (p.range.start == view.weekStart) return p;
  }
  for (final p in periods) {
    if (p.range.contains(today)) return p;
  }
  return periods.first;
}
