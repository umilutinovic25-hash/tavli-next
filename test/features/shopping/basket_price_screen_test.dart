import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/data/basket_price_catalog.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/domain/basket_comparison.dart';
import 'package:tavli/features/shopping/basket_price_screen.dart';

void main() {
  testWidgets('Univerexport koristi samo izabranu i sačuvanu kategoriju', (
    tester,
  ) async {
    final source = BasketPriceCatalog.sources['Univerexport']!;
    PriceProduct product(String store, int price) => PriceProduct(
      name: 'Mleko',
      offer: BasketOffer(
        store: store,
        barcode: '123',
        priceInParas: price,
        priceDate: DateTime(2026, 11, 13),
        source: source,
      ),
    );
    final data = PriceCatalog([
      product('UNIVEREXPORT - S', 10000),
      product('UNIVEREXPORT - M', 15000),
      product('UNIVEREXPORT - L', 20000),
    ], []);
    const item = ShoppingItemRow(
      id: '1',
      listId: '1',
      name: 'Mleko',
      quantity: 1,
      unit: 'kom',
      category: 'ostalo',
      isBought: false,
      isManual: true,
      fromRecipeIdsJson: '[]',
      priceSelectionJson:
          '{"barcode":"123","name":"Mleko","unit":"kom","package":"1"}',
    );
    String? saved;
    Widget screen() => MaterialApp(
      home: BasketPriceScreen(
        items: const [item],
        loadCatalog: () async => data,
        loadPriceCategory: () async => saved,
        savePriceCategory: (value) async {
          saved = value;
        },
      ),
    );
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('UNIVEREXPORT - S'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kategorija M').last);
    await tester.pumpAndSettle();
    expect(saved, 'M');
    await tester.scrollUntilVisible(
      find.text('150.00 din'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('UNIVEREXPORT - M'), findsOneWidget);
    expect(find.text('100.00 din'), findsNothing);
    expect(find.text('200.00 din'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('Kategorija M'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('150.00 din'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('UNIVEREXPORT - M'), findsOneWidget);
  });
  testWidgets('svaki izvor prikazuje svoje vreme i dostupnost', (tester) async {
    final data = PriceCatalog([], [
      PriceSourceStatus(
        name: 'IDEA MARKETI',
        source: Uri.parse('https://example.com/idea'),
        fetchedAt: DateTime(2026, 11, 13, 12, 30),
        failed: false,
      ),
      PriceSourceStatus(
        name: 'Delhaize',
        source: Uri.parse('https://example.com/delhaize'),
        fetchedAt: DateTime(2026, 11, 10, 9, 5),
        failed: true,
      ),
      PriceSourceStatus(
        name: 'Europrom',
        source: Uri.parse('https://example.com/europrom'),
        fetchedAt: null,
        failed: true,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: BasketPriceScreen(items: const [], loadCatalog: () async => data),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('IDEA MARKETI: preuzeto 13.11.2026. u 12:30'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'prikazan sačuvani cenovnik preuzet 10.11.2026. u 09:05',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Europrom: cenovnik nije dostupan'),
      findsOneWidget,
    );
    expect(find.text('Osveži cenovnike'), findsOneWidget);
  });
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
    final data = PriceCatalog(
      [product],
      [
        PriceSourceStatus(
          name: 'Delhaize',
          source: Uri.parse('https://example.com'),
          fetchedAt: DateTime(2026, 11, 13),
          failed: false,
        ),
      ],
    );
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
    final data = PriceCatalog(
      [product],
      [
        PriceSourceStatus(
          name: 'Delhaize',
          source: Uri.parse('https://example.com'),
          fetchedAt: DateTime(2026, 11, 13),
          failed: true,
        ),
      ],
    );
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
    expect(find.textContaining('nije moguće osvežiti'), findsOneWidget);
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
