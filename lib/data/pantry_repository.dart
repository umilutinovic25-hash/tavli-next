import 'package:drift/drift.dart';

import '../account/auth_controller.dart';
import '../domain/ids.dart';
import '../domain/use_first.dart';
import '../sync/synced_writer.dart';
import 'database.dart';

/// Ostava domaćinstva; svaka izmena ima outbox u istoj transakciji.
class PantryRepository {
  PantryRepository(
    this._db, {
    required this._scope,
    required this._writer,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final AccountScope _scope;
  final SyncedWriter _writer;
  final DateTime Function() _clock;

  static const _pantryItem = 'pantry_item';

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
