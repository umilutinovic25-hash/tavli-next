import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/basket_price_catalog.dart';
import '../../data/database.dart';
import '../../domain/basket_comparison.dart';
import '../../domain/shopping_demand.dart';

class BasketPriceScreen extends StatefulWidget {
  const BasketPriceScreen({
    super.key,
    required this.items,
    this.loadCatalog,
    this.saveSelection,
  });
  final List<ShoppingItemRow> items;
  final Future<PriceCatalog> Function()? loadCatalog;
  final Future<bool> Function(String, String?)? saveSelection;
  @override
  State<BasketPriceScreen> createState() => _BasketPriceScreenState();
}

class _BasketPriceScreenState extends State<BasketPriceScreen> {
  late Future<PriceCatalog> catalog;
  final barcodes = <String, String>{};
  final names = <String, String>{};
  Future<void> writes = Future.value();
  final packs = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final item in widget.items) {
      try {
        final data = jsonDecode(item.priceSelectionJson ?? 'null');
        if (data is Map<String, dynamic> &&
            data['barcode'] is String &&
            data['name'] is String &&
            data['unit'] ==
                normalizeUnit(item.unit, dictionaryVersion: 1).base &&
            data['package'] is String) {
          barcodes[item.id] = data['barcode'] as String;
          names[item.id] = data['name'] as String;
          packs[item.id] = TextEditingController(
            text: data['package'] as String,
          );
        }
      } on FormatException {
        /* neispravan stari izbor se zanemaruje */
      }
    }
    catalog = (widget.loadCatalog ?? BasketPriceCatalog().fetch)();
  }

  @override
  void dispose() {
    for (final c in packs.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pick(ShoppingItemRow item, PriceCatalog data) async {
    final product = await showSearch<PriceProduct?>(
      context: context,
      query: item.name,
      delegate: _ProductSearch(data.products, item.name),
    );
    if (!mounted || product == null) return;
    setState(() {
      if (barcodes[item.id] != product.offer.barcode) {
        packs[item.id]?.clear();
      }
      barcodes[item.id] = product.offer.barcode;
      names[item.id] = product.name;
    });
    save(item);
  }

  void save(ShoppingItemRow item) {
    final callback = widget.saveSelection;
    if (callback == null) return;
    final barcode = barcodes[item.id];
    final value = barcode == null
        ? null
        : jsonEncode({
            'barcode': barcode,
            'name': names[item.id],
            'unit': normalizeUnit(item.unit, dictionaryVersion: 1).base,
            'package': packs[item.id]?.text ?? '',
          });
    writes = writes.then((_) async {
      try {
        if (!await callback(item.id, value)) {
          throw const FormatException('Stavka ne postoji');
        }
      } on Exception {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izbor nije sačuvan. Pokušaj ponovo.'),
            ),
          );
        }
      }
    });
    unawaited(writes);
  }

  BasketLine line(ShoppingItemRow item) {
    final unit = normalizeUnit(item.unit, dictionaryVersion: 1);
    final kind = switch (unit.base) {
      'g' => BasketUnit.gram,
      'ml' => BasketUnit.milliliter,
      'kom' => BasketUnit.piece,
      _ => null,
    };
    final amount = item.quantity;
    final package = double.tryParse(
      (packs[item.id]?.text ?? '').replaceAll(',', '.'),
    );
    return BasketLine(
      id: item.id,
      name: item.name,
      unit: kind,
      quantity: amount != null && amount.isFinite && amount > 0 && kind != null
          ? (amount * unit.factor * 1000000).round()
          : null,
      packageQuantity: package != null && package.isFinite && package > 0
          ? (package * 1000000).round()
          : null,
      barcode: barcodes[item.id],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Poređenje cena korpe')),
      body: FutureBuilder<PriceCatalog>(
        future: catalog,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final lines = widget.items
              .where((i) => !i.isBought)
              .map(line)
              .toList();
          final results = compareBasket(lines, [
            for (final p in data.products) p.offer,
          ]);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Izaberi proizvod za svaku stavku i unesi veličinu pakovanja u prikazanoj jedinici. Cene su informativne.',
              ),
              Text(
                data.products.isEmpty
                    ? 'Cenovnici nisu dostupni.'
                    : 'Preuzeto: ${data.fetchedAt.day}.${data.fetchedAt.month}.${data.fetchedAt.year}. · Izvori: Delhaize i Europrom',
              ),
              const SelectableText(
                'Izvori: https://data.gov.rs/sr/datasets/r/aa0a4ab4-1dc8-49e2-abef-67612a2abcbb i https://data.gov.rs/sr/datasets/r/7bcd8e5e-a89f-4dc8-9b7d-70ce27e31096',
              ),
              if (data.failedSources.isNotEmpty)
                Text(
                  'Nije moguće osvežiti: ${data.failedSources.join(', ')}. Ako postoji, prikazan je sačuvani cenovnik.',
                ),
              if (data.products.isEmpty)
                OutlinedButton(
                  onPressed: () => setState(
                    () => catalog =
                        (widget.loadCatalog ?? BasketPriceCatalog().fetch)(),
                  ),
                  child: const Text('Pokušaj ponovo'),
                ),
              for (final item in widget.items.where((i) => !i.isBought)) ...[
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.name),
                  subtitle: Text(names[item.id] ?? 'Proizvod nije izabran'),
                  trailing: const Icon(Icons.search),
                  onTap: () => pick(item, data),
                ),
                TextField(
                  controller: packs.putIfAbsent(
                    item.id,
                    TextEditingController.new,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        'Veličina pakovanja (${normalizeUnit(item.unit, dictionaryVersion: 1).base})',
                    helperText: 'Proveri količinu na proizvodu.',
                  ),
                  onChanged: (_) {
                    setState(() {});
                    save(item);
                  },
                ),
              ],
              const SizedBox(height: 24),
              Text('Rezultati', style: Theme.of(context).textTheme.titleLarge),
              for (final result in results.where((r) => r.covered.isNotEmpty))
                ListTile(
                  title: Text(result.store),
                  subtitle: Text(
                    '${result.covered.length}/${lines.length} stavki · ${result.complete ? 'cela korpa' : 'nepotpuna korpa'}\n${result.covered.map((c) => '${c.line.name}: ${c.packages == 0 ? 'u već uračunatom pakovanju' : '${c.packages} pak.'} · ${c.offer.priceDate.day}.${c.offer.priceDate.month}.${c.offer.priceDate.year}.').join('\n')}',
                  ),
                  isThreeLine: true,
                  onTap: result.uncovered.isEmpty
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Stavke bez cene'),
                            content: Text(
                              result.uncovered.map((i) => i.name).join('\n'),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Zatvori'),
                              ),
                            ],
                          ),
                        ),
                  trailing: Text(
                    '${(result.subtotalInParas / 100).toStringAsFixed(2)} din',
                  ),
                ),
              if (results.every((r) => r.covered.isEmpty))
                const Text(
                  'Izaberi proizvode i unesi potvrđene veličine pakovanja.',
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductSearch extends SearchDelegate<PriceProduct?> {
  _ProductSearch(this.products, String initial) {
    query = initial;
  }
  final List<PriceProduct> products;
  @override
  String get searchFieldLabel => 'Naziv proizvoda ili barkod';
  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];
  @override
  Widget buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );
  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);
  @override
  Widget buildSuggestions(BuildContext context) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) {
      return const Center(child: Text('Unesi najmanje dva znaka.'));
    }
    final seen = <String>{};
    final found = products
        .where(
          (p) =>
              (p.name.toLowerCase().contains(q) ||
                  p.offer.barcode.contains(q)) &&
              seen.add(p.offer.barcode),
        )
        .take(100)
        .toList();
    return ListView.builder(
      itemCount: found.length,
      itemBuilder: (context, index) {
        final p = found[index];
        return ListTile(
          title: Text(p.name),
          subtitle: Text('Barkod: ${p.offer.barcode}'),
          onTap: () => close(context, p),
        );
      },
    );
  }
}
