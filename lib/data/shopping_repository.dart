import 'dart:convert';

import 'package:drift/drift.dart';

import '../account/auth_controller.dart';
import '../domain/ids.dart';
import '../domain/meal_plan.dart' show MealKind;
import '../domain/plan_calendar.dart';
import '../domain/recipe.dart';
import '../domain/shopping_demand.dart';
import '../domain/shopping_source.dart';
import '../domain/shopping_sync.dart';
import '../domain/supply_allocation.dart';
import '../sync/synced_writer.dart';
import 'database.dart';

/// Zbir jedne namirnice u celom planu (mesec): samo za čitanje. Radnje idu
/// na nedeljne stavke iz [itemIds]; mesečna lista se ne čuva.
class PlanTotal {
  const PlanTotal({
    required this.ingredient,
    required this.unitGroup,
    required this.name,
    required this.category,
    required this.baseUnit,
    required this.openMicros,
    required this.boughtMicros,
    required this.hasUnknown,
    required this.itemIds,
    required this.listIds,
  });

  final String ingredient;
  final String unitGroup;
  final String name;
  final String category;
  final String baseUnit;

  /// Preostalo za kupovinu i već kupljeno, u milionitim delovima [baseUnit].
  final int openMicros;
  final int boughtMicros;

  /// Neka otvorena stavka nema poznatu količinu (traži proveru).
  final bool hasUnknown;
  final List<String> itemIds;
  final List<String> listIds;
}

/// Stavka nedeljne liste plana sa početkom te nedelje.
class PlanShoppingItem {
  const PlanShoppingItem({required this.weekStart, required this.item});

  final CivilDate weekStart;
  final ShoppingItemRow item;
}

/// Samostalna priprema recepta u nabavci: zamrznut recept sa sastojcima
/// koje osoba nema (ostale je označila sa "imam") i porcije.
class RecipePreparation {
  const RecipePreparation({
    required this.id,
    required this.snapshot,
    required this.servings,
    this.recipeId,
  });

  final String id;
  final RecipeSnapshot snapshot;
  final int servings;
  final String? recipeId;
}

/// Kupovina domaćinstva; svaka izmena ima outbox u istoj transakciji.
class ShoppingRepository {
  ShoppingRepository(
    this._db, {
    required this._scope,
    required this._writer,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final AccountScope _scope;
  final SyncedWriter _writer;
  final DateTime Function() _clock;

  Future<String> _ensureList() => _db.transaction(() async {
    final existing =
        await (_db.select(_db.shoppingLists)
              ..where(
                (t) =>
                    t.householdId.equals(_scope.householdId) &
                    t.mealPlanId.isNull(),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(t.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return existing.id;
    final id = newId();
    await _db
        .into(_db.shoppingLists)
        .insert(
          ShoppingListsCompanion.insert(
            id: id,
            name: 'Kupovina',
            createdAt: _clock().toUtc(),
            householdId: Value(_scope.householdId),
          ),
        );
    await _writer.upsert('shopping_list', id);
    return id;
  });

  static List<String> _recipes(ShoppingItemRow row) => [
    for (final id in jsonDecode(row.fromRecipeIdsJson) as List<dynamic>)
      id as String,
  ];

  Future<List<ShoppingItemRow>> _items() async {
    final id = await _ensureList();
    return (_db.select(_db.shoppingItems)..where(
          (t) => t.listId.equals(id) & t.householdId.equals(_scope.householdId),
        ))
        .get();
  }

  Future<ShoppingSyncPlan> plan(
    String recipeId, {
    required List<Ingredient> missing,
    required List<Ingredient> have,
  }) async {
    final rows = [
      for (final row in await _items())
        if (_recipes(row).contains(recipeId)) row,
    ];
    return planRecipeShopping(
      missing: missing,
      have: have,
      inList: {for (final row in rows) ingredientKey(row.name)},
      bought: {
        for (final row in rows)
          if (row.isBought) ingredientKey(row.name),
      },
    );
  }

  /// Ponovni klik dodaje samo razliku; drugi recept deli postojeću stavku.
  Future<List<Ingredient>> addMissing(
    String recipeId, {
    required List<Ingredient> missing,
    required List<Ingredient> have,
  }) => _db.transaction(() async {
    final p = await plan(recipeId, missing: missing, have: have);
    final listId = await _ensureList();
    final open = {
      for (final row in await _items())
        if (!row.isBought) ingredientKey(row.name): row,
    };
    for (final ingredient in p.toAdd) {
      final existing = open[ingredientKey(ingredient.name)];
      if (existing != null) {
        await (_db.update(
          _db.shoppingItems,
        )..where((t) => t.id.equals(existing.id))).write(
          ShoppingItemsCompanion(
            fromRecipeIdsJson: Value(
              jsonEncode([..._recipes(existing), recipeId]),
            ),
          ),
        );
        await _writer.upsert('shopping_item', existing.id);
      } else {
        final id = newId();
        await _db
            .into(_db.shoppingItems)
            .insert(
              ShoppingItemsCompanion.insert(
                id: id,
                listId: listId,
                name: ingredient.name,
                quantity: Value(ingredient.quantity),
                unit: Value(ingredient.unit),
                category: ingredient.category,
                fromRecipeIdsJson: Value(jsonEncode([recipeId])),
                householdId: Value(_scope.householdId),
              ),
            );
        await _writer.upsert('shopping_item', id);
      }
    }
    return p.toAdd;
  });

  /// "Imam" uklanja samo doprinos ovog recepta; kupljeno ostaje.
  Future<bool> markHave(String recipeId, Ingredient ingredient) =>
      _db.transaction(() async {
        var removed = false;
        for (final row in await _items()) {
          final recipes = _recipes(row);
          if (row.isBought ||
              ingredientKey(row.name) != ingredientKey(ingredient.name) ||
              !recipes.contains(recipeId)) {
            continue;
          }
          removed = true;
          final rest = [...recipes]..remove(recipeId);
          if (rest.isEmpty && !row.isManual) {
            await (_db.delete(
              _db.shoppingItems,
            )..where((t) => t.id.equals(row.id))).go();
            await _writer.delete('shopping_item', row.id);
            if (row.photoPath case final p?) await _writer.photoDelete(p);
          } else {
            await (_db.update(
              _db.shoppingItems,
            )..where((t) => t.id.equals(row.id))).write(
              ShoppingItemsCompanion(
                fromRecipeIdsJson: Value(jsonEncode(rest)),
              ),
            );
            await _writer.upsert('shopping_item', row.id);
          }
        }
        return removed;
      });

  Future<int> openCount() async =>
      (await _items()).where((row) => !row.isBought).length;
  Future<List<String>> openNames() async => [
    for (final row in await _items())
      if (!row.isBought) row.name,
  ];

  Future<void> markBought(String name) => _db.transaction(() async {
    for (final row in await _items()) {
      if (ingredientKey(row.name) == ingredientKey(name) && !row.isBought) {
        await (_db.update(_db.shoppingItems)..where((t) => t.id.equals(row.id)))
            .write(const ShoppingItemsCompanion(isBought: Value(true)));
        await _writer.upsert('shopping_item', row.id);
      }
    }
  });

  // ---------------------------------------------------------------------
  // 010: nedeljne liste plana, izvori, doprinosi i raspodela zalihe.

  static const _shoppingList = 'shopping_list';
  static const _shoppingItem = 'shopping_item';
  static const _source = 'shopping_source';
  static const _contribution = 'shopping_contribution';
  static const _allocation = 'supply_allocation';

  /// Lista nabavke bez plana (samostalni recepti i ručne stavke).
  Future<String> recipeList() => _ensureList();

  /// Kanonska lista za nedeljni deo plana: ista za isti plan i nedelju.
  Future<String> weekList(String planId, WeekPeriod period) =>
      _db.transaction(() async {
        final start = period.range.start.toWire();
        final existing =
            await (_db.select(_db.shoppingLists)..where(
                  (t) =>
                      t.householdId.equals(_scope.householdId) &
                      t.mealPlanId.equals(planId) &
                      t.periodStart.equals(start),
                ))
                .getSingleOrNull();
        if (existing != null) return existing.id;
        final id = newId();
        await _db
            .into(_db.shoppingLists)
            .insert(
              ShoppingListsCompanion.insert(
                id: id,
                name: 'Nedelja ${period.number}',
                mealPlanId: Value(planId),
                week: Value(period.number),
                periodStart: Value(start),
                periodEnd: Value(period.range.end.toWire()),
                createdAt: _clock().toUtc(),
                householdId: Value(_scope.householdId),
              ),
            );
        await _writer.upsert(_shoppingList, id);
        return id;
      });

  /// Stavke jedne liste (nedelje ili liste bez plana).
  Future<List<ShoppingItemRow>> listItems(String listId) =>
      (_db.select(_db.shoppingItems)
            ..where(
              (t) =>
                  t.listId.equals(listId) &
                  t.householdId.equals(_scope.householdId),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  Future<MealPlanRow?> _plan(String planId) =>
      (_db.select(_db.mealPlans)..where(
            (t) =>
                t.id.equals(planId) & t.householdId.equals(_scope.householdId),
          ))
          .getSingleOrNull();

  /// Promena stvarne zalihe osvežava postojeće potrebe svih izvora.
  Future<void> reconcileInventory() => _db.transaction(_reconcile);

  /// Usklađuje nabavku plana sa odobrenim obrocima: jedan izvor po obroku u
  /// listi njegove nedelje, pa doprinosi, raspodela zalihe i otvorene
  /// stavke. Ponovljen poziv bez promene ne menja ništa.
  Future<void> reconcilePlan(String planId) => _db.transaction(() async {
    final plan = await _plan(planId);
    if (plan == null) return;
    final range = DateRange(
      CivilDate.fromWire(plan.startDate),
      CivilDate.fromWire(plan.endDate),
    );
    final entries =
        await (_db.select(_db.mealPlanEntries)..where(
              (t) =>
                  t.planId.equals(planId) &
                  t.householdId.equals(_scope.householdId),
            ))
            .get();
    final planLists = {
      for (final l
          in await (_db.select(_db.shoppingLists)..where(
                (t) =>
                    t.mealPlanId.equals(planId) &
                    t.householdId.equals(_scope.householdId),
              ))
              .get())
        l.id,
    };
    final sources = {
      for (final s
          in await (_db.select(_db.shoppingSources)..where(
                (t) =>
                    t.householdId.equals(_scope.householdId) &
                    t.kind.equals(ShoppingSourceKind.planEntry.name) &
                    t.listId.isIn(planLists),
              ))
              .get())
        s.planEntryId!: s,
    };
    final now = _clock().toUtc();
    final kept = <String>{};
    for (final e in entries) {
      final period = periodFor(range, CivilDate.fromWire(e.date));
      // Obrok van kuće (i nepoznata vrsta) zauzima mesto bez nabavke.
      if (MealKind.parse(e.kind) != MealKind.cook ||
          e.recipeSnapshotJson == null ||
          period == null) {
        continue;
      }
      final listId = await weekList(planId, period);
      var source = sources[e.id];
      if (source != null && source.listId != listId) {
        // Obrok premešten u drugu nedelju: stari izvor oslobađa zalihu.
        await _deleteSource(source.id);
        source = null;
      }
      final closedAt = e.isCooked ? (source?.closedAt ?? now) : null;
      if (source == null) {
        final id = newId();
        await _db
            .into(_db.shoppingSources)
            .insert(
              ShoppingSourcesCompanion.insert(
                id: id,
                listId: listId,
                kind: ShoppingSourceKind.planEntry.name,
                planEntryId: Value(e.id),
                closedAt: Value(closedAt),
                createdAt: now,
                householdId: Value(_scope.householdId),
              ),
            );
        await _writer.upsert(_source, id);
        kept.add(id);
      } else {
        kept.add(source.id);
        if (source.closedAt != closedAt) {
          await (_db.update(_db.shoppingSources)
                ..where((t) => t.id.equals(source!.id)))
              .write(ShoppingSourcesCompanion(closedAt: Value(closedAt)));
          await _writer.upsert(_source, source.id);
        }
      }
    }
    // Obrok obrisan ili bez recepta: njegov izvor i neiskorišćena zaliha
    // se oslobađaju; kupljene stavke ostaju.
    for (final s in sources.values) {
      if (!kept.contains(s.id)) await _deleteSource(s.id);
    }
    await _reconcile();
  });

  /// Dodaje (ili menja) samostalnu pripremu recepta bez plana. Isto
  /// poreklo ([originKey]: recept iz biblioteke ili nesačuvan nacrt) menja
  /// postojeću otvorenu pripremu; [repeat] ("Ponovi nabavku") pravi novu, a
  /// stara ostaje istorija. Vraća id pripreme.
  Future<String> addRecipePreparation({
    required RecipeSnapshot snapshot,
    required int servings,
    required String originKey,
    String? recipeId,
    bool repeat = false,
  }) => _db.transaction(() async {
    if (servings < minServings || servings > maxServings) {
      throw ArgumentError.value(servings, 'servings', 'Porcije van opsega');
    }
    final listId = await _ensureList();
    final now = _clock().toUtc();
    final current =
        await (_db.select(_db.shoppingSources)
              ..where(
                (t) =>
                    t.householdId.equals(_scope.householdId) &
                    t.kind.equals(ShoppingSourceKind.recipePreparation.name) &
                    t.originKey.equals(originKey) &
                    t.supersededAt.isNull() &
                    t.closedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    final json = jsonEncode(snapshot.withCurrentDictionary().toJson());
    String id;
    if (current != null && !repeat) {
      id = current.id;
      if (current.recipeSnapshotJson != json || current.servings != servings) {
        await (_db.update(
          _db.shoppingSources,
        )..where((t) => t.id.equals(id))).write(
          ShoppingSourcesCompanion(
            recipeSnapshotJson: Value(json),
            servings: Value(servings),
          ),
        );
        await _writer.upsert(_source, id);
      }
    } else {
      if (current != null) {
        await (_db.update(_db.shoppingSources)
              ..where((t) => t.id.equals(current.id)))
            .write(ShoppingSourcesCompanion(supersededAt: Value(now)));
        await _writer.upsert(_source, current.id);
      }
      id = newId();
      await _db
          .into(_db.shoppingSources)
          .insert(
            ShoppingSourcesCompanion.insert(
              id: id,
              listId: listId,
              kind: ShoppingSourceKind.recipePreparation.name,
              recipeSnapshotJson: Value(json),
              servings: Value(servings),
              recipeId: Value(recipeId),
              originKey: Value(originKey),
              createdAt: now,
              householdId: Value(_scope.householdId),
            ),
          );
      await _writer.upsert(_source, id);
    }
    await _reconcile();
    return id;
  });

  /// Tekuća (nezamenjena, otvorena) priprema istog porekla, ili null.
  Future<RecipePreparation?> currentPreparation(String originKey) async {
    final row =
        await (_db.select(_db.shoppingSources)
              ..where(
                (t) => _activePreparation(t) & t.originKey.equals(originKey),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _preparation(row);
  }

  /// Tekuće samostalne pripreme, novije prve, uživo.
  Stream<List<RecipePreparation>> watchPreparations() =>
      (_db.select(_db.shoppingSources)
            ..where(_activePreparation)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch()
          .map((rows) => [for (final r in rows) ?_preparation(r)]);

  Expression<bool> _activePreparation($ShoppingSourcesTable t) =>
      t.householdId.equals(_scope.householdId) &
      t.kind.equals(ShoppingSourceKind.recipePreparation.name) &
      t.supersededAt.isNull() &
      t.closedAt.isNull();

  static RecipePreparation? _preparation(ShoppingSourceRow row) {
    final json = row.recipeSnapshotJson;
    if (json == null) return null;
    try {
      final snapshot = RecipeSnapshot.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      return RecipePreparation(
        id: row.id,
        snapshot: snapshot,
        servings: row.servings ?? snapshot.baseServings,
        recipeId: row.recipeId,
      );
    } on FormatException {
      return null;
    }
  }

  /// Recept je u nekom planu kao obrok koji još nije skuvan.
  Future<bool> isPlanned(String recipeId) async =>
      await (_db.select(_db.mealPlanEntries)
            ..where(
              (t) =>
                  t.householdId.equals(_scope.householdId) &
                  t.recipeId.equals(recipeId) &
                  t.isCooked.equals(false) &
                  t.kind.equals(MealKind.cook.name),
            )
            ..limit(1))
          .getSingleOrNull() !=
      null;

  /// Uklanja izvor (npr. samostalnu pripremu): oslobađa njegovu zalihu i
  /// otvorenu potrebu; kupljeno ostaje.
  Future<void> removeSource(String sourceId) => _db.transaction(() async {
    await _deleteSource(sourceId);
    await _reconcile();
  });

  /// Stavke jedne liste, uživo (UI čita iz lokalnog keša).
  Stream<List<ShoppingItemRow>> watchListItems(String listId) =>
      (_db.select(_db.shoppingItems)
            ..where(
              (t) =>
                  t.listId.equals(listId) &
                  t.householdId.equals(_scope.householdId),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  /// Sve stavke nedeljnih lista plana, uživo, uz početak nedelje.
  Stream<List<PlanShoppingItem>> watchPlanItems(String planId) {
    final q =
        _db.select(_db.shoppingItems).join([
            innerJoin(
              _db.shoppingLists,
              _db.shoppingLists.id.equalsExp(_db.shoppingItems.listId),
            ),
          ])
          ..where(
            _db.shoppingLists.mealPlanId.equals(planId) &
                _db.shoppingLists.periodStart.isNotNull() &
                _db.shoppingItems.householdId.equals(_scope.householdId),
          )
          ..orderBy([OrderingTerm.asc(_db.shoppingItems.name)]);
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          PlanShoppingItem(
            weekStart: CivilDate.fromWire(
              r.readTable(_db.shoppingLists).periodStart!,
            ),
            item: r.readTable(_db.shoppingItems),
          ),
      ],
    );
  }

  /// Stavke liste bez plana (recepti i ručne stavke), uživo. Ne pravi listu.
  Stream<List<ShoppingItemRow>> watchRecipeItems() {
    final q =
        _db.select(_db.shoppingItems).join([
            innerJoin(
              _db.shoppingLists,
              _db.shoppingLists.id.equalsExp(_db.shoppingItems.listId),
            ),
          ])
          ..where(
            _db.shoppingLists.mealPlanId.isNull() &
                _db.shoppingItems.householdId.equals(_scope.householdId),
          )
          ..orderBy([OrderingTerm.asc(_db.shoppingItems.name)]);
    return q.watch().map(
      (rows) => [for (final r in rows) r.readTable(_db.shoppingItems)],
    );
  }

  /// Brza ručna stavka u listi; usklađivanje je nikad ne menja.
  Future<String> addManual(
    String listId,
    String name, {
    double? quantity,
    String? unit,
    String category = 'ostalo',
  }) => _db.transaction(() async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'Prazno ime');
    final id = newId();
    await _db
        .into(_db.shoppingItems)
        .insert(
          ShoppingItemsCompanion.insert(
            id: id,
            listId: listId,
            name: trimmed,
            quantity: Value(quantity),
            unit: Value(unit),
            category: category,
            isManual: const Value(true),
            householdId: Value(_scope.householdId),
          ),
        );
    await _writer.upsert(_shoppingItem, id);
    return id;
  });

  /// Briše ručnu stavku koja nije kupljena; ostale stavke se ne brišu ovde.
  Future<bool> deleteManual(String itemId) => _db.transaction(() async {
    final item = await _item(itemId);
    if (item == null || !item.isManual || item.isBought) return false;
    await (_db.delete(
      _db.shoppingItems,
    )..where((t) => t.id.equals(itemId))).go();
    await _writer.delete(_shoppingItem, itemId);
    if (item.photoPath case final p?) {
      await _writer.photoDelete(p, delay: const Duration(seconds: 30));
    }
    return true;
  });

  /// Vraća ručno obrisanu stavku sa svim detaljima dok je dostupno „Vrati”.
  Future<void> restoreManual(ShoppingItemRow item) => _db.transaction(() async {
    if (item.householdId != _scope.householdId ||
        !item.isManual ||
        item.isBought) {
      return;
    }
    if (item.photoPath case final path?) await _writer.cancelPhotoDelete(path);
    final id = await addManual(
      item.listId,
      item.name,
      quantity: item.quantity,
      unit: item.unit,
      category: item.category,
    );
    await updateDetails(
      id,
      brand: item.brand,
      note: item.note,
      photoPath: item.photoPath,
    );
  });

  /// Menja samo opis proizvoda, bez uticaja na obračun nabavke.
  Future<bool> updateDetails(
    String id, {
    String? brand,
    String? note,
    String? photoPath,
  }) => _db.transaction(() async {
    final item = await _item(id);
    if (item == null) return false;
    String? clean(String? value) {
      final trimmed = value?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    }

    final cleanBrand = clean(brand);
    final cleanNote = clean(note);
    if ((cleanBrand?.length ?? 0) > 120 || (cleanNote?.length ?? 0) > 1000) {
      throw ArgumentError('Detalji su predugački');
    }
    await (_db.update(_db.shoppingItems)..where(
          (t) => t.id.equals(id) & t.householdId.equals(_scope.householdId),
        ))
        .write(
          ShoppingItemsCompanion(
            brand: Value(cleanBrand),
            note: Value(cleanNote),
            photoPath: Value(photoPath),
          ),
        );
    await _writer.upsert(_shoppingItem, id);
    if (photoPath != item.photoPath) {
      if (photoPath != null) await _writer.photoUpload(photoPath);
      if (item.photoPath case final old?) await _writer.photoDelete(old);
    }
    return true;
  });

  Future<ShoppingItemRow?> _item(String id) =>
      (_db.select(_db.shoppingItems)..where(
            (t) => t.id.equals(id) & t.householdId.equals(_scope.householdId),
          ))
          .getSingleOrNull();

  /// Obroci i pripreme za koje je stavka: za otvorenu iz tekućih doprinosa,
  /// za kupljenu iz zamrznutog porekla kupovine.
  Future<List<ItemSource>> itemSources(String itemId) async {
    final item = await _item(itemId);
    if (item == null) return const [];
    if (item.isBought) return provenanceSources(item.purchaseProvenanceJson);
    return _currentSources(itemId);
  }

  Future<List<ItemSource>> _currentSources(String itemId) async {
    final contributions =
        await (_db.select(_db.shoppingContributions)..where(
              (t) =>
                  t.shoppingItemId.equals(itemId) &
                  t.householdId.equals(_scope.householdId),
            ))
            .get();
    final sources =
        await (_db.select(_db.shoppingSources)..where(
              (t) => t.id.isIn({for (final c in contributions) c.sourceId}),
            ))
            .get();
    final entries = {
      for (final e
          in await (_db.select(_db.mealPlanEntries)..where(
                (t) => t.id.isIn([for (final s in sources) ?s.planEntryId]),
              ))
              .get())
        e.id: e,
    };
    final result = <(DemandOrder, ItemSource)>[];
    for (final s in sources) {
      final entry = entries[s.planEntryId];
      final json = entry?.recipeSnapshotJson ?? s.recipeSnapshotJson;
      if (json == null) continue;
      final RecipeSnapshot snapshot;
      try {
        snapshot = RecipeSnapshot.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );
      } on FormatException {
        continue;
      }
      final date = entry == null ? null : CivilDate.fromWire(entry.date);
      result.add((
        DemandOrder(
          date: date?.toWire(),
          mealOrder: entry == null ? 3 : mealOrder(entry.mealType),
        ),
        ItemSource(
          title: snapshot.title,
          kind: ShoppingSourceKind.values.asNameMap()[s.kind],
          servings:
              (entry == null ? s.servings : entry.servings) ??
              snapshot.baseServings,
          date: date,
          mealType: entry?.mealType,
        ),
      ));
    }
    result.sort((a, b) {
      final (da, db) = (a.$1.date, b.$1.date);
      if (da != db) {
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      }
      return a.$1.mealOrder.compareTo(b.$1.mealOrder);
    });
    return [for (final (_, s) in result) s];
  }

  /// Kupljeno ili poništeno, cela stavka odjednom. Kupovina zamrzava izvore
  /// i pokriva baš one obroke za koje je stavka bila; poništavanje vraća
  /// istu stavku u nabavku. Stavka primljena u ostavu se ne poništava (ista
  /// zaliha je već u ostavi). Ponovljen poziv ne menja ništa. Vraća broj
  /// promenjenih stavki.
  Future<int> setBought(Iterable<String> itemIds, {required bool bought}) =>
      _db.transaction(() async {
        var changed = 0;
        for (final id in itemIds.toSet()) {
          final item = await _item(id);
          if (item == null || item.isBought == bought) continue;
          if (bought) {
            await _buy(item);
          } else {
            if (await _isReceived(id)) continue;
            await _unbuy(item);
          }
          changed++;
        }
        if (changed > 0) await _reconcile();
        return changed;
      });

  Future<bool> _isReceived(String itemId) async =>
      await (_db.select(_db.pantryItems)..where(
            (t) =>
                t.sourceShoppingItemId.equals(itemId) &
                t.householdId.equals(_scope.householdId),
          ))
          .getSingleOrNull() !=
      null;

  Future<void> _buy(ShoppingItemRow item) async {
    final hid = _scope.householdId;
    final now = _clock().toUtc();
    final contributions =
        await (_db.select(_db.shoppingContributions)..where(
              (t) =>
                  t.shoppingItemId.equals(item.id) & t.householdId.equals(hid),
            ))
            .get();
    var quantity = item.quantity;
    var unit = item.unit;
    if (contributions.isNotEmpty) {
      // Stavka pokriva tačno ono što je preostalo njenim obrocima: zaliha
      // ide njima, ne nekom ranijem obroku iste namirnice.
      final allocated = <String, int>{};
      for (final a
          in await (_db.select(_db.supplyAllocations)..where(
                (t) => t.contributionId.isIn([
                  for (final c in contributions) c.id,
                ]),
              ))
              .get()) {
        allocated[a.contributionId] =
            (allocated[a.contributionId] ?? 0) + (a.micros ?? 0);
      }
      var total = 0;
      for (final c in contributions) {
        final micros = c.micros == null
            ? null
            : c.micros! - (allocated[c.id] ?? 0);
        if (micros != null && micros <= 0) continue;
        total += micros ?? 0;
        final id = newId();
        await _db
            .into(_db.supplyAllocations)
            .insert(
              SupplyAllocationsCompanion.insert(
                id: id,
                contributionId: c.id,
                purchasedShoppingItemId: Value(item.id),
                micros: Value(micros),
                coversWholeUnknown: Value(micros == null),
                createdAt: now,
                householdId: Value(hid),
              ),
            );
        await _writer.upsertLast(_allocation, id);
      }
      // Prikaz u kg/l može da zaokruži; kupovina čuva tačan zbir.
      final known = contributions.first.micros != null;
      if (known &&
          (item.quantity == null ||
              toMicros(item.quantity!) * normalizeUnit(item.unit).factor !=
                  total)) {
        quantity = fromMicros(total);
        unit = contributions.first.baseUnit;
      }
    }
    await (_db.update(
      _db.shoppingItems,
    )..where((t) => t.id.equals(item.id))).write(
      ShoppingItemsCompanion(
        isBought: const Value(true),
        quantity: Value(quantity),
        unit: Value(unit),
        purchaseProvenanceJson: Value(
          contributions.isEmpty
              ? null
              : provenanceJson(await _currentSources(item.id)),
        ),
      ),
    );
    await _writer.upsert(_shoppingItem, item.id);
  }

  Future<void> _unbuy(ShoppingItemRow item) async {
    for (final a
        in await (_db.select(_db.supplyAllocations)..where(
              (t) =>
                  t.purchasedShoppingItemId.equals(item.id) &
                  t.householdId.equals(_scope.householdId),
            ))
            .get()) {
      await (_db.delete(
        _db.supplyAllocations,
      )..where((t) => t.id.equals(a.id))).go();
      await _writer.delete(_allocation, a.id);
    }
    await (_db.update(
      _db.shoppingItems,
    )..where((t) => t.id.equals(item.id))).write(
      const ShoppingItemsCompanion(
        isBought: Value(false),
        purchaseProvenanceJson: Value(null),
      ),
    );
    await _writer.upsert(_shoppingItem, item.id);
    // Stavka iz obroka se vraća kao ta ista otvorena stavka (ili briše ako je
    // u međuvremenu sve pokriveno); ručna i stara ostaju kakve jesu.
    if (provenanceSources(item.purchaseProvenanceJson).isNotEmpty &&
        !item.isManual) {
      _reopened.add(item.id);
    }
  }

  /// Zbir celog plana po namirnici, iz nedeljnih lista (samo čitanje).
  Future<List<PlanTotal>> planTotals(String planId) async {
    final lists =
        await (_db.select(_db.shoppingLists)..where(
              (t) =>
                  t.mealPlanId.equals(planId) &
                  t.householdId.equals(_scope.householdId) &
                  t.periodStart.isNotNull(),
            ))
            .get();
    final items =
        await (_db.select(_db.shoppingItems)..where(
              (t) =>
                  t.listId.isIn([for (final l in lists) l.id]) &
                  t.householdId.equals(_scope.householdId),
            ))
            .get();
    final contributions =
        await (_db.select(_db.shoppingContributions)..where(
              (t) =>
                  t.shoppingItemId.isIn([for (final i in items) i.id]) &
                  t.householdId.equals(_scope.householdId),
            ))
            .get();
    return totalsOf(
      items,
      identities: {
        for (final c in contributions)
          if (c.shoppingItemId != null)
            c.shoppingItemId!: (c.ingredientKey, c.unitGroup),
      },
    );
  }

  /// Zbir stavki po namirnici i grupi jedinica (za prikaz celog plana).
  static List<PlanTotal> totalsOf(
    List<ShoppingItemRow> items, {
    Map<String, (String, String)> identities = const {},
  }) {
    final groups = <(String, String), List<ShoppingItemRow>>{};
    for (final i in items) {
      final unit = normalizeUnit(i.unit);
      final group = i.quantity == null ? unknownGroup : unit.group;
      final identity = identities[i.id] ?? (ingredientKey(i.name), group);
      groups.putIfAbsent(identity, () => []).add(i);
    }
    int micros(ShoppingItemRow i) => i.quantity == null
        ? 0
        : toMicros(i.quantity!) * normalizeUnit(i.unit).factor;
    return [
      for (final MapEntry(key: (ingredient, group), value: rows)
          in groups.entries)
        PlanTotal(
          ingredient: ingredient,
          unitGroup: group,
          name: rows.first.name,
          category: rows.first.category,
          baseUnit: normalizeUnit(rows.first.unit).base,
          openMicros: rows
              .where((r) => !r.isBought)
              .fold(0, (sum, r) => sum + micros(r)),
          boughtMicros: rows
              .where((r) => r.isBought)
              .fold(0, (sum, r) => sum + micros(r)),
          hasUnknown: rows.any((r) => !r.isBought && r.quantity == null),
          itemIds: [for (final r in rows) r.id],
          listIds: {for (final r in rows) r.listId}.toList(),
        ),
    ];
  }

  /// Briše izvor i njegovu decu (deca pre roditelja, i u outbox-u).
  Future<void> _deleteSource(String sourceId) async {
    final contributions = await (_db.select(
      _db.shoppingContributions,
    )..where((t) => t.sourceId.equals(sourceId))).get();
    for (final c in contributions) {
      await _deleteContribution(c.id);
    }
    await (_db.delete(
      _db.shoppingSources,
    )..where((t) => t.id.equals(sourceId))).go();
    await _writer.delete(_source, sourceId);
  }

  /// Stavke čiji su doprinosi obrisani u ovoj transakciji: posle
  /// usklađivanja se brišu ako ih više ništa ne traži.
  final _released = <String>{};

  /// Poništene kupovine iz obroka: usklađivanje ih vraća kao otvorene
  /// stavke iste grupe (isti id) ili briše ako više nisu potrebne.
  final _reopened = <String>{};

  Future<void> _deleteContribution(String id) async {
    final row = await (_db.select(
      _db.shoppingContributions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row?.shoppingItemId case final itemId?) _released.add(itemId);
    final allocations = await (_db.select(
      _db.supplyAllocations,
    )..where((t) => t.contributionId.equals(id))).get();
    for (final a in allocations) {
      await (_db.delete(
        _db.supplyAllocations,
      )..where((t) => t.id.equals(a.id))).go();
      await _writer.delete(_allocation, a.id);
    }
    await (_db.delete(
      _db.shoppingContributions,
    )..where((t) => t.id.equals(id))).go();
    await _writer.delete(_contribution, id);
  }

  /// Potrebe izvora iz odobrenog recepta i porcija; prazno kad recept nije
  /// čitljiv.
  List<DemandLine> _demand(
    ShoppingSourceRow s,
    Map<String, MealPlanEntryRow> entries,
  ) {
    final entry = entries[s.planEntryId];
    final json = s.planEntryId == null
        ? s.recipeSnapshotJson
        : entry?.recipeSnapshotJson;
    if (json == null) return const [];
    final RecipeSnapshot snapshot;
    try {
      snapshot = RecipeSnapshot.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } on FormatException {
      return const [];
    }
    final servings = (s.planEntryId == null ? s.servings : entry?.servings);
    return demandFor(
      DemandSource(
        id: s.id,
        baseServings: snapshot.baseServings,
        servings: (servings ?? snapshot.baseServings).clamp(
          minServings,
          maxServings,
        ),
        ingredients: snapshot.ingredients,
        dictionaryVersion: snapshot.dictionaryVersion,
      ),
    );
  }

  /// Celo domaćinstvo: doprinosi otvorenih izvora prate odobrene recepte,
  /// potvrđena zaliha se raspoređuje hronološki, a otvorene stavke
  /// pokazuju samo ono što preostaje. Kupljene, ručne i stare stavke se ne
  /// menjaju.
  Future<void> _reconcile() async {
    final hid = _scope.householdId;
    final now = _clock().toUtc();
    final sources = await (_db.select(
      _db.shoppingSources,
    )..where((t) => t.householdId.equals(hid))).get();
    final entries = {
      for (final e
          in await (_db.select(_db.mealPlanEntries)..where(
                (t) => t.id.isIn([for (final s in sources) ?s.planEntryId]),
              ))
              .get())
        e.id: e,
    };

    // 1. Doprinosi: jedan po izvoru + sastojku + grupi jedinica. Zatvoreni i
    // zamenjeni izvori se ne preračunavaju.
    final contributions = <String, ShoppingContributionRow>{
      for (final c in await (_db.select(
        _db.shoppingContributions,
      )..where((t) => t.householdId.equals(hid))).get())
        c.id: c,
    };
    final changed = <String>{};
    for (final s in sources) {
      if (s.closedAt != null || s.supersededAt != null) continue;
      final existing = {
        for (final c in contributions.values)
          if (c.sourceId == s.id) (c.ingredientKey, c.unitGroup): c,
      };
      for (final line in _demand(s, entries)) {
        final key = (line.key.ingredient, line.key.unitGroup);
        final prev = existing.remove(key);
        final notes = jsonEncode(line.notes);
        if (prev != null &&
            prev.micros == line.micros &&
            prev.name == line.name &&
            prev.category == line.category &&
            prev.baseUnit == line.baseUnit &&
            prev.notesJson == notes) {
          continue;
        }
        final row = ShoppingContributionsCompanion(
          id: Value(prev?.id ?? newId()),
          householdId: Value(hid),
          shoppingItemId: Value(prev?.shoppingItemId),
          sourceId: Value(s.id),
          ingredientKey: Value(line.key.ingredient),
          unitGroup: Value(line.key.unitGroup),
          baseUnit: Value(line.baseUnit),
          micros: Value(line.micros),
          name: Value(line.name),
          category: Value(line.category),
          notesJson: Value(notes),
        );
        await _db.into(_db.shoppingContributions).insertOnConflictUpdate(row);
        contributions[row.id.value] = await (_db.select(
          _db.shoppingContributions,
        )..where((t) => t.id.equals(row.id.value))).getSingle();
        changed.add(row.id.value);
      }
      for (final gone in existing.values) {
        await _deleteContribution(gone.id);
        contributions.remove(gone.id);
      }
    }

    // 2. Zaliha: potvrđena ostava (koja nije istekla) i kupljene stavke.
    // Prijem kupovine u ostavu je ista zaliha kao ta kupovina.
    final supplies = <Supply>[];
    final received = <String, PantryItemRow>{};
    for (final p
        in await (_db.select(_db.pantryItems)..where(
              (t) =>
                  t.householdId.equals(hid) &
                  (t.confirmedAt.isNotNull() |
                      t.sourceShoppingItemId.isNotNull()),
            ))
            .get()) {
      final expired = p.expiresAt?.isBefore(now) ?? false;
      if (p.sourceShoppingItemId case final purchase?) received[purchase] = p;
      final known = p.confirmedAt != null && p.quantity != null;
      if (p.sourceShoppingItemId == null && (!known || expired)) continue;
      final unit = normalizeUnit(p.unit);
      supplies.add(
        Supply(
          id: p.id,
          origin: SupplyOrigin.pantry,
          ingredient: ingredientKey(p.name),
          unitGroup: unit.group,
          dictionaryIngredient: dictionaryIngredientKey(p.name, 1),
          dictionaryUnitGroup: normalizeUnit(
            p.unit,
            dictionaryVersion: 1,
          ).group,
          micros: !known || expired ? 0 : toMicros(p.quantity!) * unit.factor,
          samePhysicalAs: p.sourceShoppingItemId,
        ),
      );
    }
    for (final i
        in await (_db.select(_db.shoppingItems)..where(
              (t) =>
                  t.householdId.equals(hid) &
                  t.isBought.equals(true) &
                  t.quantity.isNotNull(),
            ))
            .get()) {
      final unit = normalizeUnit(i.unit);
      supplies.add(
        Supply(
          id: i.id,
          origin: SupplyOrigin.purchase,
          ingredient: ingredientKey(i.name),
          unitGroup: unit.group,
          dictionaryIngredient: dictionaryIngredientKey(i.name, 1),
          dictionaryUnitGroup: normalizeUnit(
            i.unit,
            dictionaryVersion: 1,
          ).group,
          micros: toMicros(i.quantity!) * unit.factor,
        ),
      );
    }
    final capacity = <String, Supply>{};
    for (final s in supplies) {
      final prev = capacity[s.canonicalId];
      if (prev == null || s.samePhysicalAs != null) capacity[s.canonicalId] = s;
    }

    // 3. Postojeća raspodela: zadržava se, ali ne preko potrebe doprinosa
    // ni preko zalihe (kasniji obroci prvi gube).
    final sourceById = {for (final s in sources) s.id: s};
    DemandOrder orderOf(ShoppingContributionRow c) {
      final s = sourceById[c.sourceId];
      final e = entries[s?.planEntryId];
      return e == null
          ? const DemandOrder()
          : DemandOrder(
              date: CivilDate.fromWire(e.date).toWire(),
              mealOrder: mealOrder(e.mealType),
            );
    }

    int compareContributions(
      ShoppingContributionRow a,
      ShoppingContributionRow b,
    ) {
      final oa = orderOf(a), ob = orderOf(b);
      if (oa.date != ob.date) {
        if (oa.date == null) return 1;
        if (ob.date == null) return -1;
        final c = oa.date!.compareTo(ob.date!);
        if (c != 0) return c;
      }
      final m = oa.mealOrder.compareTo(ob.mealOrder);
      return m != 0 ? m : a.sourceId.compareTo(b.sourceId);
    }

    final allocations = await (_db.select(
      _db.supplyAllocations,
    )..where((t) => t.householdId.equals(hid))).get();
    final kept = <SupplyAllocationRow>[];
    final latestFirst = [...allocations]
      ..sort((a, b) {
        final ca = contributions[a.contributionId];
        final cb = contributions[b.contributionId];
        if (ca == null || cb == null) return 0;
        return compareContributions(cb, ca);
      });
    final used = <String, int>{};
    final perContribution = <String, int>{};
    // Prvo po hronologiji: raniji obroci zadržavaju zalihu.
    for (final a in latestFirst.reversed) {
      final c = contributions[a.contributionId];
      final supply = capacity[a.supplyId];
      if (c == null) continue;
      if (a.coversWholeUnknown) {
        final receipt = received[a.supplyId];
        if (receipt != null &&
            (receipt.quantity == 0 ||
                (receipt.expiresAt?.isBefore(now) ?? false) ||
                ingredientKey(receipt.name) != c.ingredientKey)) {
          await (_db.delete(
            _db.supplyAllocations,
          )..where((t) => t.id.equals(a.id))).go();
          await _writer.delete(_allocation, a.id);
        } else {
          kept.add(a);
        }
        continue;
      }
      final matches =
          supply?.ingredient == c.ingredientKey &&
          supply?.unitGroup == c.unitGroup;
      final cap = matches ? (supply?.micros ?? 0) : 0;
      final room = cap - (used[a.supplyId] ?? 0);
      final need = (c.micros ?? 0) - (perContribution[c.id] ?? 0);
      final keep = [a.micros ?? 0, room, need].reduce((x, y) => x < y ? x : y);
      if (keep <= 0) {
        await (_db.delete(
          _db.supplyAllocations,
        )..where((t) => t.id.equals(a.id))).go();
        await _writer.delete(_allocation, a.id);
        continue;
      }
      if (keep != a.micros) {
        await (_db.update(_db.supplyAllocations)
              ..where((t) => t.id.equals(a.id)))
            .write(SupplyAllocationsCompanion(micros: Value(keep)));
        await _writer.upsertLast(_allocation, a.id);
      }
      used[a.supplyId] = (used[a.supplyId] ?? 0) + keep;
      perContribution[c.id] = (perContribution[c.id] ?? 0) + keep;
      kept.add(a);
    }

    // 4. Nova raspodela za ono što preostaje otvorenim izvorima.
    bool isOpen(ShoppingContributionRow c) =>
        sourceById[c.sourceId]?.closedAt == null;
    final requests = [
      for (final c in contributions.values)
        if (isOpen(c) && c.micros != null)
          DemandRequest(
            DemandLine(
              key: (
                sourceId: c.id,
                ingredient: c.ingredientKey,
                unitGroup: c.unitGroup,
              ),
              name: c.name,
              category: c.category,
              micros: c.micros! - (perContribution[c.id] ?? 0),
              baseUnit: c.baseUnit,
            ),
            orderOf(c),
          ),
    ];
    final result = allocateSupply(requests, [
      for (final s in capacity.values)
        Supply(
          id: s.canonicalId,
          origin: s.origin,
          ingredient: s.ingredient,
          unitGroup: s.unitGroup,
          dictionaryIngredient: s.dictionaryIngredient,
          dictionaryUnitGroup: s.dictionaryUnitGroup,
          micros: (s.micros ?? 0) - (used[s.canonicalId] ?? 0),
        ),
    ]);
    final purchases = {
      for (final s in supplies)
        if (s.origin == SupplyOrigin.purchase) s.id,
    };
    for (final a in result.allocations) {
      final contributionId = a.demand.sourceId;
      final same = kept
          .where(
            (k) =>
                k.contributionId == contributionId && k.supplyId == a.supplyId,
          )
          .firstOrNull;
      if (same != null) {
        final micros = (same.micros ?? 0) + a.micros;
        await (_db.update(_db.supplyAllocations)
              ..where((t) => t.id.equals(same.id)))
            .write(SupplyAllocationsCompanion(micros: Value(micros)));
        await _writer.upsertLast(_allocation, same.id);
      } else {
        final id = newId();
        final purchase = purchases.contains(a.supplyId);
        await _db
            .into(_db.supplyAllocations)
            .insert(
              SupplyAllocationsCompanion.insert(
                id: id,
                contributionId: contributionId,
                pantryItemId: Value(purchase ? null : a.supplyId),
                purchasedShoppingItemId: Value(purchase ? a.supplyId : null),
                micros: Value(a.micros),
                createdAt: now,
                householdId: Value(hid),
              ),
            );
        await _writer.upsertLast(_allocation, id);
      }
      perContribution[contributionId] =
          (perContribution[contributionId] ?? 0) + a.micros;
    }

    // 5. Otvorene stavke: po listi i grupi, zbir onoga što preostaje.
    final wholeUnknown = {
      for (final a in kept)
        if (a.coversWholeUnknown) a.contributionId,
    };
    int? remaining(ShoppingContributionRow c) => c.micros == null
        ? (wholeUnknown.contains(c.id) ? 0 : null)
        : c.micros! - (perContribution[c.id] ?? 0);

    final items = {
      for (final i in await (_db.select(
        _db.shoppingItems,
      )..where((t) => t.householdId.equals(hid))).get())
        i.id: i,
    };
    final groups = <(String, String, String), List<ShoppingContributionRow>>{};
    for (final c in contributions.values) {
      final s = sourceById[c.sourceId];
      if (s == null) continue;
      groups
          .putIfAbsent((s.listId, c.ingredientKey, c.unitGroup), () => [])
          .add(c);
    }
    final pointed = <String, String?>{};
    final liveItems = <String>{};
    for (final MapEntry(key: (listId, ingredient, group), value: cs)
        in groups.entries) {
      cs.sort(compareContributions);
      final open = [
        for (final c in cs)
          if (isOpen(c) && remaining(c) != 0) c,
      ];
      // Postojeća otvorena stavka ove grupe (ne kupljena, ne ručna), ili
      // upravo poništena kupovina iste grupe.
      final current =
          [
            for (final c in cs)
              if (items[c.shoppingItemId] case final i?
                  when !i.isBought && !i.isManual && i.listId == listId)
                i,
          ].firstOrNull ??
          [
            for (final id in _reopened)
              if (items[id] case final i?
                  when !i.isBought &&
                      i.listId == listId &&
                      dictionaryIngredientKey(
                            i.name,
                            ingredient.startsWith('v1:') ? 1 : 0,
                          ) ==
                          ingredient &&
                      (i.quantity == null
                              ? unknownGroup
                              : normalizeUnit(
                                  i.unit,
                                  dictionaryVersion:
                                      ingredient.startsWith('v1:') ? 1 : 0,
                                ).group) ==
                          group &&
                      !liveItems.contains(id))
                i,
          ].firstOrNull;
      if (open.isEmpty) {
        for (final c in cs) {
          pointed[c.id] = null;
        }
        continue;
      }
      final unknown = open.any((c) => remaining(c) == null);
      final total = unknown
          ? null
          : open.fold<int>(0, (sum, c) => sum + remaining(c)!);
      final amount = total == null
          ? null
          : displayAmount(total, open.first.baseUnit);
      final recipeIds = <String>{
        for (final c in open)
          if (sourceById[c.sourceId] case final s?)
            ?(s.recipeId ?? entries[s.planEntryId]?.recipeId),
      }.toList();
      // Ime i kategorija od najranijeg obroka grupe, da se ne menjaju kad
      // se raspodela pomeri.
      final row = ShoppingItemsCompanion(
        name: Value(cs.first.name),
        quantity: Value(amount?.quantity),
        unit: Value(group == unknownGroup ? null : amount?.unit),
        category: Value(cs.first.category),
        fromRecipeIdsJson: Value(jsonEncode(recipeIds)),
      );
      String itemId;
      if (current == null) {
        itemId = newId();
        await _db
            .into(_db.shoppingItems)
            .insert(
              row.copyWith(
                id: Value(itemId),
                listId: Value(listId),
                householdId: Value(hid),
              ),
            );
        await _writer.upsert(_shoppingItem, itemId);
      } else {
        itemId = current.id;
        if (current.name != row.name.value ||
            current.quantity != row.quantity.value ||
            current.unit != row.unit.value ||
            current.category != row.category.value ||
            current.fromRecipeIdsJson != row.fromRecipeIdsJson.value) {
          await (_db.update(
            _db.shoppingItems,
          )..where((t) => t.id.equals(itemId))).write(row);
          await _writer.upsert(_shoppingItem, itemId);
        }
      }
      liveItems.add(itemId);
      for (final c in cs) {
        pointed[c.id] = open.contains(c) ? itemId : null;
      }
    }
    // Doprinos na novu stavku ide posle nje u outbox-u.
    for (final MapEntry(key: id, value: itemId) in pointed.entries) {
      final c = contributions[id]!;
      if (c.shoppingItemId == itemId && !changed.contains(id)) continue;
      if (c.shoppingItemId != itemId) {
        await (_db.update(
          _db.shoppingContributions,
        )..where((t) => t.id.equals(id))).write(
          ShoppingContributionsCompanion(shoppingItemId: Value(itemId)),
        );
      }
      await _writer.upsertLast(_contribution, id);
      for (final a in await (_db.select(
        _db.supplyAllocations,
      )..where((t) => t.contributionId.equals(id))).get()) {
        await _writer.upsertLast(_allocation, a.id);
      }
    }
    // Otvorene stavke koje više ništa ne traži se brišu.
    final candidates = {
      ..._released,
      ..._reopened,
      for (final c in contributions.values) ?c.shoppingItemId,
    };
    _released.clear();
    _reopened.clear();
    for (final id in candidates) {
      final old = items[id];
      if (old == null || old.isBought || old.isManual) continue;
      if (liveItems.contains(id)) continue;
      await (_db.delete(_db.shoppingItems)..where((t) => t.id.equals(id))).go();
      await _writer.delete(_shoppingItem, id);
      if (old.photoPath case final p?) await _writer.photoDelete(p);
      items.remove(id);
    }
  }
}
