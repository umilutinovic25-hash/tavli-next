import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/meal_plan_repository.dart';
import 'package:tavli/data/shopping_repository.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_demand.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/sync/synced_writer.dart';

void main() {
  test(
    'šablon čuva snimak i pravi nove obroke i nabavku po porcijama',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const scope = AccountScope(userId: 'one', householdId: 'home');
      final writer = SyncedWriter(db, accountId: 'one');
      final shopping = ShoppingRepository(db, scope: scope, writer: writer);
      final repo = MealPlanRepository(
        db,
        scope: scope,
        writer: writer,
        shopping: shopping,
      );
      final monday = CivilDate(2026, 11, 2);
      final slot = MealSlot(monday.addDays(1), MealType.lunch);
      final request = PlanRequest(
        range: DateRange(monday, monday.addDays(6)),
        mealTypes: {MealType.lunch},
        servings: 4,
        usePantry: false,
      );
      final original = await repo.approve(
        PlanDraft(
          request: request,
          proposals: {
            slot: const SlotProposal(title: 'Jelo', libraryRecipeId: 'missing'),
          },
          libraryRecipes: {
            'missing': const RecipeSnapshot(
              title: 'Jelo',
              baseServings: 4,
              ingredients: [
                Ingredient(name: 'brašno', quantity: 1, unit: 'kg'),
              ],
            ),
          },
        ),
        allowPartial: true,
      );
      final originalMeal = (await repo.watchMeals(original).first).single;
      final templateId = await repo.saveWeekTemplate(
        original,
        monday,
        'Omiljena',
      );
      await repo.changeServings(originalMeal.id, 2);
      final oldItem = (await db.select(db.shoppingItems).get()).single;
      expect(await shopping.setBought([oldItem.id], bought: true), 1);
      final purchasedBefore = (await db.select(db.shoppingItems).get()).single;
      final template = (await repo.watchWeekTemplates().first).single;
      expect(template.id, templateId);
      final newMonday = CivilDate(2026, 12, 7);
      final copied = await repo.applyWeekTemplate(templateId, newMonday, 8);
      final meal = (await repo.watchMeals(copied).first).single;
      expect(copied, isNot(original));
      expect(meal.id, isNot(originalMeal.id));
      expect(meal.slot, MealSlot(newMonday.addDays(1), MealType.lunch));
      expect(meal.servings, 8);
      expect(meal.snapshot!.title, 'Jelo');
      expect(meal.isCooked, isFalse);
      expect(
        (await shopping.planTotals(copied)).single.openMicros,
        toMicros(2000),
      );
      expect((await repo.watchMeals(original).first).single.servings, 2);
      final purchasedAfter = await (db.select(
        db.shoppingItems,
      )..where((t) => t.id.equals(oldItem.id))).getSingle();
      expect(purchasedAfter.isBought, isTrue);
      expect(purchasedAfter.quantity, purchasedBefore.quantity);
      expect(
        purchasedAfter.purchaseProvenanceJson,
        purchasedBefore.purchaseProvenanceJson,
      );
      final another = await repo.applyWeekTemplate(templateId, newMonday, 8);
      expect(another, isNot(copied));
      expect((await repo.watchMeals(another).first).single.id, isNot(meal.id));
      expect(
        (await db.select(db.syncOutbox).get()).where(
          (e) => e.entity == 'week_template' && e.recordId == templateId,
        ),
        hasLength(1),
      );
      final others = MealPlanRepository(
        db,
        scope: const AccountScope(userId: 'two', householdId: 'other'),
        writer: SyncedWriter(db, accountId: 'two'),
        shopping: ShoppingRepository(
          db,
          scope: const AccountScope(userId: 'two', householdId: 'other'),
          writer: SyncedWriter(db, accountId: 'two'),
        ),
      );
      expect(await others.watchWeekTemplates().first, isEmpty);
      await expectLater(
        others.applyWeekTemplate(templateId, newMonday, 8),
        throwsA(isA<Exception>()),
      );
    },
  );
}
