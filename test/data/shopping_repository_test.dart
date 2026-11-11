import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/pantry_repository.dart';
import 'package:tavli/data/recipe_photo_store.dart';
import 'package:tavli/data/shopping_repository.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/sync/synced_writer.dart';
import 'package:tavli/sync/uploader.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_photo_store.dart';
import '../helpers/food_seed.dart';

const krompir = Ingredient(name: 'Krompir', quantity: 1, unit: 'kg');
const meso = Ingredient(name: 'Mleveno meso', quantity: 500, unit: 'g');
const luk = Ingredient(name: 'Crni luk', quantity: 2, unit: 'kom');

void main() {
  late AppDatabase db;
  late ShoppingRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ShoppingRepository(
      db,
      scope: const AccountScope(userId: 'one', householdId: 'home-one'),
      writer: SyncedWriter(db, accountId: 'one'),
    );
  });

  tearDown(() => db.close());

  test(
    'detalji su izolovani, menjaju se kroz outbox i ne diraju količinu',
    () async {
      final list = await repo.recipeList();
      final id = await repo.addManual(list, 'Mleko', quantity: 2, unit: 'l');
      expect(
        await repo.updateDetails(
          id,
          brand: '  Brend  ',
          note: '  Bez laktoze ',
          photoPath: 'recipe_photos/a.jpg',
        ),
        isTrue,
      );
      var row = (await repo.listItems(list)).single;
      expect(
        [row.brand, row.note, row.photoPath],
        ['Brend', 'Bez laktoze', 'recipe_photos/a.jpg'],
      );
      expect([row.quantity, row.unit, row.isBought], [2.0, 'l', false]);
      final other = ShoppingRepository(
        db,
        scope: const AccountScope(userId: 'two', householdId: 'home-two'),
        writer: SyncedWriter(db, accountId: 'two'),
      );
      expect(await other.updateDetails(id, brand: 'tuđe'), isFalse);
      await repo.updateDetails(id, brand: '', photoPath: 'recipe_photos/b.jpg');
      row = (await repo.listItems(list)).single;
      expect(
        [row.brand, row.note, row.photoPath],
        [null, null, 'recipe_photos/b.jpg'],
      );
      final pending = await db.select(db.syncOutbox).get();
      expect(
        pending.any(
          (e) =>
              e.op == OutboxOp.photoDelete &&
              e.recordId == 'recipe_photos/a.jpg',
        ),
        isTrue,
      );
      expect(
        pending.any(
          (e) =>
              e.op == OutboxOp.photoUpload &&
              e.recordId == 'recipe_photos/b.jpg',
        ),
        isTrue,
      );
      await repo.setBought([id], bought: true);
      row = (await repo.listItems(list)).single;
      expect(
        [row.quantity, row.unit, row.photoPath, row.isBought],
        [2.0, 'l', 'recipe_photos/b.jpg', true],
      );
    },
  );

  test(
    'vraćanje obrisane stavke čuva detalje i otkazuje brisanje fotografije',
    () async {
      final list = await repo.recipeList();
      final id = await repo.addManual(list, 'Mleko', quantity: 2, unit: 'l');
      await repo.updateDetails(
        id,
        brand: 'Brend',
        note: 'Napomena',
        photoPath: 'recipe_photos/a.jpg',
      );
      final original = (await repo.listItems(list)).single;
      expect(await repo.deleteManual(id), isTrue);
      final deletion = (await db.select(db.syncOutbox).get()).singleWhere(
        (e) => e.op == OutboxOp.photoDelete,
      );
      expect(deletion.nextAttemptAt, isNotNull);
      await repo.restoreManual(original);
      final restored = (await repo.listItems(list)).single;
      expect(
        [
          restored.brand,
          restored.note,
          restored.photoPath,
          restored.quantity,
          restored.unit,
        ],
        ['Brend', 'Napomena', 'recipe_photos/a.jpg', 2.0, 'l'],
      );
      final outbox = await db.select(db.syncOutbox).get();
      expect(outbox.any((e) => e.op == OutboxOp.photoDelete), isFalse);
      expect(outbox.any((e) => e.op == OutboxOp.photoUpload), isTrue);
    },
  );

  test('kupovina je odvojena po domaćinstvu i upisuje outbox sa UUID-jevima', () async {
    await repo.addMissing('musaka', missing: const [luk], have: const []);
    final other = ShoppingRepository(
      db,
      scope: const AccountScope(userId: 'two', householdId: 'home-two'),
      writer: SyncedWriter(db, accountId: 'two'),
    );
    expect(await other.openNames(), isEmpty);
    await other.addMissing('sarma', missing: const [krompir], have: const []);
    expect(await repo.openNames(), ['Crni luk']);
    expect(await other.openNames(), ['Krompir']);
    final outbox = await db.select(db.syncOutbox).get();
    expect(
      outbox.where((r) => r.accountId == 'one').map((r) => r.entity),
      containsAll(['shopping_list', 'shopping_item']),
    );
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    for (final row in outbox) {
      expect(uuid.hasMatch(row.recordId), isTrue);
    }
    await repo.markHave('musaka', luk);
    final deleted = await (db.select(
      db.syncOutbox,
    )..where((r) => r.op.equals(OutboxOp.delete))).get();
    expect(deleted.single.entity, 'shopping_item');
    expect(deleted.single.accountId, 'one');
  });

  test(
    '3 sastojka, imam 2 → dodaje 1; odštikliram jedan → dodaje samo njega',
    () async {
      // Imam meso i luk; nedostaje krompir.
      var added = await repo.addMissing(
        'musaka',
        missing: const [krompir],
        have: const [meso, luk],
      );
      expect(added.map((i) => i.name), ['Krompir']);
      expect(await repo.openNames(), ['Krompir']);

      // Ponovni klik bez promene ne dodaje ništa.
      added = await repo.addMissing(
        'musaka',
        missing: const [krompir],
        have: const [meso, luk],
      );
      expect(added, isEmpty);

      // Ipak nemam luk: dodaje se samo luk, krompir se ne duplira.
      final plan = await repo.plan(
        'musaka',
        missing: const [krompir, luk],
        have: const [meso],
      );
      expect(plan.toAdd.map((i) => i.name), ['Crni luk']);
      added = await repo.addMissing(
        'musaka',
        missing: const [krompir, luk],
        have: const [meso],
      );
      expect(added.map((i) => i.name), ['Crni luk']);
      expect(await repo.openNames(), ['Krompir', 'Crni luk']);
      expect(await repo.openCount(), 2);
    },
  );

  test(
    'štikliram "imam" za stavku koju je recept dodao → izlazi iz kupovine',
    () async {
      await repo.addMissing(
        'musaka',
        missing: const [krompir, luk],
        have: const [meso],
      );
      expect(await repo.markHave('musaka', luk), isTrue);
      expect(await repo.openNames(), ['Krompir']);
      // Ponovo ga nemam: vraća se jednom.
      await repo.addMissing(
        'musaka',
        missing: const [krompir, luk],
        have: const [meso],
      );
      expect(await repo.openNames(), ['Krompir', 'Crni luk']);
    },
  );

  test('kupljena stavka ostaje i kad je označim kao "imam"', () async {
    await repo.addMissing('musaka', missing: const [luk], have: const []);
    await repo.markBought('Crni luk');
    expect(await repo.markHave('musaka', luk), isFalse);
    expect(await repo.openCount(), 0);
  });

  test('isti sastojak iz dva recepta je jedna stavka; "imam" u jednom je ne '
      'briše za drugi', () async {
    await repo.addMissing('musaka', missing: const [luk], have: const []);
    await repo.addMissing('sarma', missing: const [luk], have: const []);
    expect(await repo.openNames(), ['Crni luk']);

    await repo.markHave('musaka', luk);
    expect(await repo.openNames(), ['Crni luk']);
    await repo.markHave('sarma', luk);
    expect(await repo.openNames(), isEmpty);
  });

  group('010: nedelje, izvori, doprinosi i zaliha', () {
    const home = AccountScope(userId: 'one', householdId: 'home-one');
    final now = DateTime.utc(2026, 11, 1, 9);
    late SyncedWriter writer;
    late ShoppingRepository shop;

    setUp(() {
      writer = SyncedWriter(db, accountId: home.userId, clock: () => now);
      shop = ShoppingRepository(
        db,
        scope: home,
        writer: writer,
        clock: () => now,
      );
    });

    RecipeSnapshot snapshot(List<Ingredient> ingredients, {int servings = 2}) =>
        RecipeSnapshot(
          title: 'Sarma',
          baseServings: servings,
          ingredients: ingredients,
        );

    Future<void> plan(
      String id,
      CivilDate start,
      CivilDate end, {
      String household = 'home-one',
    }) => db
        .into(db.mealPlans)
        .insert(
          MealPlansCompanion.insert(
            id: id,
            startDate: start.toWire(),
            endDate: end.toWire(),
            mealTypesJson: '["lunch","dinner"]',
            createdAt: now,
            householdId: Value(household),
          ),
        );

    Future<void> entry(
      String id,
      CivilDate date, {
      String planId = 'p1',
      String mealType = 'lunch',
      List<Ingredient> ingredients = const [],
      int? servings,
      int baseServings = 2,
      String? recipeId,
      bool cooked = false,
    }) => db
        .into(db.mealPlanEntries)
        .insertOnConflictUpdate(
          MealPlanEntriesCompanion.insert(
            id: id,
            planId: planId,
            date: date.toWire(),
            mealType: mealType,
            recipeId: Value(recipeId),
            servings: Value(servings),
            isCooked: Value(cooked),
            recipeSnapshotJson: Value(
              jsonEncode(
                snapshot(ingredients, servings: baseServings).toJson(),
              ),
            ),
            householdId: const Value('home-one'),
          ),
        );

    Future<void> pantry(
      String id,
      String name,
      double quantity,
      String unit, {
      bool confirmed = true,
      DateTime? expiresAt,
      String? sourceItem,
    }) => db
        .into(db.pantryItems)
        .insertOnConflictUpdate(
          PantryItemsCompanion.insert(
            id: id,
            name: name,
            quantity: Value(quantity),
            unit: Value(unit),
            category: 'ostalo',
            addedAt: now,
            expiresAt: Value(expiresAt),
            confirmedAt: Value(confirmed ? now : null),
            sourceShoppingItemId: Value(sourceItem),
            householdId: const Value('home-one'),
          ),
        );

    Future<List<String>> open(String listId) async => [
      for (final i in await shop.listItems(listId))
        if (!i.isBought) '${i.name} ${i.quantity} ${i.unit}',
    ];

    final mon = CivilDate(2026, 11, 2);
    const kupus = Ingredient(name: 'Kupus', quantity: 300, unit: 'g');

    test('kanonska nedeljna lista: ista za isti plan i nedelju, mesec do 6 '
        'delova, odvojeno po domaćinstvu', () async {
      final range = DateRange(CivilDate(2026, 11, 1), CivilDate(2026, 11, 30));
      final periods = weekPeriods(range);
      expect(periods, hasLength(6));
      final ids = [for (final p in periods) await shop.weekList('p1', p)];
      expect(ids.toSet(), hasLength(6));
      expect(await shop.weekList('p1', periods[2]), ids[2]);
      final lists = await db.select(db.shoppingLists).get();
      final sixth = lists.firstWhere((l) => l.id == ids[5]);
      expect(sixth.week, 6);
      expect(sixth.name, 'Nedelja 6');
      expect(CivilDate.fromWire(sixth.periodStart!), CivilDate(2026, 11, 30));
      expect(CivilDate.fromWire(sixth.periodEnd!), CivilDate(2026, 11, 30));

      final other = ShoppingRepository(
        db,
        scope: const AccountScope(userId: 'two', householdId: 'home-two'),
        writer: SyncedWriter(db, accountId: 'two'),
      );
      expect(await other.weekList('p2', periods[2]), isNot(ids[2]));
      expect(
        (await db.select(db.syncOutbox).get())
            .where((r) => r.accountId == 'one')
            .map((r) => r.entity)
            .toSet(),
        {'shopping_list'},
      );
    });

    test('isti recept dva puta u nedelji: dva izvora, jedna stavka sa zbirom; '
        'ponovno usklađivanje ne menja ništa', () async {
      await plan('p1', mon, mon.addDays(6));
      await entry('e1', mon, ingredients: const [kupus]);
      await entry('e2', mon.addDays(2), ingredients: const [kupus]);
      await shop.reconcilePlan('p1');

      final week = await shop.weekList(
        'p1',
        weekPeriods(DateRange(mon, mon.addDays(6))).first,
      );
      expect(await open(week), ['Kupus 600.0 g']);
      expect(await db.select(db.shoppingSources).get(), hasLength(2));
      final contributions = await db.select(db.shoppingContributions).get();
      expect(contributions, hasLength(2));
      expect(contributions.every((c) => c.micros == 300000000), isTrue);

      // Roditelj pre deteta u outbox-u.
      final order = [
        for (final r in await (db.select(
          db.syncOutbox,
        )..orderBy([(t) => OrderingTerm.asc(t.seq)])).get())
          r.entity,
      ];
      expect(
        order.indexOf('shopping_list'),
        lessThan(order.indexOf('shopping_source')),
      );
      expect(
        order.indexOf('shopping_source'),
        lessThan(order.indexOf('shopping_item')),
      );
      expect(
        order.indexOf('shopping_item'),
        lessThan(order.indexOf('shopping_contribution')),
      );

      // Bez promene: isti redovi, bez novih izmena.
      final before = await db.select(db.syncOutbox).get();
      await shop.reconcilePlan('p1');
      expect(await db.select(db.syncOutbox).get(), hasLength(before.length));
      expect(await db.select(db.shoppingItems).get(), hasLength(1));
      expect(await db.select(db.shoppingContributions).get(), hasLength(2));
    });

    test('porcije menjaju samo razliku: isti doprinos i stavka', () async {
      await plan('p1', mon, mon.addDays(6));
      await entry('e1', mon, ingredients: const [kupus]);
      await shop.reconcilePlan('p1');
      final item = (await db.select(db.shoppingItems).get()).single;
      final contribution =
          (await db.select(db.shoppingContributions).get()).single;

      await shop.updateDetails(
        item.id,
        brand: 'Primer',
        note: 'Sveže',
        photoPath: 'recipe_photos/a.jpg',
      );
      await entry('e1', mon, ingredients: const [kupus], servings: 3);
      await shop.reconcilePlan('p1');
      final after = (await db.select(db.shoppingItems).get()).single;
      expect(after.id, item.id);
      expect(
        [after.brand, after.note, after.photoPath],
        ['Primer', 'Sveže', 'recipe_photos/a.jpg'],
      );
      expect(after.quantity, 450);
      final c = (await db.select(db.shoppingContributions).get()).single;
      expect(c.id, contribution.id);
      expect(c.micros, 450000000);
    });

    test('ostava 400 g na 300/100/200 hronološki: dve nedelje, kupuje se '
        'samo 200 g u drugoj', () async {
      final end = mon.addDays(13);
      await plan('p1', mon, end);
      await entry(
        'e3',
        mon.addDays(8),
        ingredients: const [
          Ingredient(name: 'Pirinač', quantity: 200, unit: 'g'),
        ],
      );
      await entry(
        'e1',
        mon,
        ingredients: const [
          Ingredient(name: 'Pirinač', quantity: 300, unit: 'g'),
        ],
      );
      await entry(
        'e2',
        mon,
        mealType: 'dinner',
        ingredients: const [
          Ingredient(name: 'pirinač', quantity: 0.1, unit: 'kg'),
        ],
      );
      await pantry('o1', 'Pirinač', 0.4, 'kg');
      await shop.reconcilePlan('p1');

      final periods = weekPeriods(DateRange(mon, end));
      final w1 = await shop.weekList('p1', periods[0]);
      final w2 = await shop.weekList('p1', periods[1]);
      expect(await open(w1), isEmpty);
      expect(await open(w2), ['Pirinač 200.0 g']);
      final allocations = await db.select(db.supplyAllocations).get();
      expect(allocations.fold<int>(0, (sum, a) => sum + a.micros!), 400000000);
      expect(allocations.every((a) => a.pantryItemId == 'o1'), isTrue);

      // Ponovo: ista raspodela, bez duplog kredita.
      await shop.reconcilePlan('p1');
      expect(
        await db.select(db.supplyAllocations).get(),
        hasLength(allocations.length),
      );
      expect(await open(w2), ['Pirinač 200.0 g']);

      // Manje u ostavi: kasniji obrok gubi zalihu prvi.
      await pantry('o1', 'Pirinač', 0.3, 'kg');
      await shop.reconcilePlan('p1');
      expect(await open(w1), ['Pirinač 100.0 g']);
      expect(await open(w2), ['Pirinač 200.0 g']);
    });

    test(
      'nepotvrđena, istekla i nepoznata količina ne pokrivaju potrebu',
      () async {
        await plan('p1', mon, mon.addDays(6));
        await entry(
          'e1',
          mon,
          ingredients: const [
            kupus,
            Ingredient(name: 'Luk', quantity: 1, unit: 'kom'),
            Ingredient(name: 'So'),
          ],
        );
        await pantry('o1', 'Kupus', 300, 'g', confirmed: false);
        await pantry(
          'o2',
          'Luk',
          5,
          'kom',
          expiresAt: now.subtract(const Duration(days: 1)),
        );
        await shop.reconcilePlan('p1');
        final week = (await db.select(db.shoppingLists).get()).single.id;
        expect(
          await open(week),
          unorderedEquals(['Kupus 300.0 g', 'Luk 1.0 kom', 'So null null']),
        );
        expect(await db.select(db.supplyAllocations).get(), isEmpty);
      },
    );

    test('kupovina i njen prijem u ostavu su jedna zaliha', () async {
      await plan('p1', mon, mon.addDays(6));
      final list = await shop.weekList(
        'p1',
        weekPeriods(DateRange(mon, mon.addDays(6))).first,
      );
      await db
          .into(db.shoppingItems)
          .insert(
            ShoppingItemsCompanion.insert(
              id: 'kupljeno',
              listId: list,
              name: 'Kupus',
              quantity: const Value(500),
              unit: const Value('g'),
              category: 'voće i povrće',
              isBought: const Value(true),
              purchaseProvenanceJson: const Value('{"sources":["Sarma"]}'),
              householdId: const Value('home-one'),
            ),
          );
      await pantry('prijem', 'Kupus', 500, 'g', sourceItem: 'kupljeno');
      for (var i = 0; i < 3; i++) {
        await entry('e$i', mon.addDays(i), ingredients: const [kupus]);
      }
      await shop.reconcilePlan('p1');

      final allocations = await db.select(db.supplyAllocations).get();
      expect(allocations.fold<int>(0, (sum, a) => sum + a.micros!), 500000000);
      expect(allocations.every((a) => a.supplyId == 'kupljeno'), isTrue);
      expect(await open(list), ['Kupus 400.0 g']);
      // Kupljena stavka i njeno poreklo se ne menjaju.
      final bought = await (db.select(
        db.shoppingItems,
      )..where((t) => t.id.equals('kupljeno'))).getSingle();
      expect(bought.quantity, 500);
      expect(bought.purchaseProvenanceJson, '{"sources":["Sarma"]}');
    });

    test('ručna stavka istog imena ostaje odvojena i netaknuta', () async {
      await plan('p1', mon, mon.addDays(6));
      final list = await shop.weekList(
        'p1',
        weekPeriods(DateRange(mon, mon.addDays(6))).first,
      );
      await db
          .into(db.shoppingItems)
          .insert(
            ShoppingItemsCompanion.insert(
              id: 'rucno',
              listId: list,
              name: 'Kupus',
              quantity: const Value(1),
              unit: const Value('kom'),
              category: 'ostalo',
              isManual: const Value(true),
              householdId: const Value('home-one'),
            ),
          );
      await entry('e1', mon, ingredients: const [kupus]);
      await shop.reconcilePlan('p1');
      await db.delete(db.mealPlanEntries).go();
      await shop.reconcilePlan('p1');
      final items = await db.select(db.shoppingItems).get();
      expect(items.single.id, 'rucno');
      expect(items.single.quantity, 1);
    });

    test('obrisan obrok oslobađa zalihu za drugi; skuvan ne pravi kupovinu, '
        'a zadržava zalihu', () async {
      await plan('p1', mon, mon.addDays(6));
      await entry('e1', mon, ingredients: const [kupus]);
      await entry('e2', mon.addDays(1), ingredients: const [kupus]);
      await pantry('o1', 'Kupus', 300, 'g');
      await shop.reconcilePlan('p1');
      final list = (await db.select(db.shoppingLists).get()).single.id;
      expect(await open(list), ['Kupus 300.0 g']);

      await entry(
        'e2',
        mon.addDays(1),
        ingredients: const [kupus],
        cooked: true,
      );
      await shop.reconcilePlan('p1');
      expect(await open(list), isEmpty);
      final closed = await (db.select(
        db.shoppingSources,
      )..where((t) => t.planEntryId.equals('e2'))).getSingle();
      expect(closed.closedAt, isNotNull);

      await (db.delete(
        db.mealPlanEntries,
      )..where((t) => t.id.equals('e1'))).go();
      await shop.reconcilePlan('p1');
      expect(
        [
          for (final s in await db.select(db.shoppingSources).get())
            s.planEntryId,
        ],
        ['e2'],
      );
      expect(await open(list), isEmpty);
      final deleted = {
        for (final r in await (db.select(
          db.syncOutbox,
        )..where((t) => t.op.equals(OutboxOp.delete))).get())
          r.entity,
      };
      expect(
        deleted,
        containsAll(['shopping_source', 'shopping_contribution']),
      );
    });

    test(
      'mesečni zbir spaja potvrđene sinonime u različitim nedeljama',
      () async {
        final end = mon.addDays(8);
        await plan('p1', mon, end);
        await entry(
          'e1',
          mon,
          ingredients: const [
            Ingredient(name: 'beli luk', quantity: 100, unit: 'g'),
          ],
        );
        await entry(
          'e2',
          end,
          ingredients: const [
            Ingredient(name: 'češnjak', quantity: 50, unit: 'gram'),
          ],
        );
        for (final e in await db.select(db.mealPlanEntries).get()) {
          final old = RecipeSnapshot.fromJson(
            jsonDecode(e.recipeSnapshotJson!) as Map<String, dynamic>,
          );
          await (db.update(
            db.mealPlanEntries,
          )..where((t) => t.id.equals(e.id))).write(
            MealPlanEntriesCompanion(
              recipeSnapshotJson: Value(
                jsonEncode(old.withCurrentDictionary().toJson()),
              ),
            ),
          );
        }
        await shop.reconcilePlan('p1');
        final totals = await shop.planTotals('p1');
        expect(totals, hasLength(1));
        expect(totals.single.openMicros, 150000000);
      },
    );

    test(
      'novi sinonimi se saberu, staro odobrenje se ne menja pri obračunu',
      () async {
        await plan('p1', mon, mon);
        await entry(
          'e1',
          mon,
          ingredients: const [
            Ingredient(name: 'beli luk', quantity: 100, unit: 'g'),
            Ingredient(name: 'češnjak', quantity: 50, unit: 'gram'),
          ],
        );
        await shop.reconcilePlan('p1');
        final before = await db.select(db.shoppingContributions).get();
        final oldSnapshot = (await db.select(db.mealPlanEntries).get())
            .single
            .recipeSnapshotJson;
        expect(before, hasLength(2));
        await shop.addRecipePreparation(
          snapshot: snapshot(const [
            Ingredient(name: 'beli luk', quantity: 100, unit: 'g'),
            Ingredient(name: 'češnjak', quantity: 50, unit: 'gram'),
            Ingredient(name: 'češnjak', quantity: 2, unit: 'komad'),
          ]),
          servings: 2,
          originKey: 'novi',
        );
        final lines = await db.select(db.shoppingContributions).get();
        final old = lines
            .where((c) => c.sourceId == before.first.sourceId)
            .toList();
        expect(old.map((c) => c.id).toSet(), before.map((c) => c.id).toSet());
        expect(
          (await db.select(db.mealPlanEntries).get()).single.recipeSnapshotJson,
          oldSnapshot,
        );
        final source = (await db.select(db.shoppingSources).get()).singleWhere(
          (s) => s.originKey == 'novi',
        );
        expect(
          (jsonDecode(source.recipeSnapshotJson!)
              as Map<String, dynamic>)['dictionaryVersion'],
          2,
        );
        final current = lines.where((c) => c.sourceId == source.id).toList();
        expect(current, hasLength(2));
        expect(
          current.firstWhere((c) => c.unitGroup == 'mass').micros,
          150000000,
        );
      },
    );

    test(
      'zaliha sinonima koristi se jednom kroz stare i nove izvore',
      () async {
        await plan('p1', mon, mon);
        await entry(
          'e1',
          mon,
          ingredients: const [
            Ingredient(name: 'beli luk', quantity: 100, unit: 'g'),
          ],
        );
        await pantry('stock', 'beli luk', 150, 'gram');
        await shop.reconcilePlan('p1');
        // Stari izvor ne prepoznaje naziv "gram" i ostaje nepromenjen.
        final old = (await db.select(db.shoppingContributions).get()).single;
        expect(old.micros, 100000000);
        await shop.addRecipePreparation(
          snapshot: snapshot(const [
            Ingredient(name: 'češnjak', quantity: 100, unit: 'g'),
          ]),
          servings: 2,
          originKey: 'novi',
        );
        final list = await shop.recipeList();
        expect(await open(list), isEmpty);
        final allocations = await db.select(db.supplyAllocations).get();
        expect(
          allocations.fold<int>(0, (sum, a) => sum + (a.micros ?? 0)),
          100000000,
        );
        await shop.reconcilePlan('p1');
        expect(
          (await db.select(db.shoppingContributions).get())
              .firstWhere((c) => c.id == old.id)
              .unitGroup,
          'mass',
        );
      },
    );

    test('samostalna priprema bez plana: ista priprema pri ponovnom dodavanju, '
        '"Ponovi nabavku" pravi novu', () async {
      final first = await shop.addRecipePreparation(
        snapshot: snapshot(const [kupus]),
        servings: 2,
        originKey: 'recept-sarma',
        recipeId: 'sarma',
      );
      final list = await shop.recipeList();
      expect(await open(list), ['Kupus 300.0 g']);
      expect(await db.select(db.mealPlans).get(), isEmpty);
      expect(await db.select(db.recipes).get(), isEmpty);

      final again = await shop.addRecipePreparation(
        snapshot: snapshot(const [kupus]),
        servings: 4,
        originKey: 'recept-sarma',
        recipeId: 'sarma',
      );
      expect(again, first);
      expect(await open(list), ['Kupus 600.0 g']);

      final repeat = await shop.addRecipePreparation(
        snapshot: snapshot(const [kupus]),
        servings: 2,
        originKey: 'recept-sarma',
        recipeId: 'sarma',
        repeat: true,
      );
      expect(repeat, isNot(first));
      final sources = {
        for (final s in await db.select(db.shoppingSources).get()) s.id: s,
      };
      expect(sources[first]!.supersededAt, isNotNull);
      expect(sources[repeat]!.supersededAt, isNull);
      expect(await open(list), ['Kupus 900.0 g']);
      expect(
        jsonDecode((await shop.listItems(list)).single.fromRecipeIdsJson),
        ['sarma'],
      );

      await shop.removeSource(first);
      expect(await open(list), ['Kupus 300.0 g']);
      expect(
        () => shop.addRecipePreparation(
          snapshot: snapshot(const [kupus]),
          servings: 21,
          originKey: 'x',
        ),
        throwsArgumentError,
      );
    });

    Future<ShoppingItemRow> item(String listId, String name) async =>
        (await shop.listItems(listId)).firstWhere((i) => i.name == name);

    test(
      'kupljeno pokriva baš tu nedelju; poništavanje vraća istu stavku',
      () async {
        final end = mon.addDays(13);
        await plan('p1', mon, end);
        await entry('e1', mon, ingredients: const [kupus]);
        await entry('e2', mon.addDays(8), ingredients: const [kupus]);
        await shop.reconcilePlan('p1');
        final weeks = weekPeriods(DateRange(mon, end));
        final w1 = await shop.weekList('p1', weeks[0]);
        final w2 = await shop.weekList('p1', weeks[1]);
        final second = await item(w2, 'Kupus');

        expect(await shop.setBought([second.id], bought: true), 1);
        // Ponovljen klik ne menja ništa.
        expect(await shop.setBought([second.id], bought: true), 0);
        expect(await open(w1), ['Kupus 300.0 g']);
        expect(await open(w2), isEmpty);
        final bought = await item(w2, 'Kupus');
        expect(bought.isBought, isTrue);
        final sources = await shop.itemSources(bought.id);
        expect(sources.single.title, 'Sarma');
        expect(sources.single.date, mon.addDays(8));
        expect(sources.single.mealType, 'lunch');

        expect(await shop.setBought([second.id], bought: false), 1);
        expect(await open(w2), ['Kupus 300.0 g']);
        final back = await item(w2, 'Kupus');
        expect(back.id, second.id);
        expect(back.purchaseProvenanceJson, isNull);
        expect(
          await db.select(db.supplyAllocations).get(),
          isEmpty,
          reason: 'poništena kupovina više nije zaliha',
        );
        expect(await shop.listItems(w2), hasLength(1));
      },
    );

    test('nepoznata količina: kupljeno je pokriva, poništeno vraća', () async {
      await plan('p1', mon, mon.addDays(6));
      await entry('e1', mon, ingredients: const [Ingredient(name: 'So')]);
      await shop.reconcilePlan('p1');
      final list = (await db.select(db.shoppingLists).get()).single.id;
      final so = await item(list, 'So');
      await shop.setBought([so.id], bought: true);
      expect(await open(list), isEmpty);
      await shop.reconcilePlan('p1');
      expect(await open(list), isEmpty);
      await shop.setBought([so.id], bought: false);
      expect(await open(list), ['So null null']);
      expect((await item(list, 'So')).id, so.id);
    });

    test('ručna stavka: brzo dodavanje, kupljeno/poništeno, brisanje; '
        'obroci je ne menjaju', () async {
      await plan('p1', mon, mon.addDays(6));
      final list = await shop.weekList(
        'p1',
        weekPeriods(DateRange(mon, mon.addDays(6))).first,
      );
      final id = await shop.addManual(list, '  Deterdžent ');
      expect(() => shop.addManual(list, ' '), throwsArgumentError);
      await entry('e1', mon, ingredients: const [kupus]);
      await shop.reconcilePlan('p1');
      expect(
        await open(list),
        unorderedEquals(['Deterdžent null null', 'Kupus 300.0 g']),
      );
      expect(await shop.itemSources(id), isEmpty);

      await shop.setBought([id], bought: true);
      await shop.setBought([id], bought: false);
      expect((await item(list, 'Deterdžent')).isManual, isTrue);
      expect(await shop.deleteManual(id), isTrue);
      final kupusId = (await item(list, 'Kupus')).id;
      expect(await shop.deleteManual(kupusId), isFalse);
      expect(await open(list), ['Kupus 300.0 g']);
    });

    test(
      '300 g potrebe, 100 g u ostavi, kupljeno 200 g i primljeno; potreba '
      '400 g → kupuje se još 100 g, ponovljen prijem ne menja ništa',
      () async {
        final pantryRepo = PantryRepository(
          db,
          scope: home,
          writer: writer,
          shopping: shop,
          clock: () => now,
        );
        await plan('p1', mon, mon.addDays(6));
        await entry('e1', mon, ingredients: const [kupus]);
        await pantry('o1', 'Kupus', 100, 'g');
        await shop.reconcilePlan('p1');
        final list = (await db.select(db.shoppingLists).get()).single.id;
        expect(await open(list), ['Kupus 200.0 g']);
        final bought = await item(list, 'Kupus');
        await shop.setBought([bought.id], bought: true);
        expect(await pantryRepo.receivePurchases([bought.id]), 1);
        expect(await pantryRepo.receivePurchases([bought.id]), 0);
        await shop.reconcilePlan('p1');
        expect(await open(list), isEmpty);

        await entry(
          'e1',
          mon,
          ingredients: const [
            Ingredient(name: 'Kupus', quantity: 400, unit: 'g'),
          ],
        );
        await shop.reconcilePlan('p1');
        await shop.reconcilePlan('p1');
        expect(await open(list), ['Kupus 100.0 g']);
        expect(
          (await db.select(db.pantryItems).get()).map((p) => p.id),
          hasLength(2),
        );
        // Primljena kupovina se više ne poništava.
        expect(await shop.setBought([bought.id], bought: false), 0);
        expect((await item(list, 'Kupus')).isBought, isTrue);
      },
    );

    test('zamenjen ili uklonjen obrok ne vraća kupljeno u nabavku', () async {
      await plan('p1', mon, mon.addDays(6));
      await entry('e1', mon, ingredients: const [kupus]);
      await shop.reconcilePlan('p1');
      final list = (await db.select(db.shoppingLists).get()).single.id;
      final id = (await item(list, 'Kupus')).id;
      await shop.setBought([id], bought: true);
      await (db.delete(
        db.mealPlanEntries,
      )..where((t) => t.id.equals('e1'))).go();
      await shop.reconcilePlan('p1');
      final kept = await item(list, 'Kupus');
      expect(kept.isBought, isTrue);
      expect(kept.quantity, 300);
      expect(
        (await shop.itemSources(id)).single.title,
        'Sarma',
        reason: 'poreklo kupovine je zamrznuto',
      );
    });

    test('recept bez plana: "imam" pa poništen "imam" dodaje samo razliku; '
        'kupljeno ostaje; spisak tekućih priprema', () async {
      const luk = Ingredient(name: 'Luk', quantity: 1, unit: 'kom');
      final first = await shop.addRecipePreparation(
        snapshot: snapshot(const [kupus]),
        servings: 2,
        originKey: 'recipe:sarma',
        recipeId: 'sarma',
      );
      final list = await shop.recipeList();
      final kupusId = (await item(list, 'Kupus')).id;
      await shop.setBought([kupusId], bought: true);

      // Ipak nemam luk: ista priprema, dodaje se samo luk.
      final again = await shop.addRecipePreparation(
        snapshot: snapshot(const [kupus, luk]),
        servings: 2,
        originKey: 'recipe:sarma',
        recipeId: 'sarma',
      );
      expect(again, first);
      expect(await open(list), ['Luk 1.0 kom']);
      expect((await item(list, 'Kupus')).isBought, isTrue);

      final current = await shop.currentPreparation('recipe:sarma');
      expect(current!.id, first);
      expect(current.servings, 2);
      expect(current.snapshot.ingredients.map((i) => i.name), ['Kupus', 'Luk']);
      expect(await shop.currentPreparation('recipe:musaka'), isNull);
      expect((await shop.watchPreparations().first).single.id, first);

      final repeat = await shop.addRecipePreparation(
        snapshot: snapshot(const [kupus]),
        servings: 2,
        originKey: 'recipe:sarma',
        recipeId: 'sarma',
        repeat: true,
      );
      expect((await shop.watchPreparations().first).single.id, repeat);
      await shop.removeSource(repeat);
      expect(await shop.watchPreparations().first, isEmpty);
      expect(await shop.currentPreparation('recipe:sarma'), isNull);
      expect(await db.select(db.mealPlans).get(), isEmpty);
    });

    test('ista potvrđena zaliha se ne koristi i za plan i za recept', () async {
      await plan('p1', mon, mon.addDays(6));
      await entry('e1', mon, ingredients: const [kupus], recipeId: 'sarma');
      await pantry('o1', 'Kupus', 300, 'g');
      await shop.reconcilePlan('p1');
      await shop.addRecipePreparation(
        snapshot: snapshot(const [kupus]),
        servings: 2,
        originKey: 'recipe:sarma',
        recipeId: 'sarma',
      );
      final week = await shop.weekList(
        'p1',
        weekPeriods(DateRange(mon, mon.addDays(6))).first,
      );
      expect(await open(week), isEmpty);
      expect(await open(await shop.recipeList()), ['Kupus 300.0 g']);
      expect(await shop.isPlanned('sarma'), isTrue);
      expect(await shop.isPlanned('musaka'), isFalse);
      await entry(
        'e1',
        mon,
        ingredients: const [kupus],
        recipeId: 'sarma',
        cooked: true,
      );
      expect(await shop.isPlanned('sarma'), isFalse);
    });

    test('mesec se samo sabira iz nedelja; ne pravi novu listu', () async {
      final end = mon.addDays(13);
      await plan('p1', mon, end);
      await entry('e1', mon, ingredients: const [kupus]);
      await entry(
        'e2',
        mon.addDays(8),
        ingredients: const [Ingredient(name: 'kupus', quantity: 1, unit: 'kg')],
      );
      await entry(
        'e3',
        mon.addDays(9),
        ingredients: const [Ingredient(name: 'So')],
      );
      await shop.reconcilePlan('p1');
      final lists = await db.select(db.shoppingLists).get();
      final totals = await shop.planTotals('p1');
      expect(await db.select(db.shoppingLists).get(), hasLength(lists.length));
      final k = totals.firstWhere((t) => t.ingredient == 'kupus');
      expect(k.openMicros, 1300000000);
      expect(k.baseUnit, 'g');
      expect(k.listIds, hasLength(2));
      expect(k.itemIds, hasLength(2));
      expect(totals.firstWhere((t) => t.ingredient == 'so').hasUnknown, isTrue);
    });

    test('poslato na server: roditelj pre deteta, ponovni pokušaj bez '
        'duplikata', () async {
      final backend = FakeBackend();
      final s = await backend.auth.verifyCode('ana@mail.com', FakeServer.code);
      final scope = AccountScope(
        userId: s.userId,
        householdId: backend.server.households[s.userId]!,
      );
      final w = SyncedWriter(db, accountId: scope.userId, clock: () => now);
      final repo = ShoppingRepository(
        db,
        scope: scope,
        writer: w,
        clock: () => now,
      );
      await db
          .into(db.mealPlans)
          .insert(
            MealPlansCompanion.insert(
              id: 'p1',
              startDate: mon.toWire(),
              endDate: mon.addDays(6).toWire(),
              mealTypesJson: '["lunch"]',
              createdAt: now,
              householdId: Value(scope.householdId),
            ),
          );
      await db
          .into(db.mealPlanEntries)
          .insert(
            MealPlanEntriesCompanion.insert(
              id: 'e1',
              planId: 'p1',
              date: mon.toWire(),
              mealType: 'lunch',
              recipeSnapshotJson: Value(
                jsonEncode(snapshot(const [kupus]).toJson()),
              ),
              householdId: Value(scope.householdId),
            ),
          );
      await w.upsert('meal_plan', 'p1');
      await w.upsert('meal_plan_entry', 'e1');
      await db
          .into(db.pantryItems)
          .insert(
            PantryItemsCompanion.insert(
              id: 'o1',
              name: 'Kupus',
              quantity: const Value(100),
              unit: const Value('g'),
              category: 'ostalo',
              addedAt: now,
              confirmedAt: Value(now),
              householdId: Value(scope.householdId),
            ),
          );
      await w.upsert('pantry_item', 'o1');
      await repo.reconcilePlan('p1');

      final uploader = Uploader(
        db: db,
        remote: backend.sync,
        photos: backend.photos,
        photoStore: FakePhotoStore() as RecipePhotoStore,
        scope: scope,
        refreshSession: () async => true,
        clock: () => now,
      );
      backend.server.interruptAfterRows = 4;
      expect((await uploader.run()).offline, isTrue);
      await uploader.run();
      final upserts = [
        for (final c in backend.server.calls)
          if (c.startsWith('upsert:')) c.split(':')[1],
      ];
      expect(
        upserts.indexOf('shopping_items'),
        lessThan(upserts.lastIndexOf('shopping_contributions')),
      );
      expect(
        upserts.lastIndexOf('shopping_contributions'),
        lessThanOrEqualTo(upserts.lastIndexOf('supply_allocations')),
      );
      final server = backend.server;
      expect(server.rows('shopping_sources').single['plan_entry_id'], 'e1');
      expect(server.rows('shopping_contributions').single['micros'], 300000000);
      expect(server.rows('supply_allocations').single['supply_id'], 'o1');
      expect(server.rows('shopping_items').single['quantity'], 200.0);
      expect(await db.select(db.syncOutbox).get(), isEmpty);
    });
  });

  group('036: nabavka po namirnici', () {
    final now = DateTime.utc(2026, 11);

    setUp(() async {
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
    });

    RecipeSnapshot dish(String title, int base, List<Ingredient> items) =>
        RecipeSnapshot(title: title, baseServings: base, ingredients: items);

    Future<void> jajce({String? foodId = 'f_jaje'}) => db
        .into(db.pantryItems)
        .insert(
          PantryItemsCompanion.insert(
            id: 'ostava-jajce',
            name: 'jajce',
            quantity: const Value(2),
            unit: const Value('kom'),
            category: 'ostalo',
            addedAt: now,
            confirmedAt: Value(now),
            householdId: const Value('home-one'),
            foodId: Value(foodId),
          ),
        );

    test('potvrda pripreme: snimak v2 i doprinos po namirnici', () async {
      await repo.addRecipePreparation(
        snapshot: dish('Omlet', 2, const [
          Ingredient(name: 'Jaja', quantity: 2, unit: 'kom'),
        ]),
        servings: 2,
        originKey: 'omlet',
      );
      final source = (await db.select(db.shoppingSources).get()).single;
      final json =
          jsonDecode(source.recipeSnapshotJson!) as Map<String, dynamic>;
      expect(json['dictionaryVersion'], 2);
      final ingredient =
          (json['ingredients'] as List).single as Map<String, dynamic>;
      expect(ingredient['foodId'], 'f_jaje');
      expect(ingredient['name'], 'Jaja');
      final c = (await db.select(db.shoppingContributions).get()).single;
      expect(c.ingredientKey, 'food:f_jaje');
    });

    test('SC-001: jedna stavka „jaje“ 1,5 kom posle zalihe „jajce“', () async {
      await jajce();
      await repo.addRecipePreparation(
        snapshot: dish('A', 4, const [
          Ingredient(name: 'jaja', quantity: 3, unit: 'kom'),
        ]),
        servings: 2,
        originKey: 'a',
      );
      await repo.addRecipePreparation(
        snapshot: dish('B', 2, const [
          Ingredient(name: 'jaje', quantity: 2, unit: 'kom'),
        ]),
        servings: 2,
        originKey: 'b',
      );
      final list = await repo.recipeList();
      final open = [
        for (final i in await repo.listItems(list))
          if (!i.isBought) i,
      ];
      expect(open, hasLength(1));
      expect(
        (open.single.name, open.single.quantity, open.single.unit),
        ('jaje', 1.5, 'kom'),
      );
      expect(open.single.foodId, 'f_jaje');
      final allocated = await db.select(db.supplyAllocations).get();
      expect(allocated.fold<int>(0, (s, a) => s + a.micros!), 2000000);
    });

    test('kontrola bez kataloga: dve stavke, zaliha ne pokriva', () async {
      await db.delete(db.foodAliases).go();
      await db.delete(db.foods).go();
      await jajce(foodId: null);
      await repo.addRecipePreparation(
        snapshot: dish('A', 4, const [
          Ingredient(name: 'jaja', quantity: 3, unit: 'kom'),
        ]),
        servings: 2,
        originKey: 'a',
      );
      await repo.addRecipePreparation(
        snapshot: dish('B', 2, const [
          Ingredient(name: 'jaje', quantity: 2, unit: 'kom'),
        ]),
        servings: 2,
        originKey: 'b',
      );
      final list = await repo.recipeList();
      expect(
        [
          for (final i in await repo.listItems(list))
            if (!i.isBought) '${i.name} ${i.quantity} ${i.foodId}',
        ],
        ['jaja 1.5 null', 'jaje 2.0 null'],
      );
    });

    test('namirnica koje nema na uređaju: naziv iz teksta', () async {
      await repo.addRecipePreparation(
        snapshot: dish('C', 2, const [
          Ingredient(
            name: 'Zmajevo voće',
            quantity: 1,
            unit: 'kom',
            foodId: 'own-nema',
          ),
        ]),
        servings: 2,
        originKey: 'c',
      );
      final list = await repo.recipeList();
      final item = (await repo.listItems(list)).single;
      expect((item.name, item.foodId), ('Zmajevo voće', 'own-nema'));
    });

    test('C1: „Dodaj u kupovinu“ ne duplira istu namirnicu', () async {
      final added = await repo.addMissing(
        'omlet',
        missing: const [Ingredient(name: 'Jajce', foodId: 'f_jaje')],
        have: const [],
      );
      expect(added, hasLength(1));
      final again = await repo.addMissing(
        'kajgana',
        missing: const [Ingredient(name: 'jaja', foodId: 'f_jaje')],
        have: const [],
      );
      expect(again, hasLength(1));
      final rows = await db.select(db.shoppingItems).get();
      expect(rows, hasLength(1));
      expect((rows.single.name, rows.single.foodId), ('Jajce', 'f_jaje'));
      expect(jsonDecode(rows.single.fromRecipeIdsJson), ['omlet', 'kajgana']);
      expect(
        await repo.markHave(
          'kajgana',
          const Ingredient(name: 'jaje', foodId: 'f_jaje'),
        ),
        isTrue,
      );
    });

    test('totalsOf grupiše po namirnici', () {
      ShoppingItemRow row(String id, String name, String? foodId) =>
          ShoppingItemRow(
            id: id,
            listId: 'l',
            name: name,
            quantity: 1,
            unit: 'kom',
            category: 'ostalo',
            isBought: false,
            isManual: false,
            fromRecipeIdsJson: '[]',
            foodId: foodId,
          );
      final totals = ShoppingRepository.totalsOf([
        row('1', 'jaja', 'f_jaje'),
        row('2', 'jajce', 'f_jaje'),
        row('3', 'jaja', null),
      ]);
      expect(
        [for (final t in totals) '${t.ingredient} ${t.openMicros}'],
        ['food:f_jaje 2000000', 'jaja 1000000'],
      );
    });
  });

  test('036: ručna stavka dobija namirnicu po aliasu', () async {
    await seedEggs(db);
    final list = await repo.recipeList();
    final id = await repo.addManual(list, 'Jaja', quantity: 10, unit: 'kom');
    final other = await repo.addManual(list, 'kokos', foodId: 'own-x');
    final rows = {for (final r in await repo.listItems(list)) r.id: r.foodId};
    expect(rows, {id: 'f_jaje', other: 'own-x'});
  });

  test('036: usklađivanje ne briše namirnicu koju je postavilo mapiranje '
      'na stavci sa tekstualnim ključem', () async {
    await repo.addRecipePreparation(
      snapshot: const RecipeSnapshot(
        title: 'Pire',
        baseServings: 2,
        ingredients: [Ingredient(name: 'krompir', quantity: 1, unit: 'kg')],
      ),
      servings: 2,
      originKey: 'pire',
    );
    final item = (await db.select(db.shoppingItems).get()).single;
    expect(item.foodId, isNull);
    // Kao posle serverskog mapiranja (map_food_ids) i preuzimanja.
    await (db.update(db.shoppingItems)..where((t) => t.id.equals(item.id)))
        .write(const ShoppingItemsCompanion(foodId: Value('f_krompir')));
    await db.delete(db.syncOutbox).go();
    await repo.reconcileInventory();
    expect(
      (await db.select(db.shoppingItems).get()).single.foodId,
      'f_krompir',
    );
    expect(await db.select(db.syncOutbox).get(), isEmpty);
  });

  test('036: namirnica se menja samo ručnoj, nekupljenoj stavci', () async {
    await seedEggs(db);
    final list = await repo.recipeList();
    final id = await repo.addManual(list, 'domaća jajca');
    await db.delete(db.syncOutbox).go();
    expect(await repo.setManualFood(id, 'f_jaje'), isTrue);
    expect((await repo.listItems(list)).single.foodId, 'f_jaje');
    expect(await db.select(db.syncOutbox).get(), hasLength(1));
    expect(() => repo.setManualFood(id, 'nepostoji'), throwsArgumentError);
    await repo.setBought([id], bought: true);
    expect(await repo.setManualFood(id, 'f_jaje'), isFalse);
    expect(await repo.setManualFood('nema', 'f_jaje'), isFalse);
  });
}
