import 'package:supabase/supabase.dart';

import '../account/auth_controller.dart';
import '../domain/basket_comparison.dart';
import '../domain/food_matcher.dart';
import '../domain/shopping_demand.dart';
import '../domain/shopping_sync.dart';
import '../sync/sync_engine.dart';
import 'database.dart';

/// Reads reviewed public price mappings; the household basket stays local.
class StorePriceRepository {
  const StorePriceRepository({
    required this.client,
    required this.syncEngine,
    required this.scope,
  });

  final SupabaseClient? client;
  final SyncEngine? syncEngine;
  final AccountScope scope;

  Future<List<StoreBasketEstimate>> compare(List<ShoppingItemRow> items) async {
    final open = items.where((item) => !item.isBought).toList();
    if (open.isEmpty) return const [];
    final supabase = client;
    final engine = syncEngine;
    if (supabase == null || engine == null || scope.householdId.isEmpty) {
      return const [];
    }

    final matcher = await engine.catalogMatcher();
    final byName = <String, FoodMatchResult>{};
    final lines = <BasketLine>[];
    for (final item in open) {
      final nameKey = ingredientKey(item.name);
      final normalized = normalizeUnit(item.unit);
      final unit = switch (normalized.group) {
        'mass' => BasketUnit.gram,
        'volume' => BasketUnit.milliliter,
        'count:kom' => BasketUnit.piece,
        _ => null,
      };
      final resolved =
          byName[nameKey] ??
          await matcher.findByName(
            originalText: item.name,
            scope: FoodLookupScope(householdId: scope.householdId),
          );
      byName[nameKey] = resolved;
      final food = resolved is Matched ? resolved.food : null;
      final foodUnit = switch (food?.baseUnit) {
        FoodBaseUnit.gram => BasketUnit.gram,
        FoodBaseUnit.milliliter => BasketUnit.milliliter,
        FoodBaseUnit.piece => BasketUnit.piece,
        null => null,
      };
      final id = food != null && foodUnit == unit ? food.id : null;
      final quantityMicros =
          item.quantity != null &&
              item.quantity!.isFinite &&
              item.quantity! >= 0
          ? toMicros(item.quantity!) * normalized.factor
          : null;
      lines.add(
        BasketLine(
          id: item.id,
          name: item.name,
          foodId: id,
          quantityMicros: quantityMicros,
          unit: unit,
        ),
      );
    }

    final foodIds = {for (final line in lines) ?line.foodId}.toList();
    if (foodIds.isEmpty) return const [];
    final response = await supabase.rpc<List<Map<String, dynamic>>>(
      'store_price_offers_for_food_ids',
      params: {'p_food_ids': foodIds},
    );
    final offers = [for (final row in response) ?_offer(row)];
    return compareBasket(lines, offers);
  }

  BasketOffer? _offer(Map<String, dynamic> row) {
    final unit = switch (row['package_unit']) {
      'gram' => BasketUnit.gram,
      'milliliter' => BasketUnit.milliliter,
      'piece' => BasketUnit.piece,
      _ => null,
    };
    final priceDate = DateTime.tryParse(row['price_date'] as String? ?? '');
    final retrievedAt = DateTime.tryParse(row['retrieved_at'] as String? ?? '');
    final source = Uri.tryParse(row['source_url'] as String? ?? '');
    final packageMicros = row['package_quantity_micros'];
    final price = row['price_in_paras'];
    if (unit == null ||
        priceDate == null ||
        retrievedAt == null ||
        source == null ||
        source.scheme != 'https' ||
        packageMicros is! int ||
        price is! int ||
        row['source_id'] is! String ||
        row['retailer'] is! String ||
        row['retailer_format'] is! String ||
        row['barcode'] is! String ||
        row['food_id'] is! String) {
      return null;
    }
    return BasketOffer(
      retailer: row['retailer'] as String,
      format: row['retailer_format'] as String,
      foodId: row['food_id'] as String,
      barcode: row['barcode'] as String,
      packageQuantityMicros: packageMicros,
      unit: unit,
      priceInParas: price,
      priceDate: priceDate.toUtc(),
      source: source,
      retrievedAt: retrievedAt.toUtc(),
    );
  }
}
