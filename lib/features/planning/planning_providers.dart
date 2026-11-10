import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/auth_controller.dart';
import '../../data/day_rule_repository.dart';
import '../../data/meal_plan_repository.dart';
import '../../domain/day_rules.dart';
import '../../domain/meal_plan.dart';
import '../../domain/plan_calendar.dart';
import '../../providers.dart';
import '../recipes/recipe_providers.dart';

/// Planovi prijavljenog domaćinstva (čita lokalni keš naloga).
final mealPlanRepositoryProvider = Provider<MealPlanRepository>(
  (ref) => MealPlanRepository(
    ref.watch(databaseProvider),
    scope: ref.watch(accountScopeProvider) ?? noAccountScope,
    writer: ref.watch(syncedWriterProvider),
    shopping: ref.watch(shoppingRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Pravila po danima domaćinstva.
final dayRuleRepositoryProvider = Provider<DayRuleRepository>(
  (ref) => DayRuleRepository(
    ref.watch(databaseProvider),
    scope: ref.watch(accountScopeProvider) ?? noAccountScope,
    writer: ref.watch(syncedWriterProvider),
    clock: ref.watch(clockProvider),
  ),
);

final dayRulesProvider = StreamProvider.autoDispose<List<DayRule>>(
  (ref) => ref.watch(dayRuleRepositoryProvider).watchAll(),
);

/// Svi sačuvani planovi, noviji prvi.
final mealPlansProvider = StreamProvider.autoDispose<List<MealPlan>>(
  (ref) => ref.watch(mealPlanRepositoryProvider).watchPlans(),
);

final mealPlanProvider = StreamProvider.autoDispose.family<MealPlan?, String>(
  (ref, id) => ref.watch(mealPlanRepositoryProvider).watchPlan(id),
);

final plannedMealsProvider = StreamProvider.autoDispose
    .family<List<PlannedMeal>, String>(
      (ref, id) => ref.watch(mealPlanRepositoryProvider).watchMeals(id),
    );

/// Plan koji se prikazuje: najnoviji koji sadrži danas, inače najnoviji.
MealPlan? selectDefaultPlan(List<MealPlan> plans, DateTime now) {
  final today = CivilDate.today(() => now);
  for (final p in plans) {
    if (p.range.contains(today)) return p;
  }
  return plans.isEmpty ? null : plans.first;
}

enum PlanViewMode { week, month }

/// Šta Plan tab prikazuje: izabran plan (null = podrazumevani), nedelja ili
/// mesec, izabran dan i (na širokom ekranu) izabran obrok.
class PlanView {
  const PlanView({
    this.planId,
    this.mode = PlanViewMode.week,
    this.date,
    this.entryId,
  });

  final String? planId;
  final PlanViewMode mode;

  /// null = danas ako je u planu, inače prvi dan plana.
  final CivilDate? date;
  final String? entryId;

  PlanView copyWith({
    String? planId,
    PlanViewMode? mode,
    CivilDate? date,
    String? entryId,
    bool clearEntry = false,
  }) => PlanView(
    planId: planId ?? this.planId,
    mode: mode ?? this.mode,
    date: date ?? this.date,
    entryId: clearEntry ? null : (entryId ?? this.entryId),
  );
}

class PlanViewController extends Notifier<PlanView> {
  @override
  PlanView build() {
    ref.watch(accountScopeProvider);
    return const PlanView();
  }

  void selectPlan(String id) => state = PlanView(planId: id, mode: state.mode);

  void setMode(PlanViewMode mode) => state = state.copyWith(mode: mode);

  void selectDate(CivilDate date) => state = state.copyWith(date: date);

  void selectEntry(String? id) =>
      state = state.copyWith(entryId: id, clearEntry: id == null);
}

final planViewProvider = NotifierProvider<PlanViewController, PlanView>(
  PlanViewController.new,
);

/// Izabran plan: iz [planViewProvider] ako još postoji, inače podrazumevani.
MealPlan? selectedPlan(List<MealPlan> plans, PlanView view, DateTime now) {
  for (final p in plans) {
    if (p.id == view.planId) return p;
  }
  return selectDefaultPlan(plans, now);
}

/// Izabran dan unutar plana.
CivilDate selectedDate(MealPlan plan, PlanView view, CivilDate today) {
  final d = view.date;
  if (d != null && plan.range.contains(d)) return d;
  return plan.range.contains(today) ? today : plan.range.start;
}
