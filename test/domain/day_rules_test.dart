import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/day_rules.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_source.dart';

RecipeSnapshot dish(List<Ingredient> items) =>
    RecipeSnapshot(title: 'Jelo', baseServings: 2, ingredients: items);

const meso = Ingredient(name: 'Mleveno meso', category: 'meso i riba');
const losos = Ingredient(name: 'file lososa', category: 'meso i riba');
const krompir = Ingredient(name: 'krompir', category: 'voće i povrće');
const nepoznato = Ingredient(name: 'divljač X', category: 'meso i riba');

const mondayNoMeat = DayRule(id: 'r1', weekday: 1, kind: RuleKind.noMeat);
const fridayFish = DayRule(id: 'r2', weekday: 5, kind: RuleKind.fish);

// 2. novembar 2026. je ponedeljak.
MealSlot slot(int day, [MealType type = MealType.lunch]) =>
    MealSlot(CivilDate(2026, 11, day), type);

void main() {
  test('bez mesa razlikuje mleveno brašno i pačetinu', () {
    expect(
      evaluateRule(
        mondayNoMeat,
        dish([
          const Ingredient(name: 'mleveno brašno', category: 'suvi proizvodi'),
        ]),
      ).fit,
      RuleFit.pass,
    );
    expect(
      evaluateRule(
        mondayNoMeat,
        dish([const Ingredient(name: 'pačetina')]),
      ).fit,
      RuleFit.fail,
    );
    expect(evaluateRule(mondayNoMeat, dish([meso])).fit, RuleFit.fail);
  });

  test('kratak naziv sastojka se ne poklapa sa delom druge reči', () {
    const noSalt = DayRule(
      id: 'salt',
      weekday: 1,
      kind: RuleKind.without,
      value: 'so',
    );
    expect(
      evaluateRule(noSalt, dish([const Ingredient(name: 'losos')])).fit,
      RuleFit.pass,
    );
    expect(
      evaluateRule(noSalt, dish([const Ingredient(name: 'morska so')])).fit,
      RuleFit.fail,
    );
  });

  test('ponedeljak bez mesa: mesni recept krši, sa dokazom', () {
    final r = evaluateRule(mondayNoMeat, dish([meso, krompir]));
    expect(r.fit, RuleFit.fail);
    expect(r.evidence, ['Mleveno meso']);
    expect(
      ruleResultText(r),
      'Krši pravilo: Ponedeljak · bez mesa '
      '(Mleveno meso)',
    );
  });

  test('neklasifikovan sastojak iz kategorije meso i riba je Neprovereno', () {
    final r = evaluateRule(mondayNoMeat, dish([nepoznato, krompir]));
    expect(r.fit, RuleFit.unknown);
    expect(ruleResultText(r), 'Neprovereno: Ponedeljak · bez mesa (divljač X)');
    expect(evaluateRule(mondayNoMeat, null).fit, RuleFit.unknown);
    expect(evaluateRule(mondayNoMeat, dish(const [])).fit, RuleFit.unknown);
  });

  test('riba nije meso; posno jelo poštuje pravilo', () {
    expect(evaluateRule(mondayNoMeat, dish([losos])).fit, RuleFit.pass);
    expect(evaluateRule(mondayNoMeat, dish([krompir])).fit, RuleFit.pass);
  });

  test('petak riba: losos poštuje, krompir krši, nepoznato je neprovereno', () {
    expect(evaluateRule(fridayFish, dish([losos, krompir])).fit, RuleFit.pass);
    expect(evaluateRule(fridayFish, dish([krompir])).fit, RuleFit.fail);
    expect(evaluateRule(fridayFish, dish([nepoznato])).fit, RuleFit.unknown);
  });

  test('prepoznavanje reči: somun nije som, rakija nije rak, tuna jeste', () {
    const fishRule = DayRule(id: 'f', weekday: 5, kind: RuleKind.fish);
    expect(
      evaluateRule(fishRule, dish([const Ingredient(name: 'somun')])).fit,
      RuleFit.fail,
    );
    expect(
      evaluateRule(fishRule, dish([const Ingredient(name: 'rakija')])).fit,
      RuleFit.fail,
    );
    expect(
      evaluateRule(fishRule, dish([const Ingredient(name: 'tuna u ulju')])).fit,
      RuleFit.pass,
    );
    expect(
      evaluateRule(
        mondayNoMeat,
        dish([const Ingredient(name: 'Ćuretina')]),
      ).fit,
      RuleFit.fail,
    );
  });

  test('bez sastojka i sa sastojkom, bez razlike u kvačicama', () {
    const noOnion = DayRule(
      id: 'o',
      weekday: 3,
      kind: RuleKind.without,
      value: 'luk',
    );
    const withPotato = DayRule(
      id: 'p',
      weekday: 3,
      kind: RuleKind.withIngredient,
      value: 'krompir',
    );
    final onion = dish([const Ingredient(name: 'Crni luk'), krompir]);
    expect(evaluateRule(noOnion, onion).fit, RuleFit.fail);
    expect(evaluateRule(noOnion, onion).evidence, ['Crni luk']);
    expect(evaluateRule(withPotato, onion).fit, RuleFit.pass);
    expect(evaluateRule(withPotato, dish([meso])).fit, RuleFit.fail);
  });

  test('matrica dana i obroka: pravilo važi samo za svoj dan i obrok', () {
    const dinnerOnly = DayRule(
      id: 'd',
      weekday: 1,
      mealType: MealType.dinner,
      kind: RuleKind.noMeat,
    );
    for (var day = 2; day <= 8; day++) {
      final s = slot(day);
      expect(mondayNoMeat.appliesTo(s), s.date.weekday == 1, reason: '$day');
    }
    expect(dinnerOnly.appliesTo(slot(2, MealType.dinner)), isTrue);
    expect(dinnerOnly.appliesTo(slot(2)), isFalse);
    expect(dinnerOnly.appliesTo(slot(9, MealType.dinner)), isTrue);
    expect(
      evaluateSlot([mondayNoMeat, fridayFish], slot(2), dish([meso])).length,
      1,
    );
  });

  test('obavezno i želja; izuzetak važi samo za taj obrok i to pravilo', () {
    const preferred = DayRule(
      id: 'w',
      weekday: 1,
      kind: RuleKind.noMeat,
      mode: RuleMode.preferred,
    );
    final results = evaluateSlot(
      [mondayNoMeat, preferred],
      slot(2),
      dish([meso]),
    );
    expect(blockingViolations(results, const {}).map((r) => r.rule.id), ['r1']);
    expect(blockingViolations(results, const {'r1'}), isEmpty);
    expect(blockingViolations(results, const {'w'}).single.rule.id, 'r1');
    expect(
      ruleResultText(results[1]),
      'Odstupa od želje: Ponedeljak · bez mesa (želja) (Mleveno meso)',
    );
    expect(
      ruleResultText(results[0], overridden: true),
      'Izuzetak: Ponedeljak · bez mesa (Mleveno meso)',
    );
  });

  test('naziv pravila, opis za AI i provera unosa', () {
    const r = DayRule(
      id: 'x',
      weekday: 5,
      mealType: MealType.lunch,
      kind: RuleKind.fish,
    );
    expect(r.label, 'Petak · ručak · riba');
    expect(r.promptLine, 'Friday (lunch): a fish dish — required');
    expect(
      () =>
          validRule(const DayRule(id: 'y', weekday: 1, kind: RuleKind.without)),
      throwsArgumentError,
    );
    expect(
      () =>
          validRule(const DayRule(id: 'y', weekday: 8, kind: RuleKind.noMeat)),
      throwsArgumentError,
    );
    validRule(
      const DayRule(id: 'y', weekday: 1, kind: RuleKind.without, value: 'luk'),
    );
  });
}
