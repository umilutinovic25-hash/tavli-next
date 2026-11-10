import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/plan_calendar.dart';

void main() {
  test('vrsta obroka: prazno je kuvanje, nepoznato zauzima mesto', () {
    expect(MealKind.parse(null), MealKind.cook);
    expect(MealKind.parse('cook'), MealKind.cook);
    expect(MealKind.parse('away'), MealKind.away);
    expect(MealKind.parse('leftover'), MealKind.away);
  });

  test('razlog i naslov obroka van kuće', () {
    expect(AwayReason.tryParse('restaurant'), AwayReason.restaurant);
    expect(AwayReason.tryParse('nešto'), isNull);
    PlannedMeal meal(AwayReason? r, [String? note]) => PlannedMeal(
      id: 'm',
      planId: 'p',
      slot: MealSlot(CivilDate(2026, 11, 4), MealType.lunch),
      servings: 2,
      kind: MealKind.away,
      awayReason: r,
      awayNote: note,
    );
    expect(meal(AwayReason.restaurant).awayTitle, 'Restoran');
    expect(meal(AwayReason.visiting).awayTitle, 'Kod roditelja');
    expect(meal(AwayReason.skip, 'post').awayTitle, 'Preskačem · post');
    expect(meal(null).awayTitle, 'Van kuće');
  });

  test('ponovni predlog ne dira obrok van kuće', () {
    final range = DateRange(CivilDate(2026, 11, 4), CivilDate(2026, 11, 5));
    final plan = MealPlan(
      id: 'p',
      range: range,
      mealTypes: const {MealType.lunch},
      defaultServings: 2,
      usePantry: true,
      createdAt: DateTime.utc(2026),
    );
    final away = PlannedMeal(
      id: 'a',
      planId: 'p',
      slot: MealSlot(range.start, MealType.lunch),
      servings: 2,
      kind: MealKind.away,
      awayReason: AwayReason.restaurant,
    );
    expect(regenerableSlots(plan, [away], range.start), {
      MealSlot(range.end, MealType.lunch),
    });
  });
}
