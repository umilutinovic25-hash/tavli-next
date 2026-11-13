import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/meal_plan_repository.dart';
import 'package:tavli/data/shopping_repository.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/features/recipes/cooking_screen.dart';
import 'package:tavli/features/recipes/keep_screen_on.dart';
import 'package:tavli/features/recipes/recipe_providers.dart';
import 'package:tavli/providers.dart';
import 'package:tavli/sync/synced_writer.dart';

import '../../helpers/test_app.dart';

CheckboxListTile checkbox(WidgetTester tester, String label) => tester.widget(
  find.ancestor(of: find.text(label), matching: find.byType(CheckboxListTile)),
);

class DelayedWakeLock implements ScreenWakeLock {
  final calls = <String>[];
  final firstEnable = Completer<void>();

  @override
  Future<void> enable() async {
    calls.add('enable');
    if (calls.length == 1) await firstEnable.future;
  }

  @override
  Future<void> disable() async => calls.add('disable');
}

Future<void> tapLabel(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('zahtevi za ekran se izvršavaju redom pri brzoj zameni', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final lock = DelayedWakeLock();
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(key: 'keep_screen_on', value: 'true'),
        );
    Widget app(Key? key) => ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        screenWakeLockProvider.overrideWithValue(lock),
      ],
      child: MaterialApp(
        home: key == null
            ? const SizedBox()
            : KeepScreenOnScope(key: key, child: const SizedBox()),
      ),
    );
    await tester.pumpWidget(app(const ValueKey('first')));
    await tester.pumpAndSettle();
    expect(lock.calls, ['enable']);
    await tester.pumpWidget(app(null));
    await tester.pumpWidget(app(const ValueKey('second')));
    await tester.pump();
    expect(lock.calls, ['enable']);
    lock.firstEnable.complete();
    await tester.pumpAndSettle();
    expect(lock.calls, ['enable', 'disable', 'enable']);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(lock.calls.last, 'disable');
    await db.close();
  });

  testWidgets('preklopljeni prikazi ne oslobađaju tuđi zahtev', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final lock = DelayedWakeLock()..firstEnable.complete();
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(key: 'keep_screen_on', value: 'true'),
        );
    Widget app(bool first, bool second) => ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        screenWakeLockProvider.overrideWithValue(lock),
      ],
      child: MaterialApp(
        home: Column(
          children: [
            if (first)
              const KeepScreenOnScope(key: ValueKey('one'), child: SizedBox()),
            if (second)
              const KeepScreenOnScope(key: ValueKey('two'), child: SizedBox()),
          ],
        ),
      ),
    );
    await tester.pumpWidget(app(true, true));
    await tester.pumpAndSettle();
    expect(lock.calls, ['enable']);
    await tester.pumpWidget(app(false, true));
    await tester.pumpAndSettle();
    expect(lock.calls, ['enable']);
    await tester.pumpWidget(app(false, false));
    await tester.pumpAndSettle();
    expect(lock.calls, ['enable', 'disable']);
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });

  for (final size in [const Size(320, 800), wide]) {
    testTavli('kuvanje recepta je privremeno i radi na $size', (tester) async {
      final recipe = sampleRecipe('a', 'Sarma');
      final app = await pumpTavli(
        tester,
        size: size,
        location: '/recipes/a',
        recipes: [recipe],
        settings: {'keep_screen_on': 'true'},
        setup: (db) async {
          await db
              .into(db.pantryItems)
              .insert(
                PantryItemsCompanion.insert(
                  id: 'p',
                  name: 'kupus',
                  quantity: const Value(2),
                  category: 'ostalo',
                  addedAt: DateTime.utc(2026),
                ),
              );
        },
      );
      final original = (await app.repo.get('a'))!.toJson();
      final pantry = await app.db.select(app.db.pantryItems).get();
      expect(app.wakeLock.on, isTrue);
      await tapLabel(tester, 'Kreni sa kuvanjem');
      expect(find.byType(CookingScreen), findsOneWidget);
      expect(app.wakeLock.on, isTrue);
      expect(find.byType(KeepScreenOnButton), findsOneWidget);
      await tapLabel(tester, '0,5 kg kupus');
      expect(checkbox(tester, '0,5 kg kupus').value, isTrue);
      await tapLabel(tester, 'Umotati.');
      expect(checkbox(tester, 'Umotati.').value, isTrue);
      await tapLabel(tester, 'Sledeći');
      expect(find.text('Korak 2 od 2'), findsOneWidget);
      await tapLabel(tester, 'Kuvati.');
      await tapLabel(tester, 'Prethodni');
      expect(checkbox(tester, 'Umotati.').value, isTrue);
      await tapLabel(tester, 'Umotati.');
      expect(checkbox(tester, 'Umotati.').value, isFalse);
      expect((await app.repo.get('a'))!.toJson(), original);
      expect(await app.db.select(app.db.pantryItems).get(), pantry);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(app.wakeLock.on, isTrue); // The recipe is still open.
      await tapLabel(tester, 'Kreni sa kuvanjem');
      expect(checkbox(tester, '0,5 kg kupus').value, isFalse);
      expect(checkbox(tester, 'Umotati.').value, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(app.wakeLock.on, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testTavli('plan koristi odobreni snimak i porcije, bez izvornog recepta', (
    tester,
  ) async {
    final day = CivilDate(2026, 11, 4);
    final app = await pumpTavli(
      tester,
      location: '/plan',
      settings: {'keep_screen_on': 'true'},
      overrides: [clockProvider.overrideWithValue(() => DateTime(2026, 11, 4))],
      setup: (db) async {
        final account = await db.select(db.accounts).getSingle();
        final scope = AccountScope(
          userId: account.userId,
          householdId: account.householdId,
        );
        final writer = SyncedWriter(db, accountId: scope.userId);
        final repo = MealPlanRepository(
          db,
          scope: scope,
          writer: writer,
          shopping: ShoppingRepository(db, scope: scope, writer: writer),
        );
        final request = PlanRequest(
          range: DateRange(day, day),
          mealTypes: const {MealType.lunch},
          servings: 4,
        );
        final slot = request.slots.single;
        await repo.approve(
          PlanDraft(
            request: request,
            proposals: {
              slot: const SlotProposal(
                title: 'Snimak',
                draftRecipeKey: 'snimak',
              ),
            },
            newRecipes: {
              'snimak': const RecipeSnapshot(
                title: 'Snimak',
                baseServings: 2,
                ingredients: [
                  Ingredient(name: 'brašno', quantity: 300, unit: 'g'),
                ],
                steps: ['Promešati.'],
              ),
            },
          ),
        );
      },
    );
    await tapLabel(tester, 'Snimak');
    await tapLabel(tester, 'Kreni sa kuvanjem');
    expect(find.text('600 g brašno'), findsOneWidget);
    expect(find.text('Promešati.'), findsOneWidget);
    expect(app.wakeLock.on, isTrue);
    await tapLabel(tester, 'Promešati.');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(app.wakeLock.on, isFalse);
  });

  testTavli('recept bez koraka nema prazan deo Priprema, sastojci ostaju', (
    tester,
  ) async {
    await pumpTavli(
      tester,
      location: '/recipes/a',
      recipes: [sampleRecipe('a', 'Sarma').copyWith(steps: [])],
    );
    await tapLabel(tester, 'Kreni sa kuvanjem');
    expect(find.text('Priprema'), findsNothing);
    expect(find.text('Koraci pripreme nisu uneti.'), findsNothing);
    expect(find.text('Sledeći'), findsNothing);
    expect(find.textContaining('kupus'), findsOneWidget);
  });

  testTavli('recept sa više od 20 porcija zadržava originalne količine', (
    tester,
  ) async {
    await pumpTavli(
      tester,
      location: '/recipes/a',
      recipes: [sampleRecipe('a', 'Sarma').copyWith(servings: 25)],
    );
    await tapLabel(tester, 'Kreni sa kuvanjem');
    expect(find.text('25 porcija'), findsOneWidget);
    expect(find.text('0,5 kg kupus'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testTavli('telefon sa uvećanim tekstom i opcijom ekrana', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final app = await pumpTavli(
      tester,
      size: const Size(320, 800),
      location: '/recipes/a',
      recipes: [sampleRecipe('a', 'Sarma')],
    );
    await tapLabel(tester, 'Kreni sa kuvanjem');
    await tester.tap(find.byType(KeepScreenOnButton));
    await tester.pumpAndSettle();
    expect(app.wakeLock.on, isTrue);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tapLabel(tester, 'Sledeći');
    expect(find.text('Kuvati.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
