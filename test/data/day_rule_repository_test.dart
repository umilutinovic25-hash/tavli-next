import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/day_rule_repository.dart';
import 'package:tavli/data/meal_plan_repository.dart';
import 'package:tavli/data/shopping_repository.dart';
import 'package:tavli/domain/day_rules.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/sync/synced_writer.dart';

const scope = AccountScope(userId: 'u1', householdId: 'h1');

// Ponedeljci 2. i 9. novembra 2026.
final monday = CivilDate(2026, 11, 2);
final nextMonday = CivilDate(2026, 11, 9);

RecipeSnapshot dish(String title, List<Ingredient> items) =>
    RecipeSnapshot(title: title, baseServings: 2, ingredients: items);

final sarma = dish('Sarma', const [
  Ingredient(name: 'mleveno meso', category: 'meso i riba'),
]);
final pasulj = dish('Pasulj', const [Ingredient(name: 'pasulj')]);

void main() {
  late AppDatabase db;
  late DayRuleRepository rules;
  late MealPlanRepository plans;
  var n = 0;

  setUp(() {
    n = 0;
    db = AppDatabase(NativeDatabase.memory());
    final writer = SyncedWriter(db, accountId: 'u1');
    rules = DayRuleRepository(
      db,
      scope: scope,
      writer: writer,
      newId: () => 'rule-${++n}',
    );
    plans = MealPlanRepository(
      db,
      scope: scope,
      writer: writer,
      shopping: ShoppingRepository(db, scope: scope, writer: writer),
      clock: () => DateTime.utc(2026, 11),
    );
  });
  tearDown(() => db.close());

  /// Ručak 2–9. novembra; [dishes] po danu (ostalo pasulj).
  PlanDraft draft(Map<int, RecipeSnapshot> dishes, {PlanBase? base}) {
    final request = PlanRequest(
      range: DateRange(monday, nextMonday),
      mealTypes: const {MealType.lunch},
    );
    return PlanDraft(
      request: request,
      proposals: {
        for (final s in request.slots)
          s: SlotProposal(
            title: (dishes[s.date.day] ?? pasulj).title,
            draftRecipeKey: '${s.date.day}',
          ),
      },
      newRecipes: {
        for (final s in request.slots)
          '${s.date.day}': dishes[s.date.day] ?? pasulj,
      },
      base: base,
    );
  }

  MealSlot lunch(CivilDate d) => MealSlot(d, MealType.lunch);

  test(
    'pravila se dodaju, čitaju i brišu sa outbox-om; loš unos se odbija',
    () async {
      await rules.add(weekday: 1, kind: RuleKind.noMeat);
      await rules.add(
        weekday: 3,
        kind: RuleKind.without,
        value: ' luk ',
        mode: RuleMode.preferred,
      );
      final all = await rules.getAll();
      expect(all.map((r) => r.label), [
        'Ponedeljak · bez mesa',
        'Sreda · bez: luk (želja)',
      ]);
      await rules.remove('rule-1');
      expect((await rules.getAll()).single.id, 'rule-2');
      final ops = [
        for (final r in await db.select(db.syncOutbox).get())
          '${r.entity}:${r.op}',
      ];
      expect(ops, contains('day_rule:delete'));
      expect(
        () => rules.add(weekday: 2, kind: RuleKind.withIngredient),
        throwsArgumentError,
      );
    },
  );

  test(
    'ponedeljak bez mesa: čuvanje mesnog jela se odbija bez izuzetka',
    () async {
      await rules.add(weekday: 1, kind: RuleKind.noMeat);
      await expectLater(
        plans.approve(draft({2: sarma})),
        throwsA(
          isA<RuleViolationException>().having((e) => e.slots, 'slots', [
            lunch(monday),
          ]),
        ),
      );
      expect(await db.select(db.mealPlans).get(), isEmpty);
    },
  );

  test(
    'izuzetak važi samo za taj ponedeljak; sledeći se i dalje proverava',
    () async {
      await rules.add(weekday: 1, kind: RuleKind.noMeat);
      // Oba ponedeljka imaju sarmu; izuzetak samo za prvi.
      await expectLater(
        plans.approve(
          draft({2: sarma, 9: sarma}),
          overrides: {
            lunch(monday): {'rule-1'},
          },
        ),
        throwsA(
          isA<RuleViolationException>().having((e) => e.slots, 'slots', [
            lunch(nextMonday),
          ]),
        ),
      );

      final id = await plans.approve(
        draft({2: sarma}),
        overrides: {
          lunch(monday): {'rule-1'},
        },
      );
      final meals = await plans.watchMeals(id).first;
      expect(meals.first.ruleOverrides, {'rule-1'});
      expect(meals.last.ruleOverrides, isEmpty);
    },
  );

  test('želja i neprovereno ne blokiraju čuvanje', () async {
    await rules.add(
      weekday: 1,
      kind: RuleKind.noMeat,
      mode: RuleMode.preferred,
    );
    await rules.add(weekday: 2, kind: RuleKind.noMeat);
    final unknown = dish('Divljač', const [
      Ingredient(name: 'divljač X', category: 'meso i riba'),
    ]);
    final id = await plans.approve(draft({2: sarma, 3: unknown}));
    expect(await plans.watchMeals(id).first, hasLength(8));
  });

  test('izuzetak na sačuvanom obroku se uključuje i ukida; zamena jela '
      'briše stare izuzetke', () async {
    final id = await plans.approve(draft({}));
    final meal = (await plans.watchMeals(id).first).first;
    await plans.setRuleOverride(meal.id, 'r-x', allowed: true);
    expect((await plans.watchMeals(id).first).first.ruleOverrides, {'r-x'});
    await plans.setRuleOverride(meal.id, 'r-x', allowed: false);
    expect((await plans.watchMeals(id).first).first.ruleOverrides, isEmpty);

    await plans.setRuleOverride(meal.id, 'r-x', allowed: true);
    final plan = (await plans.watchPlans().first).single;
    final base = PlanBase(planId: id, fingerprint: await plans.fingerprint(id));
    final request = PlanRequest(
      range: plan.range,
      mealTypes: plan.mealTypes,
      only: {meal.slot},
    );
    await plans.approve(
      PlanDraft(
        request: request,
        proposals: {
          meal.slot: const SlotProposal(title: 'Sarma', draftRecipeKey: 's'),
        },
        newRecipes: {'s': sarma},
        base: base,
      ),
    );
    expect((await plans.watchMeals(id).first).first.ruleOverrides, isEmpty);
  });

  test('pravila su odvojena po domaćinstvu', () async {
    await rules.add(weekday: 1, kind: RuleKind.noMeat);
    final theirs = DayRuleRepository(
      db,
      scope: const AccountScope(userId: 'u2', householdId: 'h2'),
      writer: SyncedWriter(db, accountId: 'u2'),
    );
    expect(await theirs.getAll(), isEmpty);
    await theirs.remove('rule-1');
    expect(await rules.getAll(), hasLength(1));
    // Tuđe pravilo ne važi za moj plan i obrnuto.
    final otherPlans = MealPlanRepository(
      db,
      scope: const AccountScope(userId: 'u2', householdId: 'h2'),
      writer: SyncedWriter(db, accountId: 'u2'),
      shopping: ShoppingRepository(
        db,
        scope: const AccountScope(userId: 'u2', householdId: 'h2'),
        writer: SyncedWriter(db, accountId: 'u2'),
      ),
    );
    expect(await otherPlans.approve(draft({2: sarma})), isNotEmpty);
  });

  test('nepoznata vrsta pravila (novija verzija) se preskače', () async {
    await db
        .into(db.dayRules)
        .insert(
          DayRulesCompanion.insert(
            id: 'novo',
            householdId: const Value('h1'),
            weekday: 1,
            kind: 'nesto-novo',
            createdAt: DateTime.utc(2026),
          ),
        );
    expect(await rules.getAll(), isEmpty);
  });
}
