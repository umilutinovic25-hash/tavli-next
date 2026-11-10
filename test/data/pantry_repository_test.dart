import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/pantry_repository.dart';
import 'package:tavli/data/shopping_repository.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_demand.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/sync/synced_writer.dart';

void main() {
  const home = AccountScope(userId: 'one', householdId: 'home-one');
  final now = DateTime.utc(2026, 11, 2, 9);
  late AppDatabase db;
  late ShoppingRepository shop;
  late PantryRepository pantry;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final writer = SyncedWriter(db, accountId: 'one', clock: () => now);
    shop = ShoppingRepository(
      db,
      scope: home,
      writer: writer,
      clock: () => now,
    );
    pantry = PantryRepository(
      db,
      scope: home,
      writer: writer,
      shopping: shop,
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  test('CRUD: domaćinstvo, outbox, potvrda i provera količine', () async {
    final id = await pantry.create(
      name: '  Pirinač  ',
      quantity: 1.5,
      unit: 'kg',
    );
    var row = (await pantry.watchItems().first).single;
    expect(row.id, id);
    expect(row.name, 'Pirinač');
    expect(row.householdId, home.householdId);
    expect(row.confirmedAt!.isAtSameMomentAs(now), isTrue);
    await pantry.update(id, name: 'Pirinač');
    row = (await pantry.watchItems().first).single;
    expect(row.quantity, isNull);
    expect(row.unit, isNull);
    expect(row.confirmedAt, isNull);
    for (final value in [-1.0, 0.0, double.nan, double.infinity]) {
      expect(
        () => pantry.create(name: 'So', quantity: value),
        throwsArgumentError,
      );
    }
    expect(() => pantry.create(name: ' '), throwsArgumentError);
    await pantry.remove(id);
    expect(await pantry.watchItems().first, isEmpty);
    final outbox = await (db.select(
      db.syncOutbox,
    )..where((t) => t.entity.equals('pantry_item'))).get();
    expect(outbox.single.recordId, id);
    expect(outbox.single.op, OutboxOp.delete);
  });

  test('tuđa zaliha ne može da se čita, menja ili ukloni', () async {
    final id = await pantry.create(name: 'So', quantity: 10);
    final otherShop = ShoppingRepository(
      db,
      scope: const AccountScope(userId: 'two', householdId: 'home-two'),
      writer: SyncedWriter(db, accountId: 'two'),
    );
    final other = PantryRepository(
      db,
      scope: const AccountScope(userId: 'two', householdId: 'home-two'),
      writer: SyncedWriter(db, accountId: 'two'),
      shopping: otherShop,
    );
    expect(await other.watchItems().first, isEmpty);
    expect(
      () => other.update(id, name: 'Tuđe'),
      throwsA(isA<PantryItemMissing>()),
    );
    expect(() => other.remove(id), throwsA(isA<PantryItemMissing>()));
    expect((await pantry.watchItems().first).single.name, 'So');
  });

  test(
    'promena naziva ili jedinice ne zadržava pokriće prethodne namirnice',
    () async {
      await shop.addRecipePreparation(
        snapshot: const RecipeSnapshot(
          title: 'Ručak',
          baseServings: 2,
          ingredients: [Ingredient(name: 'Pirinač', quantity: 1, unit: 'kg')],
        ),
        servings: 2,
        originKey: 'test',
      );
      final id = await pantry.create(name: 'Pirinač', quantity: 1, unit: 'kg');
      expect(
        (await shop.watchRecipeItems().first).where((r) => !r.isBought),
        isEmpty,
      );
      await pantry.update(id, name: 'So', quantity: 1, unit: 'kg');
      expect(
        (await shop.watchRecipeItems().first)
            .where((r) => !r.isBought)
            .single
            .name,
        'Pirinač',
      );
      await pantry.update(id, name: 'Pirinač', quantity: 1, unit: 'l');
      expect(
        (await shop.watchRecipeItems().first)
            .where((r) => !r.isBought)
            .single
            .name,
        'Pirinač',
      );
    },
  );

  test(
    'uklonjena primljena kupovina sa nepoznatom količinom ponovo traži proveru',
    () async {
      await shop.addRecipePreparation(
        snapshot: const RecipeSnapshot(
          title: 'Jelo',
          baseServings: 2,
          ingredients: [Ingredient(name: 'So')],
        ),
        servings: 2,
        originKey: 'test',
      );
      final purchase = (await shop.watchRecipeItems().first).single;
      await shop.setBought([purchase.id], bought: true);
      await pantry.receivePurchases([purchase.id]);
      final row = (await pantry.watchItems().first).single;
      await pantry.remove(row.id);
      expect(
        (await shop.watchRecipeItems().first)
            .where((r) => !r.isBought)
            .single
            .name,
        'So',
      );
    },
  );

  test('greška outbox-a vraća i podatak i postojeću nabavku', () async {
    await shop.addRecipePreparation(
      snapshot: const RecipeSnapshot(
        title: 'Ručak',
        baseServings: 2,
        ingredients: [Ingredient(name: 'Pirinač', quantity: 1, unit: 'kg')],
      ),
      servings: 2,
      originKey: 'test',
    );
    final before = (await shop.watchRecipeItems().first).single;
    // Greška tokom preračuna, posle upisa Ostave i njene outbox operacije.
    await db.delete(db.syncOutbox).go();
    await db.customStatement(
      "CREATE TRIGGER reject_pantry_outbox BEFORE INSERT ON sync_outbox WHEN NEW.entity = 'shopping_item' BEGIN SELECT RAISE(ABORT, 'test'); END",
    );
    await expectLater(
      pantry.create(name: 'Pirinač', quantity: 0.25, unit: 'kg'),
      throwsException,
    );
    expect(await pantry.watchItems().first, isEmpty);
    expect(await db.select(db.syncOutbox).get(), isEmpty);
    final after = (await shop.watchRecipeItems().first).single;
    expect(after.id, before.id);
    expect(after.quantity, before.quantity);
    expect(after.unit, before.unit);
  });

  test(
    '1 kg potrebe − 0,25 kg zalihe = 750 g nabavke; izmena i uklanjanje uživo',
    () async {
      await shop.addRecipePreparation(
        snapshot: const RecipeSnapshot(
          title: 'Ručak',
          baseServings: 2,
          ingredients: [Ingredient(name: 'Pirinač', quantity: 1, unit: 'kg')],
        ),
        servings: 2,
        originKey: 'test',
      );
      Future<double> needed() async {
        final row = (await shop.watchRecipeItems().first)
            .where((r) => !r.isBought)
            .single;
        return row.quantity! * normalizeUnit(row.unit).factor;
      }

      final id = await pantry.create(
        name: 'Pirinač',
        quantity: 0.25,
        unit: 'kg',
      );
      expect(await needed(), 750);
      await pantry.update(id, name: 'Pirinač', quantity: 500, unit: 'g');
      expect(await needed(), 500);
      await pantry.remove(id);
      expect(await needed(), 1000);
    },
  );

  test('primljena kupovina: izmena, nepoznato, rok i uklanjanje ne vraćaju staru zalihu', () async {
    final list = await shop.recipeList();
    final purchase = await shop.addManual(
      list,
      'Pirinač',
      quantity: 1,
      unit: 'kg',
    );
    await shop.setBought([purchase], bought: true);
    await pantry.receivePurchases([purchase]);
    final row = (await pantry.watchItems().first).single;
    await shop.addRecipePreparation(
      snapshot: const RecipeSnapshot(
        title: 'Ručak',
        baseServings: 2,
        ingredients: [Ingredient(name: 'Pirinač', quantity: 1, unit: 'kg')],
      ),
      servings: 2,
      originKey: 'test',
    );
    Future<double> needed() async {
      final row = (await shop.watchRecipeItems().first)
          .where((r) => !r.isBought)
          .single;
      return row.quantity! * normalizeUnit(row.unit).factor;
    }

    await pantry.update(row.id, name: 'Pirinač', quantity: 0.25, unit: 'kg');
    expect(await needed(), 750);
    await pantry.update(row.id, name: 'Pirinač', unit: 'kg');
    expect(await needed(), 1000);
    await pantry.update(
      row.id,
      name: 'Pirinač',
      quantity: 1,
      unit: 'kg',
      expiresAt: now.subtract(const Duration(days: 1)),
    );
    expect(await needed(), 1000);
    await pantry.remove(row.id);
    expect(await needed(), 1000);
    expect(await pantry.watchItems().first, isEmpty);
    expect(await pantry.receivePurchases([purchase]), 0);
    expect(await pantry.watchReceivedItemIds().first, {purchase});
    expect(await shop.setBought([purchase], bought: false), 0);
  });

  test(
    'prijem kupljenog: potvrđena zaliha vezana za kupovinu, jednom',
    () async {
      final list = await shop.recipeList();
      final mleko = await shop.addManual(
        list,
        'Mleko',
        quantity: 1,
        unit: 'l',
        category: 'mlečni proizvodi i jaja',
      );
      final hleb = await shop.addManual(list, 'Hleb');

      // Nekupljeno se ne prima.
      expect(await pantry.receivePurchases([mleko]), 0);
      await shop.setBought([mleko, hleb], bought: true);
      expect(await pantry.receivePurchases([mleko, mleko, hleb]), 2);
      expect(await pantry.receivePurchases([mleko]), 0);

      final rows = await db.select(db.pantryItems).get();
      final milk = rows.firstWhere((r) => r.name == 'Mleko');
      expect(milk.quantity, 1);
      expect(milk.unit, 'l');
      expect(milk.category, 'mlečni proizvodi i jaja');
      expect(milk.confirmedAt!.isAtSameMomentAs(now), isTrue);
      expect(milk.sourceShoppingItemId, mleko);
      expect(milk.householdId, 'home-one');
      expect(await pantry.watchReceivedItemIds().first, {mleko, hleb});

      final outbox = await (db.select(
        db.syncOutbox,
      )..where((t) => t.entity.equals('pantry_item'))).get();
      expect(outbox, hasLength(2));
    },
  );

  test('druga osoba ne prima tuđu kupovinu', () async {
    final list = await shop.recipeList();
    final id = await shop.addManual(list, 'Mleko');
    await shop.setBought([id], bought: true);
    final other = PantryRepository(
      db,
      scope: const AccountScope(userId: 'two', householdId: 'home-two'),
      writer: SyncedWriter(db, accountId: 'two'),
      shopping: ShoppingRepository(
        db,
        scope: const AccountScope(userId: 'two', householdId: 'home-two'),
        writer: SyncedWriter(db, accountId: 'two'),
      ),
    );
    expect(await other.receivePurchases([id]), 0);
    expect(await other.watchReceivedItemIds().first, isEmpty);
    expect(await db.select(db.pantryItems).get(), isEmpty);
  });
}
