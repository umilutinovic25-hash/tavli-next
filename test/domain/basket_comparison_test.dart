import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/basket_comparison.dart';

void main() {
  final source = Uri.parse('https://data.gov.rs/prices.csv');
  final date = DateTime.utc(2026, 11, 21);
  final retrievedAt = DateTime.utc(2026, 11, 23);

  BasketOffer offer(
    String format,
    String barcode,
    String foodId,
    int packageMicros,
    int priceInParas, {
    BasketUnit unit = BasketUnit.gram,
    DateTime? priceDate,
  }) => BasketOffer(
    retailer: 'Delhaize',
    format: format,
    foodId: foodId,
    barcode: barcode,
    packageQuantityMicros: packageMicros,
    unit: unit,
    priceInParas: priceInParas,
    priceDate: priceDate ?? date,
    source: source,
    retrievedAt: retrievedAt,
  );

  test('prikazuje delimičan zbir, 3 od 4 i nepokriven pirinač', () {
    const lines = [
      BasketLine(
        id: 'milk',
        name: 'mleko',
        foodId: 'milk',
        quantityMicros: 1500 * 1000000,
        unit: BasketUnit.milliliter,
      ),
      BasketLine(
        id: 'eggs',
        name: 'jaja',
        foodId: 'eggs',
        quantityMicros: 6 * 1000000,
        unit: BasketUnit.piece,
      ),
      BasketLine(
        id: 'flour',
        name: 'brašno',
        foodId: 'flour',
        quantityMicros: 500 * 1000000,
        unit: BasketUnit.gram,
      ),
      BasketLine(
        id: 'rice',
        name: 'pirinač',
        foodId: 'rice',
        quantityMicros: 1000 * 1000000,
        unit: BasketUnit.gram,
      ),
    ];
    final result = compareBasket(lines, [
      offer(
        'Maxi',
        'milk-1l',
        'milk',
        1000 * 1000000,
        12000,
        unit: BasketUnit.milliliter,
      ),
      offer(
        'Maxi',
        'eggs-10',
        'eggs',
        10 * 1000000,
        25000,
        unit: BasketUnit.piece,
      ),
      offer('Maxi', 'flour-1kg', 'flour', 1000 * 1000000, 9500),
    ]).single;

    expect(result.subtotalInParas, 58500);
    expect(result.coveredCount, 3);
    expect(result.itemCount, 4);
    expect(result.uncovered.single.name, 'pirinač');
    expect(result.complete, isFalse);
  });

  test('duple potrebe dele kupljeno pakovanje', () {
    const lines = [
      BasketLine(
        id: 'monday',
        name: 'mleko za ponedeljak',
        foodId: 'milk',
        quantityMicros: 400 * 1000000,
        unit: BasketUnit.milliliter,
      ),
      BasketLine(
        id: 'tuesday',
        name: 'mleko za utorak',
        foodId: 'milk',
        quantityMicros: 400 * 1000000,
        unit: BasketUnit.milliliter,
      ),
    ];
    final result = compareBasket(lines, [
      offer(
        'Maxi',
        'milk-1l',
        'milk',
        1000 * 1000000,
        12000,
        unit: BasketUnit.milliliter,
      ),
    ]).single;

    expect(result.complete, isTrue);
    expect(result.subtotalInParas, 12000);
    expect(result.covered.single.packageCount, 1);
    expect(result.covered.single.lineIds, ['monday', 'tuesday']);
  });

  test('nepoznat identitet i količina ostaju bez cene', () {
    const lines = [
      BasketLine(
        id: 'unknown',
        name: 'nepoznata namirnica',
        unit: BasketUnit.gram,
      ),
      BasketLine(
        id: 'no-quantity',
        name: 'brašno',
        foodId: 'flour',
        unit: BasketUnit.gram,
      ),
    ];
    final result = compareBasket(lines, [
      offer('Maxi', 'flour-1kg', 'flour', 1000 * 1000000, 9500),
    ]).single;

    expect(result.subtotalInParas, 0);
    expect(result.uncovered.map((line) => line.id), ['no-quantity', 'unknown']);
    expect(result.complete, isFalse);
  });

  test('kontradiktorne cene istog barkoda i datuma se isključuju', () {
    const lines = [
      BasketLine(
        id: 'flour',
        name: 'brašno',
        foodId: 'flour',
        quantityMicros: 500 * 1000000,
        unit: BasketUnit.gram,
      ),
    ];
    final result = compareBasket(lines, [
      offer('Maxi', 'flour-1kg', 'flour', 1000 * 1000000, 9500),
      offer('Maxi', 'flour-1kg', 'flour', 1000 * 1000000, 10000),
    ]).single;

    expect(result.covered, isEmpty);
    expect(result.uncovered.single.name, 'brašno');
  });

  test('starija niža cena ne zamenjuje aktuelnu cenu istog pakovanja', () {
    const lines = [
      BasketLine(
        id: 'flour',
        name: 'brašno',
        foodId: 'flour',
        quantityMicros: 500 * 1000000,
        unit: BasketUnit.gram,
      ),
    ];
    final result = compareBasket(lines, [
      offer(
        'Maxi',
        'flour-1kg',
        'flour',
        1000 * 1000000,
        5000,
        priceDate: DateTime.utc(2026, 11),
      ),
      offer('Maxi', 'flour-1kg', 'flour', 1000 * 1000000, 9500),
    ]).single;

    expect(result.subtotalInParas, 9500);
  });

  test('izveštava zasebno format trgovca', () {
    const line = BasketLine(
      id: 'flour',
      name: 'brašno',
      foodId: 'flour',
      quantityMicros: 500 * 1000000,
      unit: BasketUnit.gram,
    );
    final results = compareBasket(
      [line],
      [
        offer('Maxi', 'flour-maxi', 'flour', 1000 * 1000000, 9500),
        offer('Maxi Online', 'flour-online', 'flour', 1000 * 1000000, 11000),
      ],
    );

    expect(results.map((result) => result.format), ['Maxi', 'Maxi Online']);
    expect(results.map((result) => result.subtotalInParas), [9500, 11000]);
  });
}
