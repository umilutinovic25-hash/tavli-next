import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
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

  test('brza provera čuva metapodatke i datum i nepoznate količine', () async {
    final expiry = now.add(const Duration(days: 3));
    final id = await pantry.create(
      name: 'Mleko',
      quantity: 1,
      unit: 'l',
      category: 'mlečni proizvodi i jaja',
      expiresAt: expiry,
    );
    final checked = now.add(const Duration(days: 1));
    pantry = PantryRepository(
      db,
      scope: home,
      writer: SyncedWriter(db, accountId: 'one'),
      shopping: shop,
      clock: () => checked,
    );
    await pantry.checkQuantity(id, quantity: 0.5, unit: 'l');
    var row = (await pantry.watchItems().first).single;
    expect(row.quantity, 0.5);
    expect(row.name, 'Mleko');
    expect(row.category, 'mlečni proizvodi i jaja');
    expect(row.expiresAt!.isAtSameMomentAs(expiry), isTrue);
    await pantry.checkQuantity(id, quantity: null);
    row = (await pantry.watchItems().first).single;
    expect(row.quantity, isNull);
    expect(row.unit, 'l');
    expect(row.confirmedAt!.isAtSameMomentAs(checked), isTrue);
    final outbox = await (db.select(
      db.syncOutbox,
    )..where((t) => t.entity.equals('pantry_item'))).get();
    expect(outbox.single.recordId, id);
    expect(outbox.single.op, OutboxOp.upsert);
    await pantry.checkQuantity(id, quantity: 500, unit: ' ml ');
    row = (await pantry.watchItems().first).single;
    expect(row.quantity, 500);
    expect(row.unit, 'ml');
    for (final q in [-1.0, double.nan, double.infinity]) {
      await expectLater(
        () => pantry.checkQuantity(id, quantity: q),
        throwsArgumentError,
      );
    }
  });

  test(
    'provera: 600 g potrebe − 400 g zalihe = 200 g; nepoznato vraća 600 g',
    () async {
      await shop.addRecipePreparation(
        snapshot: const RecipeSnapshot(
          title: 'Jelo',
          baseServings: 2,
          ingredients: [Ingredient(name: 'Brašno', quantity: 600, unit: 'g')],
        ),
        servings: 2,
        originKey: 'check',
      );
      final id = await pantry.create(name: 'Brašno', unit: 'g');
      await pantry.checkQuantity(id, quantity: 400, unit: 'g');
      expect((await shop.watchRecipeItems().first).single.quantity, 200);
      await db.delete(db.syncOutbox).go();
      await db.customStatement(
        "CREATE TRIGGER reject_reconcile BEFORE INSERT ON sync_outbox WHEN NEW.entity = 'shopping_item' BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      await expectLater(
        pantry.checkQuantity(id, quantity: null),
        throwsException,
      );
      expect((await pantry.watchItems().first).single.quantity, 400);
      expect((await shop.watchRecipeItems().first).single.quantity, 200);
      expect(await db.select(db.syncOutbox).get(), isEmpty);
      await db.customStatement('DROP TRIGGER reject_reconcile');

      await pantry.checkQuantity(id, quantity: null);
      expect((await shop.watchRecipeItems().first).single.quantity, 600);
      await pantry.checkQuantity(id, quantity: 0);
      expect(await pantry.watchItems().first, isEmpty);
      expect((await shop.watchRecipeItems().first).single.quantity, 600);
    },
  );

  test('nestalo čuva prijem i ne oživljava već primljenu kupovinu', () async {
    final list = await shop.recipeList();
    final purchase = await shop.addManual(
      list,
      'Mleko',
      quantity: 1,
      unit: 'l',
    );
    await shop.setBought([purchase], bought: true);
    await pantry.receivePurchases([purchase]);
    final id = (await pantry.watchItems().first).single.id;
    await pantry.checkQuantity(id, quantity: 0);
    expect(await pantry.watchItems().first, isEmpty);
    expect(await pantry.receivePurchases([purchase]), 0);
    final row = (await db.select(db.pantryItems).get()).single;
    expect(row.id, id);
    expect(row.quantity, 0);
    expect(row.sourceShoppingItemId, purchase);
    expect(row.confirmedAt!.isAtSameMomentAs(now), isTrue);
  });

  test('036: prijem kupovine prenosi namirnicu u Ostavu', () async {
    final list = await shop.recipeList();
    final purchase = await shop.addManual(
      list,
      'Jaja',
      quantity: 10,
      unit: 'kom',
    );
    await (db.update(db.shoppingItems)..where((t) => t.id.equals(purchase)))
        .write(const ShoppingItemsCompanion(foodId: Value('f_jaje')));
    await shop.setBought([purchase], bought: true);
    await pantry.receivePurchases([purchase]);
    final row = (await db.select(db.pantryItems).get()).single;
    expect((row.name, row.foodId), ('Jaja', 'f_jaje'));
  });

  test('provera ne menja tuđu turu i rollback vraća količinu', () async {
    final id = await pantry.create(name: 'So', quantity: 10, unit: 'g');
    await db
        .into(db.pantryItems)
        .insert(
          PantryItemsCompanion.insert(
            id: 'foreign-check',
            name: 'So',
            category: 'ostalo',
            addedAt: now,
            householdId: const Value('foreign'),
            quantity: const Value(20),
          ),
        );
    await expectLater(
      pantry.checkQuantity('foreign-check', quantity: 0),
      throwsA(isA<PantryItemMissing>()),
    );
    await expectLater(
      pantry.checkQuantity('missing', quantity: 0),
      throwsA(isA<PantryItemMissing>()),
    );
    await db.delete(db.syncOutbox).go();
    await db.customStatement(
      "CREATE TRIGGER reject_check BEFORE INSERT ON sync_outbox BEGIN SELECT RAISE(ABORT, 'test'); END",
    );
    await expectLater(pantry.checkQuantity(id, quantity: 0), throwsException);
    expect((await pantry.watchItems().first).single.quantity, 10);
    expect(await db.select(db.syncOutbox).get(), isEmpty);
  });

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
    'predlozi čitaju isto domaćinstvo i postojeće rezervacije bez upisa',
    () async {
      final list = await shop.recipeList();
      final purchase = await shop.addManual(
        list,
        'Mleko',
        quantity: 1,
        unit: 'l',
      );
      await shop.setBought([purchase], bought: true);
      await pantry.receivePurchases([purchase]);
      final row = (await db.select(db.pantryItems).get()).single;
      await db
          .into(db.pantryItems)
          .insert(
            PantryItemsCompanion.insert(
              id: 'foreign',
              name: 'Tuđe',
              category: 'ostalo',
              addedAt: now,
              householdId: const Value('home-two'),
              quantity: const Value(1),
            ),
          );
      // FK doprinos postoji; isti izvor za rezervaciju pre kupovine/prijema.
      await db
          .into(db.shoppingSources)
          .insert(
            ShoppingSourcesCompanion.insert(
              id: 'source',
              householdId: const Value('home-one'),
              originKey: const Value('test'),
              kind: 'recipePreparation',
              listId: list,
              recipeSnapshotJson: const Value('{}'),
              servings: const Value(2),
              createdAt: now,
            ),
          );
      await db
          .into(db.shoppingContributions)
          .insert(
            ShoppingContributionsCompanion.insert(
              id: 'contribution',
              householdId: const Value('home-one'),
              sourceId: 'source',
              ingredientKey: 'mleko',
              unitGroup: 'volume',
              name: 'Mleko',
              category: 'ostalo',
              micros: const Value(500000000),
              baseUnit: 'ml',
            ),
          );
      await db
          .into(db.supplyAllocations)
          .insert(
            SupplyAllocationsCompanion.insert(
              id: 'allocation',
              householdId: const Value('home-one'),
              contributionId: 'contribution',
              purchasedShoppingItemId: Value(purchase),
              micros: const Value(500000000),
              createdAt: now,
            ),
          );
      final before = await db.select(db.syncOutbox).get();
      final updates = StreamIterator(pantry.watchSuggestionStock());
      expect(await updates.moveNext(), isTrue);
      final stocks = updates.current;
      expect(stocks, hasLength(1));
      expect(stocks.single.id, row.id);
      expect(stocks.single.quantity, 1);
      expect(stocks.single.reservedMicros, 500000000);
      await db.delete(db.supplyAllocations).go();
      expect(await updates.moveNext(), isTrue);
      expect(updates.current.single.reservedMicros, 0);
      await updates.cancel();
      expect((await db.select(db.syncOutbox).get()).length, before.length);
    },
  );

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
