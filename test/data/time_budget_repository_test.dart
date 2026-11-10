import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/recipe_repository.dart';
import 'package:tavli/data/time_budget_repository.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/domain/time_budget.dart';
import 'package:tavli/sync/synced_writer.dart';

import '../helpers/fake_photo_store.dart';

const scope = AccountScope(userId: 'u1', householdId: 'h1');

void main() {
  late AppDatabase db;
  late TimeBudgetRepository budgets;

  TimeBudgetRepository repoFor(AccountScope s) => TimeBudgetRepository(
    db,
    scope: s,
    writer: SyncedWriter(db, accountId: s.userId),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    budgets = repoFor(scope);
  });
  tearDown(() => db.close());

  Future<List<String>> outbox() async => [
    for (final r in await db.select(db.syncOutbox).get())
      '${r.entity}:${r.recordId}:${r.op}',
  ];

  test('dan se čuva, menja i briše sa outbox-om; id je po danu', () async {
    await budgets.save(const DayBudget(weekday: 2, maxActiveMinutes: 20));
    await budgets.save(
      const DayBudget(
        weekday: 2,
        maxActiveMinutes: 25,
        windowStart: 1080,
        windowEnd: 1125,
      ),
    );
    await budgets.save(const DayBudget(weekday: 7, maxActiveMinutes: 90));
    expect(await budgets.watchAll().first, [
      const DayBudget(
        weekday: 2,
        maxActiveMinutes: 25,
        windowStart: 1080,
        windowEnd: 1125,
      ),
      const DayBudget(weekday: 7, maxActiveMinutes: 90),
    ]);

    await budgets.save(const DayBudget(weekday: 2));
    expect((await budgets.watchAll().first).single.weekday, 7);
    expect(await outbox(), contains('day_time_budget:h1-2:delete'));
    expect(await outbox(), contains('day_time_budget:h1-7:upsert'));
  });

  test('neispravan unos se ne upisuje', () async {
    expect(
      () => budgets.save(
        const DayBudget(weekday: 1, windowStart: 1125, windowEnd: 1080),
      ),
      throwsArgumentError,
    );
    expect(await db.select(db.dayTimeBudgets).get(), isEmpty);
  });

  test('vreme je odvojeno po domaćinstvu', () async {
    await budgets.save(const DayBudget(weekday: 2, maxActiveMinutes: 20));
    final theirs = repoFor(const AccountScope(userId: 'u2', householdId: 'h2'));
    expect(await theirs.watchAll().first, isEmpty);
  });

  test(
    'recept čuva potvrđeno vreme; staro vreme pripreme ostaje odvojeno',
    () async {
      final recipes = RecipeRepository(
        db,
        FakePhotoStore(),
        writer: SyncedWriter(db, accountId: 'u1'),
        scope: scope,
      );
      final r = Recipe(
        id: 'r1',
        title: 'Pasulj',
        servings: 4,
        prepMinutes: 15,
        ingredients: const [Ingredient(name: 'pasulj')],
        source: RecipeSource.manual,
        createdAt: DateTime.utc(2026),
        activeMinutes: 15,
        totalMinutes: 60,
      );
      await recipes.create(r);
      final back = (await recipes.get('r1'))!;
      expect(
        (back.prepMinutes, back.activeMinutes, back.totalMinutes),
        (15, 15, 60),
      );

      final legacy = (await recipes.get('r1'))!.copyWith(clearTiming: true);
      expect(legacy.activeMinutes, isNull);
      expect(legacy.prepMinutes, 15);

      // Verzija i snimak plana nose vreme.
      final json =
          jsonDecode(jsonEncode(back.toJson())) as Map<String, dynamic>;
      expect(Recipe.fromJson(json).totalMinutes, 60);
      final snap = RecipeSnapshot.fromJson(
        jsonDecode(jsonEncode(RecipeSnapshot.fromRecipe(back).toJson()))
            as Map<String, dynamic>,
      );
      expect((snap.activeMinutes, snap.totalMinutes), (15, 60));
      // Recept bez potvrđenog vremena: JSON bez novih ključeva.
      expect(legacy.toJson().containsKey('activeMinutes'), isFalse);
    },
  );
}
