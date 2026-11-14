import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/basket_comparison.dart';

void main() {
  final source = Uri.parse('https://example.com/prices');
  final date = DateTime.utc(2026, 11, 13);
  BasketOffer offer(String store, String barcode, int price) => BasketOffer(
    store: store,
    barcode: barcode,
    priceInParas: price,
    priceDate: date,
    source: source,
  );

  test('cela pakovanja i nepotpuna korpa', () {
    const lines = [
      BasketLine(
        id: '1',
        name: 'mleko',
        quantity: 1500,
        unit: BasketUnit.milliliter,
        barcode: '1',
        packageQuantity: 1000,
      ),
      BasketLine(
        id: '2',
        name: 'jaja',
        quantity: 6,
        unit: BasketUnit.piece,
        barcode: '2',
        packageQuantity: 10,
      ),
    ];
    final result = compareBasket(lines, [
      offer('A', '1', 12000),
      offer('A', '2', 25000),
      offer('B', '1', 10000),
    ]);
    final a = result.firstWhere((r) => r.store == 'A');
    final b = result.firstWhere((r) => r.store == 'B');
    expect(a.subtotalInParas, 49000); // 2 × 120 + 1 × 250 = 490 din
    expect(a.complete, isTrue);
    expect(b.subtotalInParas, 20000);
    expect(b.uncovered.single.name, 'jaja');
    expect(b.complete, isFalse);
  });

  test('nepoznato pakovanje i protivrečne cene ostaju nepokriveni', () {
    const lines = [
      BasketLine(
        id: '1',
        name: 'ulje',
        quantity: 1000,
        unit: BasketUnit.milliliter,
        barcode: '1',
        packageQuantity: 1000,
      ),
      BasketLine(
        id: '2',
        name: 'brašno',
        quantity: 1000,
        unit: BasketUnit.gram,
        barcode: '2',
      ),
    ];
    final result = compareBasket(lines, [
      offer('A', '1', 10000),
      offer('A', '1', 11000),
      offer('A', '2', 9000),
    ]).single;
    expect(result.covered, isEmpty);
    expect(result.uncovered.length, 2);
    expect(result.complete, isFalse);
  });
  test('ista kupovina deli pakovanje kroz više stavki', () {
    const lines = [
      BasketLine(
        id: '1',
        name: 'mleko za ponedeljak',
        quantity: 400,
        unit: BasketUnit.milliliter,
        barcode: '1',
        packageQuantity: 1000,
      ),
      BasketLine(
        id: '2',
        name: 'mleko za utorak',
        quantity: 400,
        unit: BasketUnit.milliliter,
        barcode: '1',
        packageQuantity: 1000,
      ),
    ];
    final result = compareBasket(lines, [offer('A', '1', 12000)]).single;
    expect(result.complete, isTrue);
    expect(result.subtotalInParas, 12000);
  });

  const milk = BasketLine(
    id: '1',
    name: 'mleko',
    quantity: 1000,
    unit: BasketUnit.milliliter,
    barcode: '1',
    packageQuantity: 1000,
  );

  test('svaka protivrečna najnovija ponuda čini cenu nepokrivenom', () {
    for (final prices in [
      [10000, 10000, 12000],
      [10000, 12000, 10000],
      [12000, 10000, 10000],
    ]) {
      final result = compareBasket(
        [milk],
        [for (final p in prices) offer('A', '1', p)],
      ).single;
      expect(result.complete, isFalse, reason: '$prices');
      expect(result.covered, isEmpty);
      expect(result.uncovered, [milk]);
    }
  });

  test('saglasni najnoviji duplikati imaju prednost nad starijom cenom', () {
    final result = compareBasket(
      [milk],
      [
        offer('A', '1', 12000),
        offer('A', '1', 12000),
        BasketOffer(
          store: 'A',
          barcode: '1',
          priceInParas: 10000,
          priceDate: date.subtract(const Duration(days: 1)),
          source: source,
        ),
      ],
    ).single;
    expect(result.complete, isTrue);
    expect(result.subtotalInParas, 12000);
  });
}
