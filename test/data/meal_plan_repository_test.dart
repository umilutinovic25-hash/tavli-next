import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/meal_plan_repository.dart';
import 'package:tavli/data/recipe_repository.dart';
import 'package:tavli/data/shopping_repository.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_demand.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/sync/synced_writer.dart';

import '../helpers/fake_photo_store.dart';

const scope = AccountScope(userId: 'one', householdId: 'home-one');

/// Pada na [failAt]-tom upisu u outbox (simulira kvar usred čuvanja).
class FailingWriter extends SyncedWriter {
  FailingWriter(super.db, {required super.accountId});

  int? failAt;
  var _count = 0;

  @override
  Future<void> upsert(String entity, String id) async {
    if (failAt != null && ++_count >= failAt!) {
      throw StateError('kvar pri upisu');
    }
    return super.upsert(entity, id);
  }
}

final monday = CivilDate(2026, 11, 2);

RecipeSnapshot snapshot(String title, {double kg = 1}) => RecipeSnapshot(
  title: title,
  baseServings: 4,
  ingredients: [Ingredient(name: 'krompir', quantity: kg, unit: 'kg')],
);

/// Nacrt za [days] dana ručka: dan 1 je recept iz biblioteke "r1", ostali
/// novi recepti; [ready] ograničava koliko novih recepata ima sastojke.
PlanDraft draft({int days = 3, int? ready, PlanBase? base}) {
  final request = PlanRequest(
    range: DateRange(monday, monday.addDays(days - 1)),
    mealTypes: const {MealType.lunch},
  );
  final slots = request.slots;
  final proposals = <MealSlot, SlotProposal>{
    slots.first: const SlotProposal(title: 'Pasulj', libraryRecipeId: 'r1'),
    for (final s in slots.skip(1))
      s: SlotProposal(
        title: 'Jelo ${s.date.day}',
        draftRecipeKey: 'jelo ${s.date.day}',
      ),
  };
  final keys = [for (final s in slots.skip(1)) 'jelo ${s.date.day}'];
  return PlanDraft(
    request: request,
    proposals: proposals,
    libraryRecipes: {'r1': snapshot('Pasulj')},
    newRecipes: {
      for (final k in keys.take(ready ?? keys.length)) k: snapshot('Jelo $k'),
    },
    base: base,
  );
}

void main() {
  late AppDatabase db;
  late FailingWriter writer;
  late MealPlanRepository repo;

  MealPlanRepository makeRepo(AccountScope s, SyncedWriter w) =>
      MealPlanRepository(
        db,
        scope: s,
        writer: w,
        shopping: ShoppingRepository(db, scope: s, writer: w),
        clock: () => DateTime.utc(2026, 11, 2, 9),
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    writer = FailingWriter(db, accountId: 'one');
    repo = makeRepo(scope, writer);
    await db
        .into(db.recipes)
        .insert(
          RecipesCompanion.insert(
            id: 'r1',
            title: 'Pasulj',
            servings: 4,
            source: 'manual',
            ingredientsJson: '[]',
            stepsJson: '[]',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            householdId: const Value('home-one'),
          ),
        );
  });

  tearDown(() => db.close());

  Future<List<String>> outboxEntities() async => [
    for (final r in await (db.select(
      db.syncOutbox,
    )..orderBy([(t) => OrderingTerm.asc(t.seq)])).get())
      r.entity,
  ];

  test('odobren nacrt čuva plan, obroke sa snimkom i porcijama, '
      'nabavku i outbox redom roditelj pa dete', () async {
    final id = await repo.approve(draft());

    final plan = (await repo.watchPlans().first).single;
    expect(plan.id, id);
    expect(plan.range, DateRange(monday, monday.addDays(2)));
    expect(plan.mealTypes, {MealType.lunch});
    expect(plan.defaultServings, 2);

    final meals = await repo.watchMeals(id).first;
    expect(meals.length, 3);
    expect(meals.first.slot, MealSlot(monday, MealType.lunch));
    expect(meals.first.recipeId, 'r1');
    expect(meals.first.snapshot!.title, 'Pasulj');
    expect(meals[1].recipeId, isNotNull, reason: 'nov recept ide u Recepte');
    expect(meals[1].snapshot!.ingredients.single.name, 'krompir');
    expect(meals.every((m) => m.servings == 2), isTrue);

    // Svaki obrok: 1 kg za 4 porcije → 0,5 kg za 2; tri obroka.
    final totals = await ShoppingRepository(
      db,
      scope: scope,
      writer: writer,
    ).planTotals(id);
    expect(totals.single.baseUnit, 'g');
    expect(totals.single.openMicros, toMicros(1500));

    final entities = await outboxEntities();
    expect(entities.first, 'meal_plan');
    expect(
      entities.indexOf('meal_plan_entry'),
      lessThan(entities.indexOf('shopping_source')),
    );
    expect(entities.where((e) => e == 'meal_plan_entry').length, 3);
    expect(entities.where((e) => e == 'recipe').length, 2);
    expect(
      entities.lastIndexOf('recipe'),
      lessThan(entities.indexOf('meal_plan_entry')),
    );

    // Novi recepti su u Recepti (sažetak bez koraka), povezani sa obrokom.
    final saved = await (db.select(
      db.recipes,
    )..where((t) => t.id.isNotIn(['r1']))).get();
    expect(saved.map((r) => r.id).toSet(), {
      meals[1].recipeId,
      meals[2].recipeId,
    });
    expect(saved.every((r) => r.source == 'ai'), isTrue);
    expect(saved.every((r) => r.householdId == 'home-one'), isTrue);
    expect(saved.every((r) => r.stepsJson == '[]'), isTrue);
  });

  test('nepotpun nacrt se ne čuva bez izričitog "nepotpun plan"', () async {
    final partial = draft(ready: 1);

    await expectLater(
      repo.approve(partial),
      throwsA(isA<IncompleteDraftException>()),
    );
    expect(await db.select(db.mealPlans).get(), isEmpty);
    expect(await db.select(db.syncOutbox).get(), isEmpty);

    final id = await repo.approve(partial, allowPartial: true);
    final meals = await repo.watchMeals(id).first;
    expect(meals.map((m) => m.slot.date.day), [2, 3]);
    final plan = (await repo.watchPlans().first).single;
    expect(plan.slots.length, 3, reason: 'prazno mesto ostaje vidljivo');
  });

  test('nacrt bez ijednog spremnog obroka se ne čuva ni kao '
      'nepotpun', () async {
    final empty = PlanDraft(request: draft().request);
    await expectLater(
      repo.approve(empty, allowPartial: true),
      throwsA(isA<IncompleteDraftException>()),
    );
  });

  test('kvar usred čuvanja ne ostavlja ništa: ni plan, ni obroke, ni '
      'nabavku, ni outbox', () async {
    writer.failAt = 3;

    await expectLater(repo.approve(draft()), throwsStateError);

    expect(await db.select(db.mealPlans).get(), isEmpty);
    expect(await db.select(db.recipes).get(), hasLength(1));
    expect(await db.select(db.mealPlanEntries).get(), isEmpty);
    expect(await db.select(db.shoppingSources).get(), isEmpty);
    expect(await db.select(db.shoppingItems).get(), isEmpty);
    expect(await db.select(db.syncOutbox).get(), isEmpty);
  });

  test('odbačen nacrt ne menja ništa', () async {
    final before = await db.select(db.recipes).get();
    draft(); // nacrt postoji samo u memoriji
    expect(await db.select(db.mealPlans).get(), isEmpty);
    expect(await db.select(db.recipes).get(), before);
  });

  test('recept iz biblioteke obrisan pre odobrenja: obrok čuva snimak '
      'bez veze ka receptu', () async {
    await db.delete(db.recipes).go();

    final id = await repo.approve(draft());

    final first = (await repo.watchMeals(id).first).first;
    expect(first.recipeId, isNull);
    expect(first.snapshot!.title, 'Pasulj');
  });

  group('zastareo nacrt', () {
    test('plan promenjen posle početka nacrta se ne prepisuje', () async {
      final id = await repo.approve(draft(days: 2));
      final base = PlanBase(
        planId: id,
        fingerprint: await repo.fingerprint(id),
      );
      final meals = await repo.watchMeals(id).first;
      await (db.update(db.mealPlanEntries)
            ..where((t) => t.id.equals(meals.last.id)))
          .write(const MealPlanEntriesCompanion(servings: Value(5)));
      final outbox = (await db.select(db.syncOutbox).get()).length;

      await expectLater(
        repo.approve(draft(days: 2, base: base)),
        throwsA(isA<StaleDraftException>()),
      );
      expect((await repo.watchMeals(id).first).last.servings, 5);
      expect((await db.select(db.syncOutbox).get()).length, outbox);
    });

    test('nepromenjen plan: odobrenje menja obroke istog plana na '
        'istim mestima', () async {
      final id = await repo.approve(draft(days: 2));
      final before = await repo.watchMeals(id).first;
      final base = PlanBase(
        planId: id,
        fingerprint: await repo.fingerprint(id),
      );
      final next = draft(days: 2, base: base);
      final changed = next.copyWith(
        proposals: {
          ...next.proposals,
          next.request.slots.last: const SlotProposal(
            title: 'Gulaš',
            draftRecipeKey: 'gulaš',
          ),
        },
        newRecipes: {...next.newRecipes, 'gulaš': snapshot('Gulaš', kg: 2)},
      );

      expect(await repo.approve(changed), id);

      final after = await repo.watchMeals(id).first;
      expect(after.map((m) => m.id), before.map((m) => m.id));
      expect(after.last.snapshot!.title, 'Gulaš');
      expect(await db.select(db.mealPlans).get(), hasLength(1));
    });

    test('zaključan ili skuvan obrok se ne menja; takav nacrt je '
        'zastareo', () async {
      final id = await repo.approve(draft(days: 2));
      final meals = await repo.watchMeals(id).first;
      await (db.update(db.mealPlanEntries)
            ..where((t) => t.id.equals(meals.first.id)))
          .write(const MealPlanEntriesCompanion(isLocked: Value(true)));
      final base = PlanBase(
        planId: id,
        fingerprint: await repo.fingerprint(id),
      );

      await expectLater(
        repo.approve(draft(days: 2, base: base)),
        throwsA(isA<StaleDraftException>()),
      );
    });

    test('tuđi plan je zastareo, ne prepisuje se', () async {
      final id = await repo.approve(draft(days: 2));
      final fp = await repo.fingerprint(id);
      final other = makeRepo(
        const AccountScope(userId: 'two', householdId: 'home-two'),
        SyncedWriter(db, accountId: 'two'),
      );

      await expectLater(
        other.approve(
          draft(
            days: 2,
            base: PlanBase(planId: id, fingerprint: fp),
          ),
        ),
        throwsA(isA<StaleDraftException>()),
      );
      expect(await other.watchPlans().first, isEmpty);
    });
  });

  test('planovi su odvojeni po domaćinstvu', () async {
    final first = await repo.approve(draft());
    final second = await repo.approve(draft(days: 2));
    final other = makeRepo(
      const AccountScope(userId: 'two', householdId: 'home-two'),
      SyncedWriter(db, accountId: 'two'),
    );

    expect(await other.watchPlans().first, isEmpty);
    expect(await other.watchMeals(first).first, isEmpty);
    final ids = [for (final p in await repo.watchPlans().first) p.id];
    expect(ids.toSet(), {first, second});
  });

  test('datum obroka ne zavisi od vremenske zone uređaja', () async {
    final id = await repo.approve(draft(days: 1));
    final row = await db.select(db.mealPlanEntries).getSingle();
    expect(row.date.toUtc(), DateTime.utc(2026, 11, 2));
    expect((await repo.watchMeals(id).first).single.slot.date, monday);
    expect(
      jsonDecode(row.recipeSnapshotJson!),
      containsPair('title', 'Pasulj'),
    );
  });

  test('predlog vidi samo potvrđenu zalihu svog domaćinstva', () async {
    Future<void> pantry(
      String id,
      String name, {
      bool confirmed = true,
      String home = 'home-one',
    }) => db
        .into(db.pantryItems)
        .insert(
          PantryItemsCompanion.insert(
            id: id,
            name: name,
            category: 'ostalo',
            addedAt: DateTime.utc(2026),
            householdId: Value(home),
            confirmedAt: Value(confirmed ? DateTime.utc(2026) : null),
          ),
        );
    await pantry('a', 'pirinač');
    await pantry('b', 'brašno', confirmed: false);
    await pantry('c', 'šećer', home: 'home-two');

    expect(await repo.confirmedPantryNames(), ['pirinač']);
  });

  test('isti nov recept na više mesta je jedan recept u Receptima', () async {
    final base = draft();
    final same = base.copyWith(
      proposals: {
        for (final s in base.request.slots)
          s: const SlotProposal(title: 'Sarma', draftRecipeKey: 'sarma'),
      },
      newRecipes: {'sarma': snapshot('Sarma')},
    );

    final id = await repo.approve(same);

    final meals = await repo.watchMeals(id).first;
    expect(meals.map((m) => m.recipeId).toSet(), hasLength(1));
    final titles = [for (final r in await db.select(db.recipes).get()) r.title];
    expect(titles.where((t) => t == 'Sarma'), hasLength(1));
  });

  group('izmene obroka', () {
    late String planId;
    late List<PlannedMeal> meals;
    late ShoppingRepository shop;

    Future<int> open() async =>
        (await shop.planTotals(planId))
            .fold<int>(0, (sum, t) => sum + t.openMicros);

    Future<PlannedMeal> meal(String id) async =>
        (await repo.watchMeals(planId).first).firstWhere((m) => m.id == id);

    setUp(() async {
      shop = ShoppingRepository(db, scope: scope, writer: writer);
      planId = await repo.approve(draft());
      meals = await repo.watchMeals(planId).first;
    });

    test('porcije obroka menjaju samo njegovu potrebu', () async {
      // 3 obroka × 0,5 kg; drugi obrok na 4 porcije: 0,5 + 1 + 0,5.
      await repo.changeServings(meals[1].id, 4);

      expect((await meal(meals[1].id)).servings, 4);
      expect((await meal(meals[0].id)).servings, 2);
      expect(await open(), toMicros(2000));
      expect(() => repo.changeServings(meals[1].id, 21), throwsArgumentError);
    });

    test('zaključavanje i skuvano se čuvaju sa outbox-om', () async {
      await db.delete(db.syncOutbox).go();

      await repo.setLocked(meals[0].id, locked: true);
      expect((await meal(meals[0].id)).isLocked, isTrue);
      await repo.setLocked(meals[0].id, locked: false);
      expect((await meal(meals[0].id)).isLocked, isFalse);

      final outbox = await db.select(db.syncOutbox).get();
      expect(outbox.map((r) => (r.entity, r.recordId)).toSet(), {
        ('meal_plan_entry', meals[0].id),
      });
    });

    test('skuvan obrok više ne traži kupovinu i ne menja se', () async {
      await repo.setCooked(meals[2].id, cooked: true);

      expect((await meal(meals[2].id)).isCooked, isTrue);
      expect(await open(), toMicros(1000));
      await expectLater(
        repo.changeServings(meals[2].id, 4),
        throwsA(isA<ProtectedMealException>()),
      );

      // Izričito vraćanje ponovo otvara potrebu.
      await repo.setCooked(meals[2].id, cooked: false);
      expect(await open(), toMicros(1500));
    });

    test('uklonjen obrok oslobađa svoju potrebu; ostali ostaju', () async {
      await repo.removeMeal(meals[1].id);

      final left = await repo.watchMeals(planId).first;
      expect(left.map((m) => m.id), [meals[0].id, meals[2].id]);
      expect(await open(), toMicros(1000));
      final deletes = await (db.select(
        db.syncOutbox,
      )..where((r) => r.op.equals(OutboxOp.delete))).get();
      expect(deletes.last.entity, 'meal_plan_entry');
      expect(deletes.map((d) => d.entity), contains('shopping_source'));
    });

    test('zamena jela čuva id i porcije obroka, menja snimak i '
        'nabavku', () async {
      await repo.changeServings(meals[1].id, 4);
      final plan = (await repo.watchPlans().first).single;
      final slot = meals[1].slot;
      final replacement = PlanDraft(
        request: PlanRequest(
          range: plan.range,
          mealTypes: plan.mealTypes,
          only: {slot},
        ),
        proposals: {
          slot: const SlotProposal(title: 'Gulaš', draftRecipeKey: 'gulaš'),
        },
        newRecipes: {'gulaš': snapshot('Gulaš', kg: 2)},
        base: PlanBase(
          planId: planId,
          fingerprint: await repo.fingerprint(planId),
        ),
      );

      await repo.approve(replacement);

      final after = await repo.watchMeals(planId).first;
      expect(after.map((m) => m.id), meals.map((m) => m.id));
      expect(after[1].snapshot!.title, 'Gulaš');
      expect(after[1].servings, 4, reason: 'porcije obroka ostaju');
      expect(after[0].snapshot!.title, 'Pasulj');
      // 0,5 + 2 kg × 4/4 + 0,5.
      expect(await open(), toMicros(3000));
    });

    test('zaključan obrok se ne može zameniti ni ukloniti', () async {
      await repo.setLocked(meals[1].id, locked: true);

      await expectLater(
        repo.removeMeal(meals[1].id),
        throwsA(isA<ProtectedMealException>()),
      );
      expect(await repo.watchMeals(planId).first, hasLength(3));
    });

    test('izmena recepta u biblioteci ne menja odobren obrok; brisanje '
        'ostavlja snimak', () async {
      await (db.update(db.recipes)..where((t) => t.id.equals('r1'))).write(
        const RecipesCompanion(title: Value('Pasulj prebranac')),
      );
      expect((await meal(meals[0].id)).snapshot!.title, 'Pasulj');

      await RecipeRepository(
        db,
        FakePhotoStore(),
        writer: writer,
        scope: scope,
      ).delete('r1');

      final first = await meal(meals[0].id);
      expect(first.recipeId, isNull);
      expect(first.snapshot!.title, 'Pasulj');
      expect(first.servings, 2);
    });

    test('tuđi obrok se ne menja', () async {
      final other = makeRepo(
        const AccountScope(userId: 'two', householdId: 'home-two'),
        SyncedWriter(db, accountId: 'two'),
      );
      await expectLater(
        other.setLocked(meals[0].id, locked: true),
        throwsA(isA<MealNotFoundException>()),
      );
      expect((await meal(meals[0].id)).isLocked, isFalse);
    });

    group('obrok van kuće', () {
      Future<int> bought() async =>
          (await shop.planTotals(planId))
              .fold<int>(0, (sum, t) => sum + t.boughtMicros);

      test('restoran zauzima mesto i oslobađa samo potrebu tog obroka; '
          'jelo može da se vrati', () async {
        await repo.setAway(
          planId,
          meals[1].slot,
          AwayReason.restaurant,
          note: '  sa kolegama ',
        );

        final away = await meal(meals[1].id);
        expect(away.isAway, isTrue);
        expect(away.awayReason, AwayReason.restaurant);
        expect(away.awayNote, 'sa kolegama');
        expect(away.snapshot, isNotNull);
        expect(await open(), toMicros(1000));
        final sources = await db.select(db.shoppingSources).get();
        expect(sources.map((s) => s.planEntryId), isNot(contains(away.id)));

        await repo.restoreMeal(away.id);
        final back = await meal(meals[1].id);
        expect(back.isAway, isFalse);
        expect(back.awayReason, isNull);
        expect(await open(), toMicros(1500));
      });

      test('kupljeno ostaje kad obrok postane van kuće', () async {
        final items = [
          for (final t in await shop.planTotals(planId)) ...t.itemIds,
        ];
        await shop.setBought(items, bought: true);
        expect(await bought(), toMicros(1500));

        await repo.setAway(planId, meals[0].slot, AwayReason.visiting);

        expect(await bought(), toMicros(1500));
        expect(await open(), 0);
      });

      test('prazno mesto: obrok van kuće bez recepta, 0 potražnje', () async {
        final plan = (await repo.watchPlans().first).single;
        await repo.removeMeal(meals[2].id);
        final before = await db.select(db.shoppingContributions).get();

        await repo.setAway(planId, meals[2].slot, AwayReason.skip);

        final away = (await repo.watchMeals(planId).first).singleWhere(
          (m) => m.slot == meals[2].slot,
        );
        expect(away.isAway, isTrue);
        expect(away.snapshot, isNull);
        expect(away.recipeId, isNull);
        expect(
          (await db.select(db.shoppingContributions).get()).length,
          before.length,
        );
        expect(
          regenerableSlots(plan, [away], monday),
          isNot(contains(away.slot)),
        );
        await expectLater(
          repo.restoreMeal(away.id),
          throwsA(isA<MealNotFoundException>()),
        );
        await repo.removeMeal(away.id);
        expect(await repo.watchMeals(planId).first, hasLength(2));
      });

      test(
        'zaključan obrok ne postaje van kuće; tuđi plan ne postoji',
        () async {
          await repo.setLocked(meals[0].id, locked: true);
          await expectLater(
            repo.setAway(planId, meals[0].slot, AwayReason.restaurant),
            throwsA(isA<ProtectedMealException>()),
          );
          final theirs = makeRepo(
            const AccountScope(userId: 'two', householdId: 'home-two'),
            writer,
          );
          await expectLater(
            theirs.setAway(planId, meals[1].slot, AwayReason.restaurant),
            throwsA(isA<MealNotFoundException>()),
          );
          expect(
            () => repo.setAway(
              planId,
              meals[1].slot,
              AwayReason.restaurant,
              note: 'x' * 81,
            ),
            throwsArgumentError,
          );
        },
      );

      test('stari nečitljiv snimak nije obrok van kuće', () async {
        await (db.update(
          db.mealPlanEntries,
        )..where((t) => t.id.equals(meals[0].id))).write(
          const MealPlanEntriesCompanion(
            recipeSnapshotJson: Value('{pokvareno'),
          ),
        );
        final m = await meal(meals[0].id);
        expect(m.isAway, isFalse);
        expect(m.snapshot, isNull);
      });

      test('izričita zamena receptom vraća obrok u kuvanje', () async {
        await repo.setAway(planId, meals[1].slot, AwayReason.restaurant);
        final plan = (await repo.watchPlans().first).single;
        final base = PlanBase(
          planId: planId,
          fingerprint: await repo.fingerprint(planId),
        );
        final request = PlanRequest(
          range: plan.range,
          mealTypes: plan.mealTypes,
          only: {meals[1].slot},
        );
        await repo.approve(
          PlanDraft(
            request: request,
            proposals: {
              meals[1].slot: const SlotProposal(
                title: 'Pasulj',
                libraryRecipeId: 'r1',
              ),
            },
            libraryRecipes: {'r1': snapshot('Pasulj')},
            base: base,
          ),
        );
        final m = await meal(meals[1].id);
        expect(m.isAway, isFalse);
        expect(m.awayReason, isNull);
        expect(m.snapshot!.title, 'Pasulj');
        // Pasulj: 1 kg za 4 porcije, obrok zadržava 2 → 0,5 + 0,5 + 0,5.
        expect(await open(), toMicros(1500));
      });
    });

    test('mesta za ponovni predlog: bez zaključanih, skuvanih i '
        'prošlih', () async {
      await repo.setLocked(meals[1].id, locked: true);
      final plan = (await repo.watchPlans().first).single;
      final current = await repo.watchMeals(planId).first;

      // Sutra: današnji obrok je prošao.
      final slots = regenerableSlots(plan, current, monday.addDays(1));

      expect(slots, {meals[2].slot});
    });
  });
}
