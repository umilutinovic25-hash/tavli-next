import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/cook_soon_repository.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/meal_plan_repository.dart';
import 'package:tavli/data/recipe_repository.dart';
import 'package:tavli/data/shopping_repository.dart';
import 'package:tavli/domain/cook_soon.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/sync/synced_writer.dart';

import '../helpers/fake_photo_store.dart';

const scope = AccountScope(userId: 'one', householdId: 'home-one');
const other = AccountScope(userId: 'two', householdId: 'home-two');

final monday = CivilDate(2026, 11, 2);

Recipe recipe(String id, String title, {int servings = 4}) => Recipe(
  id: id,
  title: title,
  servings: servings,
  ingredients: const [Ingredient(name: 'krompir', quantity: 1, unit: 'kg')],
  steps: const ['Kuvati.'],
  source: RecipeSource.manual,
  createdAt: DateTime.utc(2026),
);

void main() {
  late AppDatabase db;
  late SyncedWriter writer;
  late RecipeRepository recipes;
  late MealPlanRepository plans;
  late CookSoonRepository queue;
  var ids = 0;

  CookSoonRepository makeQueue(AccountScope s) {
    final w = SyncedWriter(db, accountId: s.userId);
    final p = MealPlanRepository(
      db,
      scope: s,
      writer: w,
      shopping: ShoppingRepository(db, scope: s, writer: w),
      clock: () => DateTime.utc(2026, 11, 2, 9),
    );
    return CookSoonRepository(
      db,
      scope: s,
      writer: w,
      plans: p,
      clock: () => DateTime.utc(2026, 11, 2, 9),
      newId: () => 'q${++ids}',
    );
  }

  setUp(() async {
    ids = 0;
    db = AppDatabase(NativeDatabase.memory());
    writer = SyncedWriter(db, accountId: 'one');
    recipes = RecipeRepository(
      db,
      FakePhotoStore(),
      writer: writer,
      scope: scope,
      clock: () => DateTime.utc(2026, 11, 2, 9),
    );
    plans = MealPlanRepository(
      db,
      scope: scope,
      writer: writer,
      shopping: ShoppingRepository(db, scope: scope, writer: writer),
      clock: () => DateTime.utc(2026, 11, 2, 9),
    );
    queue = makeQueue(scope);
    await recipes.create(recipe('r1', 'Sarma'));
    await recipes.create(recipe('r2', 'Pasulj', servings: 30));
  });

  tearDown(() => db.close());

  Future<List<String>> outbox() async => [
    for (final r in await (db.select(
      db.syncOutbox,
    )..orderBy([(t) => OrderingTerm.asc(t.seq)])).get())
      '${r.entity}:${r.op}',
  ];

  /// Plan od tri dana sa ručkom; prvi dan je "Pasulj".
  Future<MealPlan> savedPlan() async {
    final request = PlanRequest(
      range: DateRange(monday, monday.addDays(2)),
      mealTypes: const {MealType.lunch},
    );
    final first = request.slots.first;
    final id = await plans.approve(
      PlanDraft(
        request: request,
        proposals: {
          first: const SlotProposal(title: 'Pasulj', libraryRecipeId: 'r2'),
        },
        libraryRecipes: {
          'r2': RecipeSnapshot.fromRecipe(recipe('r2', 'Pasulj')),
        },
      ),
      allowPartial: true,
    );
    return (await plans.watchPlan(id).first)!;
  }

  Future<PlanBase> baseOf(MealPlan plan) async =>
      PlanBase(planId: plan.id, fingerprint: await plans.fingerprint(plan.id));

  test('dodavanje: snimak, porcije u granicama i redosled', () async {
    await queue.add(recipe('r1', 'Sarma'));
    await queue.add(recipe('r2', 'Pasulj', servings: 30));
    await queue.add(recipe('r1', 'Sarma'));
    final items = await queue.watchAll().first;
    expect(items.map((i) => (i.id, i.snapshot.title, i.servings, i.position)), [
      ('q1', 'Sarma', 4, 0),
      ('q2', 'Pasulj', 20, 1),
      ('q3', 'Sarma', 4, 2),
    ]);
    expect(items.first.recipeId, 'r1');
    expect(
      await outbox(),
      containsAllInOrder(['cook_soon_item:upsert', 'cook_soon_item:upsert']),
    );
  });

  test('10 stavki u redu ne pravi nikakvu potražnju za nabavku', () async {
    for (var i = 0; i < 10; i++) {
      await queue.add(recipe('r1', 'Sarma'));
    }
    expect(await queue.watchAll().first, hasLength(10));
    expect(await db.select(db.shoppingSources).get(), isEmpty);
    expect(await db.select(db.shoppingItems).get(), isEmpty);
  });

  test('premeštanje i uklanjanje', () async {
    for (final title in ['A', 'B', 'C']) {
      await queue.add(recipe('r1', title));
    }
    await queue.move('q3', 0);
    expect((await queue.watchAll().first).map((i) => i.snapshot.title), [
      'C',
      'A',
      'B',
    ]);
    await queue.remove('q1');
    expect((await queue.watchAll().first).map((i) => i.snapshot.title), [
      'C',
      'B',
    ]);
    expect(await outbox(), contains('cook_soon_item:delete'));
  });

  test('raspoređivanje na prazno mesto pravi obrok i nabavku i uklanja '
      'stavku u istoj transakciji', () async {
    final plan = await savedPlan();
    await queue.add(recipe('r1', 'Sarma'));
    final slot = MealSlot(monday.addDays(1), MealType.lunch);

    await queue.schedule(
      'q1',
      plan: plan,
      slot: slot,
      base: await baseOf(plan),
    );

    final meals = await plans.watchMeals(plan.id).first;
    final meal = meals.singleWhere((m) => m.slot == slot);
    expect(meal.recipeId, 'r1');
    expect(meal.snapshot!.title, 'Sarma');
    expect(meal.servings, 4);
    expect(await queue.watchAll().first, isEmpty);
    expect(
      (await db.select(db.shoppingSources).get()).map((s) => s.planEntryId),
      contains(meal.id),
    );
  });

  test('zamena postojećeg obroka čuva njegove porcije', () async {
    final plan = await savedPlan();
    await queue.add(recipe('r1', 'Sarma'));
    final first = MealSlot(monday, MealType.lunch);

    await queue.schedule(
      'q1',
      plan: plan,
      slot: first,
      base: await baseOf(plan),
    );

    final meal = (await plans.watchMeals(plan.id).first).single;
    expect(meal.snapshot!.title, 'Sarma');
    expect(meal.servings, 2);
  });

  test('zastareo plan: stavka ostaje u redu, obrok netaknut', () async {
    final plan = await savedPlan();
    await queue.add(recipe('r1', 'Sarma'));
    final base = await baseOf(plan);
    final meal = (await plans.watchMeals(plan.id).first).single;
    await plans.changeServings(meal.id, 3);
    final outboxBefore = await outbox();

    await expectLater(
      queue.schedule(
        'q1',
        plan: plan,
        slot: MealSlot(monday.addDays(1), MealType.lunch),
        base: base,
      ),
      throwsA(isA<StaleDraftException>()),
    );

    expect((await queue.watchAll().first).single.id, 'q1');
    expect(await plans.watchMeals(plan.id).first, hasLength(1));
    expect(await outbox(), outboxBefore);
  });

  test('zaključan obrok se ne zamenjuje; stavka ostaje', () async {
    final plan = await savedPlan();
    await queue.add(recipe('r1', 'Sarma'));
    final meal = (await plans.watchMeals(plan.id).first).single;
    await plans.setLocked(meal.id, locked: true);

    await expectLater(
      queue.schedule(
        'q1',
        plan: plan,
        slot: meal.slot,
        base: await baseOf(plan),
      ),
      throwsA(isA<StaleDraftException>()),
    );
    expect(await queue.watchAll().first, hasLength(1));
    expect(
      (await plans.watchMeals(plan.id).first).single.snapshot!.title,
      'Pasulj',
    );
  });

  test('obrisan recept: stavka čuva snimak i može da se rasporedi', () async {
    final plan = await savedPlan();
    await queue.add(recipe('r1', 'Sarma'));
    await recipes.delete('r1');

    final item = (await queue.watchAll().first).single;
    expect(item.recipeId, isNull);
    expect(item.snapshot.title, 'Sarma');
    expect(item.snapshot.ingredients.single.name, 'krompir');

    final slot = MealSlot(monday.addDays(2), MealType.lunch);
    await queue.schedule(
      'q1',
      plan: plan,
      slot: slot,
      base: await baseOf(plan),
    );
    final meal = (await plans.watchMeals(plan.id).first).singleWhere(
      (m) => m.slot == slot,
    );
    expect(meal.recipeId, isNull);
    expect(meal.snapshot!.title, 'Sarma');
  });

  test('isti zahtev dvaput: druga stavka više ne postoji', () async {
    final plan = await savedPlan();
    await queue.add(recipe('r1', 'Sarma'));
    final slot = MealSlot(monday.addDays(1), MealType.lunch);
    await queue.schedule(
      'q1',
      plan: plan,
      slot: slot,
      base: await baseOf(plan),
    );

    await expectLater(
      queue.schedule('q1', plan: plan, slot: slot, base: await baseOf(plan)),
      throwsA(isA<CookSoonItemNotFoundException>()),
    );
    expect(await plans.watchMeals(plan.id).first, hasLength(2));
  });

  test('red je odvojen po domaćinstvu', () async {
    await queue.add(recipe('r1', 'Sarma'));
    final theirs = makeQueue(other);
    expect(await theirs.watchAll().first, isEmpty);
    await expectLater(
      theirs.remove('q1'),
      throwsA(isA<CookSoonItemNotFoundException>()),
    );
    expect(await queue.watchAll().first, hasLength(1));
  });

  test('pomoćne funkcije domena', () {
    expect(cookSoonServings(0), 1);
    expect(cookSoonServings(6), 6);
    expect(cookSoonServings(40), 20);
  });
}
