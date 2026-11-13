import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/data/basket_price_catalog.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/domain/basket_comparison.dart';
import 'package:tavli/features/shopping/basket_price_screen.dart';

void main() {
  testWidgets('izbor proizvoda i potvrda pakovanja daju cenu korpe', (
    tester,
  ) async {
    final product = PriceProduct(
      name: 'Mleko 1 l',
      offer: BasketOffer(
        store: 'Maxi',
        barcode: '123',
        priceInParas: 12000,
        priceDate: DateTime(2026, 11, 13),
        source: Uri.parse('https://example.com'),
      ),
    );
    final data = PriceCatalog([product], [], DateTime(2026, 11, 13));
    const item = ShoppingItemRow(
      id: '1',
      listId: '1',
      name: 'Mleko',
      quantity: 1.5,
      unit: 'l',
      category: 'ostalo',
      isBought: false,
      isManual: true,
      fromRecipeIdsJson: '[]',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BasketPriceScreen(
          items: const [item],
          loadCatalog: () async => data,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proizvod nije izabran'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mleko 1 l'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1000');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('240.00 din'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('240.00 din'), findsOneWidget);
    expect(find.textContaining('1/1 stavki'), findsOneWidget);
  });
  testWidgets('sačuvan izbor se vraća kada se ekran ponovo otvori', (
    tester,
  ) async {
    final product = PriceProduct(
      name: 'Mleko 1 l',
      offer: BasketOffer(
        store: 'Maxi',
        barcode: '123',
        priceInParas: 12000,
        priceDate: DateTime(2026, 11, 13),
        source: Uri.parse('https://example.com'),
      ),
    );
    final data = PriceCatalog([product], ['Delhaize'], DateTime(2026, 11, 13));
    const item = ShoppingItemRow(
      id: '1',
      listId: '1',
      name: 'Mleko',
      quantity: 1.5,
      unit: 'l',
      category: 'ostalo',
      isBought: false,
      isManual: true,
      fromRecipeIdsJson: '[]',
      priceSelectionJson:
          '{"barcode":"123","name":"Mleko 1 l","unit":"ml","package":"1000"}',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BasketPriceScreen(
          items: const [item],
          loadCatalog: () async => data,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mleko 1 l'), findsOneWidget);
    expect(find.text('1000'), findsOneWidget);
    expect(find.textContaining('Nije moguće osvežiti'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('240.00 din'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('240.00 din'), findsOneWidget);
  });
}
