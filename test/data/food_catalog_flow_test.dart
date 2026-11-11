import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/meal_plan_repository.dart';
import 'package:tavli/data/shopping_repository.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/sync/synced_writer.dart';

/// 036 SC-001 kroz plan: recept A (4 porcije) „jaja 3 kom“ i recept B
/// (2 porcije) „jaje 2 kom“, oba za 2 porcije, i potvrđena zaliha „jajce
/// 2 kom“. Potreba 1,5 + 2 = 3,5 kom, zaliha pokriva 2 → jedna stavka
/// „jaje“ 1,5 kom. Bez kataloga: dve stavke, zaliha ne pokriva ništa.
const scope = AccountScope(userId: 'one', householdId: 'home-one');
final monday = CivilDate(2026, 11, 2);

void main() {
  late AppDatabase db;
  late MealPlanRepository plans;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final writer = SyncedWriter(db, accountId: 'one');
    plans = MealPlanRepository(
      db,
      scope: scope,
      writer: writer,
      shopping: ShoppingRepository(db, scope: scope, writer: writer),
      clock: () => DateTime.utc(2026, 11, 1, 9),
    );
    for (final id in ['ra', 'rb']) {
      await db
          .into(db.recipes)
          .insert(
            RecipesCompanion.insert(
              id: id,
              title: id,
              servings: 2,
              source: 'manual',
              ingredientsJson: '[]',
              stepsJson: '[]',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
              householdId: const Value('home-one'),
            ),
          );
    }
  });
  tearDown(() => db.close());

  Future<void> catalog() async {
    await db
        .into(db.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'f_jaje',
            name: 'jaje',
            category: 'mlečni proizvodi i jaja',
            baseUnit: 'kom',
          ),
        );
    for (final a in ['jaje', 'jaja', 'jajce']) {
      await db
          .into(db.foodAliases)
          .insert(
            FoodAliasesCompanion.insert(
              id: 'f_jaje:$a',
              foodId: 'f_jaje',
              alias: a,
            ),
          );
    }
  }

  Future<void> jajce({String? foodId}) => db
      .into(db.pantryItems)
      .insert(
        PantryItemsCompanion.insert(
          id: 'ostava',
          name: 'jajce',
          quantity: const Value(2),
          unit: const Value('kom'),
          category: 'mlečni proizvodi i jaja',
          addedAt: DateTime.utc(2026, 10, 30),
          confirmedAt: Value(DateTime.utc(2026, 10, 30)),
          householdId: const Value('home-one'),
          foodId: Value(foodId),
        ),
      );

  Future<List<String>> openItems() async => [
    for (final i in await (db.select(
      db.shoppingItems,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).get())
      if (!i.isBought) '${i.name} ${i.quantity} ${i.unit} ${i.foodId}',
  ];

  Future<void> approvePlan() async {
    final request = PlanRequest(
      range: DateRange(monday, monday.addDays(1)),
      mealTypes: const {MealType.lunch},
    );
    final slots = request.slots;
    await plans.approve(
      PlanDraft(
        request: request,
        proposals: {
          slots.first: const SlotProposal(title: 'A', libraryRecipeId: 'ra'),
          slots.last: const SlotProposal(title: 'B', libraryRecipeId: 'rb'),
        },
        libraryRecipes: const {
          'ra': RecipeSnapshot(
            title: 'A',
            baseServings: 4,
            ingredients: [Ingredient(name: 'jaja', quantity: 3, unit: 'kom')],
          ),
          'rb': RecipeSnapshot(
            title: 'B',
            baseServings: 2,
            ingredients: [Ingredient(name: 'jaje', quantity: 2, unit: 'kom')],
          ),
        },
      ),
    );
  }

  test('SC-001: jedna stavka „jaje“ 1,5 kom', () async {
    await catalog();
    await jajce(foodId: 'f_jaje');
    await approvePlan();
    expect(await openItems(), ['jaje 1.5 kom f_jaje']);
  });

  test('kontrola bez kataloga: dve stavke, zaliha ne pokriva', () async {
    await jajce();
    await approvePlan();
    expect(await openItems(), ['jaja 1.5 kom null', 'jaje 2.0 kom null']);
  });
}
