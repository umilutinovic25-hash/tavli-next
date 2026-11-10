import 'package:drift/drift.dart';

import '../account/auth_controller.dart';
import '../domain/ids.dart';
import '../domain/use_first.dart';
import '../sync/synced_writer.dart';
import 'database.dart';
import 'shopping_repository.dart';

class PantryItemMissing implements Exception {
  const PantryItemMissing();
}

/// Ostava domaćinstva; svaka izmena ima outbox u istoj transakciji.
class PantryRepository {
  PantryRepository(
    this._db, {
    required this._scope,
    required this._writer,
    required this._shopping,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final AccountScope _scope;
  final SyncedWriter _writer;
  final ShoppingRepository _shopping;
  final DateTime Function() _clock;

  static const _pantryItem = 'pantry_item';

  /// Nulte evidencije prijema čuvaju identitet kupovine, ne prikazuju se
  /// kao aktivna zaliha. Nepoznata količina je vidljiva i traži potvrdu.
  Stream<List<PantryItemRow>> watchItems() =>
      (_db.select(_db.pantryItems)
            ..where(
              (t) =>
                  t.householdId.equals(_scope.householdId) &
                  (t.quantity.isNull() | t.quantity.isBiggerThanValue(0)),
            )
            ..orderBy([
              (t) => OrderingTerm.asc(t.name),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .watch();

  Future<String> create({
    required String name,
    double? quantity,
    String? unit,
    String category = 'ostalo',
    DateTime? expiresAt,
  }) {
    _validate(name, quantity);
    return _db.transaction(() async {
      final id = newId();
      final now = _clock().toUtc();
      await _db
          .into(_db.pantryItems)
          .insert(
            PantryItemsCompanion.insert(
              id: id,
              name: name.trim(),
              category: category,
              addedAt: now,
              quantity: Value(quantity),
              unit: Value(_unit(unit)),
              householdId: Value(_scope.householdId),
              expiresAt: Value(expiresAt?.toUtc()),
              confirmedAt: Value(quantity == null ? null : now),
            ),
          );
      await _writer.upsert(_pantryItem, id);
      await _shopping.reconcileInventory();
      return id;
    });
  }

  Future<void> update(
    String id, {
    required String name,
    double? quantity,
    String? unit,
    String category = 'ostalo',
    DateTime? expiresAt,
  }) {
    _validate(name, quantity);
    return _db.transaction(() async {
      await _existing(id);
      await (_db.update(_db.pantryItems)..where(
            (t) => t.id.equals(id) & t.householdId.equals(_scope.householdId),
          ))
          .write(
            PantryItemsCompanion(
              name: Value(name.trim()),
              quantity: Value(quantity),
              unit: Value(_unit(unit)),
              category: Value(category),
              expiresAt: Value(expiresAt?.toUtc()),
              confirmedAt: Value(quantity == null ? null : _clock().toUtc()),
            ),
          );
      await _writer.upsert(_pantryItem, id);
      await _shopping.reconcileInventory();
    });
  }

  Future<void> remove(String id) => _db.transaction(() async {
    final item = await _existing(id);
    if (item.sourceShoppingItemId != null) {
      // Sačuvaj prijem i nultu zalihu: stara kupovina ne sme oživeti.
      await (_db.update(_db.pantryItems)..where(
            (t) => t.id.equals(id) & t.householdId.equals(_scope.householdId),
          ))
          .write(
            PantryItemsCompanion(
              quantity: const Value(0),
              confirmedAt: Value(_clock().toUtc()),
            ),
          );
      await _writer.upsert(_pantryItem, id);
    } else {
      await (_db.delete(_db.pantryItems)..where(
            (t) => t.id.equals(id) & t.householdId.equals(_scope.householdId),
          ))
          .go();
      await _writer.delete(_pantryItem, id);
    }
    await _shopping.reconcileInventory();
  });

  Future<PantryItemRow> _existing(String id) async {
    final row =
        await (_db.select(_db.pantryItems)..where(
              (t) => t.id.equals(id) & t.householdId.equals(_scope.householdId),
            ))
            .getSingleOrNull();
    if (row == null) throw const PantryItemMissing();
    return row;
  }

  static String? _unit(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  static void _validate(String name, double? quantity) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name');
    if (quantity != null && (!quantity.isFinite || quantity <= 0)) {
      throw ArgumentError.value(quantity, 'quantity');
    }
  }

  /// Prima kupljene stavke u ostavu kao potvrđenu zalihu. Prijem je ista
  /// zaliha kao kupovina (ne nova), pa se ne računa dvaput; ponovljen prijem
  /// ne pravi drugi zapis. Vraća broj novih prijema.
  Future<int> receivePurchases(Iterable<String> itemIds) =>
      _db.transaction(() async {
        var received = 0;
        final now = _clock().toUtc();
        for (final itemId in itemIds.toSet()) {
          final item =
              await (_db.select(_db.shoppingItems)..where(
                    (t) =>
                        t.id.equals(itemId) &
                        t.householdId.equals(_scope.householdId),
                  ))
                  .getSingleOrNull();
          if (item == null || !item.isBought) continue;
          final existing =
              await (_db.select(_db.pantryItems)
                    ..where((t) => t.sourceShoppingItemId.equals(itemId)))
                  .getSingleOrNull();
          if (existing != null) continue;
          final id = newId();
          await _db
              .into(_db.pantryItems)
              .insert(
                PantryItemsCompanion.insert(
                  id: id,
                  name: item.name,
                  quantity: Value(item.quantity),
                  unit: Value(item.unit),
                  category: item.category,
                  addedAt: now,
                  confirmedAt: Value(now),
                  sourceShoppingItemId: Value(itemId),
                  householdId: Value(_scope.householdId),
                ),
              );
          await _writer.upsert(_pantryItem, id);
          received++;
        }
        if (received > 0) await _shopping.reconcileInventory();
        return received;
      });

  /// Kupljene stavke koje su već primljene u ostavu, uživo.
  Stream<Set<String>> watchReceivedItemIds() =>
      (_db.select(_db.pantryItems)..where(
            (t) =>
                t.householdId.equals(_scope.householdId) &
                t.sourceShoppingItemId.isNotNull(),
          ))
          .watch()
          .map((rows) => {for (final r in rows) r.sourceShoppingItemId!});

  /// Ista fizička zaliha i njene postojeće rezervacije, bez upisa/outbox-a.
  /// Join prati obe tabele pa promena rezervacije osvežava predloge.
  Stream<List<PantryStock>> watchSuggestionStock() {
    final p = _db.pantryItems;
    final a = _db.supplyAllocations;
    final query = _db.select(p).join([
      leftOuterJoin(
        a,
        a.householdId.equals(_scope.householdId) &
            a.supplyId.equalsExp(coalesce([p.sourceShoppingItemId, p.id])),
      ),
    ])..where(p.householdId.equals(_scope.householdId));
    return query.watch().map((rows) {
      final stocks = <String, PantryStock>{};
      for (final result in rows) {
        final row = result.readTable(p);
        final reserved = result.readTableOrNull(a);
        final previous = stocks[row.id];
        stocks[row.id] = PantryStock(
          id: row.id,
          name: row.name,
          quantity: row.quantity,
          unit: row.unit,
          confirmedAt: row.confirmedAt,
          expiresAt: row.expiresAt,
          sourceShoppingItemId: row.sourceShoppingItemId,
          reservedMicros:
              (previous?.reservedMicros ?? 0) + (reserved?.micros ?? 0),
          reservedWhole:
              (previous?.reservedWhole ?? false) ||
              (reserved?.coversWholeUnknown ?? false),
        );
      }
      return stocks.values.toList();
    });
  }
}
