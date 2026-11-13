/// Obračun potvrđenih proizvoda za poređenje otvorene korpe.
/// Količine su u istoj osnovnoj jedinici (g, ml ili kom), a novac u parama.
library;

enum BasketUnit { gram, milliliter, piece }

class BasketLine {
  const BasketLine({
    required this.id,
    required this.name,
    this.quantity,
    this.unit,
    this.barcode,
    this.packageQuantity,
  });

  final String id;
  final String name;
  final int? quantity;
  final BasketUnit? unit;

  /// Barkod i veličina pakovanja koje je korisnik potvrdio.
  final String? barcode;
  final int? packageQuantity;
}

class BasketOffer {
  const BasketOffer({
    required this.store,
    required this.barcode,
    required this.priceInParas,
    required this.priceDate,
    required this.source,
  });

  final String store;
  final String barcode;
  final int priceInParas;
  final DateTime priceDate;
  final Uri source;
}

class ComparedLine {
  const ComparedLine({
    required this.line,
    required this.offer,
    required this.packages,
    required this.totalInParas,
  });
  final BasketLine line;
  final BasketOffer offer;
  final int packages;
  final int totalInParas;
}

class StoreComparison {
  const StoreComparison({
    required this.store,
    required this.covered,
    required this.uncovered,
  });
  final String store;
  final List<ComparedLine> covered;
  final List<BasketLine> uncovered;
  int get subtotalInParas =>
      covered.fold(0, (sum, line) => sum + line.totalInParas);
  bool get complete => uncovered.isEmpty && covered.isNotEmpty;
}

/// Cenovnik treba prethodno da razreši važeću cenu i duplikate. Kod više
/// ponuda za barkod koristi se najnovija; sporni redovi se izostavljaju.
List<StoreComparison> compareBasket(
  List<BasketLine> lines,
  List<BasketOffer> offers,
) {
  final stores = <String>{for (final offer in offers) offer.store};
  return [
    for (final store in stores)
      () {
        final covered = <ComparedLine>[];
        final uncovered = <BasketLine>[];
        final used = <String, int>{};
        for (final line in lines) {
          final quantity = line.quantity;
          final package = line.packageQuantity;
          if (quantity == null ||
              quantity <= 0 ||
              package == null ||
              package <= 0 ||
              line.unit == null ||
              line.barcode == null ||
              line.barcode!.isEmpty) {
            uncovered.add(line);
            continue;
          }
          final related = lines.where(
            (other) =>
                other.barcode == line.barcode &&
                other.quantity != null &&
                other.quantity! > 0 &&
                other.unit != null &&
                other.packageQuantity != null &&
                other.packageQuantity! > 0,
          );
          if (related.any(
            (other) =>
                other.unit != line.unit || other.packageQuantity != package,
          )) {
            uncovered.add(line);
            continue;
          }
          final matches =
              offers
                  .where(
                    (o) =>
                        o.store == store &&
                        o.barcode == line.barcode &&
                        o.priceInParas > 0,
                  )
                  .toList()
                ..sort((a, b) => b.priceDate.compareTo(a.priceDate));
          if (matches.isEmpty ||
              (matches.length > 1 &&
                  matches[0].priceDate == matches[1].priceDate &&
                  matches[0].priceInParas != matches[1].priceInParas)) {
            uncovered.add(line);
            continue;
          }
          final previous = used[line.barcode] ?? 0;
          final total = previous + quantity;
          final count =
              (total + package - 1) ~/ package -
              (previous + package - 1) ~/ package;
          used[line.barcode!] = total;
          covered.add(
            ComparedLine(
              line: line,
              offer: matches.first,
              packages: count,
              totalInParas: count * matches.first.priceInParas,
            ),
          );
        }
        return StoreComparison(
          store: store,
          covered: List.unmodifiable(covered),
          uncovered: List.unmodifiable(uncovered),
        );
      }(),
  ];
}
