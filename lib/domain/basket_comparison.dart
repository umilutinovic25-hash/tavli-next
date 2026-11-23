/// Canonical unit used by an explicitly reviewed store-product mapping.
enum BasketUnit { gram, milliliter, piece }

/// A known shopping need. Unknown quantities or unresolved catalog identities
/// are represented by omitting the line from the input and remain uncovered.
class BasketLine {
  const BasketLine({
    required this.id,
    required this.name,
    this.foodId,
    this.quantityMicros,
    required this.unit,
  });

  final String id;
  final String name;
  final String? foodId;
  final int? quantityMicros;
  final BasketUnit? unit;
}

/// One current, source-backed price for a confirmed retail package.
class BasketOffer {
  const BasketOffer({
    required this.retailer,
    required this.format,
    required this.foodId,
    required this.barcode,
    required this.packageQuantityMicros,
    required this.unit,
    required this.priceInParas,
    required this.priceDate,
    required this.source,
    required this.retrievedAt,
  });

  final String retailer;
  final String format;
  final String foodId;
  final String barcode;
  final int packageQuantityMicros;
  final BasketUnit unit;
  final int priceInParas;
  final DateTime priceDate;
  final Uri source;
  final DateTime retrievedAt;

  String get storeKey => '$retailer/$format';
}

class BasketCoveredLine {
  const BasketCoveredLine({
    required this.name,
    required this.packageCount,
    required this.packageQuantityMicros,
    required this.unit,
    required this.lineIds,
  });

  final String name;
  final int packageCount;
  final int packageQuantityMicros;
  final BasketUnit unit;
  final List<String> lineIds;
}

class StoreBasketEstimate {
  const StoreBasketEstimate({
    required this.retailer,
    required this.format,
    required this.subtotalInParas,
    required this.covered,
    required this.uncovered,
    required this.priceDate,
    required this.retrievedAt,
    required this.source,
  });

  final String retailer;
  final String format;
  final int subtotalInParas;
  final List<BasketCoveredLine> covered;
  final List<BasketLine> uncovered;
  final DateTime priceDate;
  final DateTime retrievedAt;
  final Uri source;

  bool get complete => uncovered.isEmpty;
  int get coveredCount =>
      covered.fold(0, (count, line) => count + line.lineIds.length);
  int get itemCount => coveredCount + uncovered.length;
}

/// Compares needs only against reviewed mappings and current, consistent
/// offers. Unmapped, contradictory or incompatible rows never become prices.
List<StoreBasketEstimate> compareBasket(
  List<BasketLine> lines,
  List<BasketOffer> offers,
) {
  final validOffers = offers
      .where(
        (offer) =>
            offer.foodId.isNotEmpty &&
            offer.barcode.isNotEmpty &&
            offer.packageQuantityMicros > 0 &&
            offer.priceInParas >= 0 &&
            offer.priceDate.isUtc &&
            offer.retrievedAt.isUtc,
      )
      .toList();
  final scopes = <String, List<BasketOffer>>{};
  for (final offer in validOffers) {
    scopes.putIfAbsent(offer.storeKey, () => []).add(offer);
  }

  return [for (final scope in scopes.values) _estimate(lines, scope)]
    ..sort((a, b) {
      if (a.complete != b.complete) return a.complete ? -1 : 1;
      final subtotal = a.subtotalInParas.compareTo(b.subtotalInParas);
      if (subtotal != 0) return subtotal;
      return a.storeKey.compareTo(b.storeKey);
    });
}

StoreBasketEstimate _estimate(
  List<BasketLine> lines,
  List<BasketOffer> offers,
) {
  final first = offers.first;
  final byFood = <(String, BasketUnit), List<BasketLine>>{};
  final uncovered = <BasketLine>[
    for (final line in lines)
      if (line.foodId == null ||
          line.foodId!.isEmpty ||
          line.quantityMicros == null ||
          line.quantityMicros! <= 0 ||
          line.unit == null)
        line,
  ];
  for (final line in lines) {
    if (line.foodId == null ||
        line.quantityMicros == null ||
        line.quantityMicros! <= 0 ||
        line.unit == null) {
      continue;
    }
    byFood.putIfAbsent((line.foodId!, line.unit!), () => []).add(line);
  }

  final covered = <BasketCoveredLine>[];
  var subtotal = 0;
  for (final entry in byFood.entries) {
    final needs = entry.value;
    final quantity = needs.fold<int>(
      0,
      (sum, line) => sum + line.quantityMicros!,
    );
    final candidates = offers
        .where(
          (offer) => offer.foodId == entry.key.$1 && offer.unit == entry.key.$2,
        )
        .toList();
    final chosen = _cheapestPackageOption(candidates, quantity);
    if (chosen == null) {
      uncovered.addAll(needs);
      continue;
    }
    final packageCount =
        (quantity + chosen.packageQuantityMicros - 1) ~/
        chosen.packageQuantityMicros;
    subtotal += packageCount * chosen.priceInParas;
    covered.add(
      BasketCoveredLine(
        name: needs.first.name,
        packageCount: packageCount,
        packageQuantityMicros: chosen.packageQuantityMicros,
        unit: chosen.unit,
        lineIds: [for (final line in needs) line.id],
      ),
    );
  }
  covered.sort((a, b) => a.name.compareTo(b.name));
  uncovered.sort((a, b) => a.name.compareTo(b.name));
  return StoreBasketEstimate(
    retailer: first.retailer,
    format: first.format,
    subtotalInParas: subtotal,
    covered: covered,
    uncovered: uncovered,
    priceDate: offers
        .map((o) => o.priceDate)
        .reduce((a, b) => a.isBefore(b) ? a : b),
    retrievedAt: offers
        .map((o) => o.retrievedAt)
        .reduce((a, b) => a.isBefore(b) ? a : b),
    source: first.source,
  );
}

BasketOffer? _cheapestPackageOption(
  List<BasketOffer> offers,
  int quantityMicros,
) {
  if (offers.isEmpty || quantityMicros <= 0) return null;
  // If one barcode has conflicting rows for the same date, it is not a
  // trustworthy price. A different reviewed package may still cover it.
  final clean = <BasketOffer>[];
  final byBarcode = <String, List<BasketOffer>>{};
  for (final offer in offers) {
    byBarcode.putIfAbsent(offer.barcode, () => []).add(offer);
  }
  for (final barcodeRows in byBarcode.values) {
    final latest = barcodeRows
        .map((r) => r.priceDate)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final rows = barcodeRows.where((r) => r.priceDate == latest).toList();
    final first = rows.first;
    final conflict = rows.any(
      (row) =>
          row.packageQuantityMicros != first.packageQuantityMicros ||
          row.priceInParas != first.priceInParas ||
          row.unit != first.unit,
    );
    if (!conflict) clean.add(first);
  }
  if (clean.isEmpty) return null;
  clean.sort((a, b) {
    final aCount =
        (quantityMicros + a.packageQuantityMicros - 1) ~/
        a.packageQuantityMicros;
    final bCount =
        (quantityMicros + b.packageQuantityMicros - 1) ~/
        b.packageQuantityMicros;
    final aCost = aCount * a.priceInParas;
    final bCost = bCount * b.priceInParas;
    if (aCost != bCost) return aCost.compareTo(bCost);
    final freshness = b.priceDate.compareTo(a.priceDate);
    return freshness != 0 ? freshness : a.barcode.compareTo(b.barcode);
  });
  return clean.first;
}

extension on StoreBasketEstimate {
  String get storeKey => '$retailer/$format';
}
