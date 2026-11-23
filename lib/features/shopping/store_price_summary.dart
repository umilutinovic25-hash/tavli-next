import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tavli_ui/tavli_ui.dart';

import '../../data/database.dart';
import '../../domain/basket_comparison.dart';
import '../../domain/recipe_format.dart';
import 'shopping_providers.dart';

/// Shows estimates only from reviewed package mappings and states their
/// published retailer/format scope, date and coverage.
class StorePriceSummary extends ConsumerStatefulWidget {
  const StorePriceSummary({required this.items, super.key});

  final List<ShoppingItemRow> items;

  @override
  ConsumerState<StorePriceSummary> createState() => _StorePriceSummaryState();
}

class _StorePriceSummaryState extends ConsumerState<StorePriceSummary> {
  late Future<List<StoreBasketEstimate>> _estimate;
  late String _signature;

  @override
  void initState() {
    super.initState();
    _signature = _itemsSignature(widget.items);
    _estimate = _load();
  }

  @override
  void didUpdateWidget(covariant StorePriceSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _itemsSignature(widget.items);
    if (next == _signature) return;
    _signature = next;
    _estimate = _load();
  }

  Future<List<StoreBasketEstimate>> _load() =>
      ref.read(storePriceRepositoryProvider).compare(widget.items);

  @override
  Widget build(BuildContext context) {
    ref.listen(storePriceRepositoryProvider, (_, repository) {
      if (mounted) setState(() => _estimate = repository.compare(widget.items));
    });
    if (widget.items.every((item) => item.isBought)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: TavliSpacing.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: TavliSpacing.small,
        children: [
          const TavliSectionHeader('Cena korpe'),
          FutureBuilder(
            future: _estimate,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: TavliSpacing.small,
                  children: [
                    const TavliNotice(
                      message: 'Cene trenutno ne mogu da se učitaju.',
                      tone: TavliNoticeTone.error,
                    ),
                    TavliButton.secondary(
                      label: 'Pokušaj ponovo',
                      onPressed: () => setState(() => _estimate = _load()),
                    ),
                  ],
                );
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const TavliNotice(message: 'Učitavanje cenovnika…');
              }
              final estimates = snapshot.data ?? const [];
              if (estimates.isEmpty) {
                return const TavliNotice(
                  message: 'Nema potvrđenih cena za ove stavke. Nepoznate namirnice ili pakovanja ostaju bez cene.',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: TavliSpacing.small,
                children: [
                  for (final estimate in estimates)
                    _StoreEstimateTile(estimate: estimate),
                  Text(
                    'Cene iz zbirnih cenovnika mogu se razlikovati od cene u konkretnoj prodavnici. Prikaz je procena, ne cena na kasi.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StoreEstimateTile extends StatelessWidget {
  const _StoreEstimateTile({required this.estimate});

  final StoreBasketEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = estimate.complete ? 'Procenjena cena' : 'Delimičan zbir';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(TavliRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(TavliSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: TavliSpacing.small,
          children: [
            Text(
              '${estimate.retailer} · ${estimate.format}',
              style: theme.textTheme.titleSmall,
            ),
            Text(
              '$label: ${_money(estimate.subtotalInParas)}',
              style: theme.textTheme.bodyLarge,
            ),
            Text(
              '${estimate.coveredCount} od ${estimate.itemCount} stavki · cenovnik ${_date(estimate.priceDate)} · preuzeto ${_date(estimate.retrievedAt)}',
              style: theme.textTheme.bodySmall,
            ),
            if (estimate.uncovered.isNotEmpty)
              Text(
                'Nedostaje cena: ${estimate.uncovered.map((line) => line.name).join(', ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            Text(
              'Izvor: data.gov.rs (${estimate.source.host})',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _money(int paras) => '${formatQuantity(paras / 100)} RSD';

String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _itemsSignature(List<ShoppingItemRow> items) => jsonEncode([
  for (final item in items)
    [item.id, item.name, item.quantity, item.unit, item.isBought],
]);
