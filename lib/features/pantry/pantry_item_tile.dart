import 'package:flutter/material.dart';

import '../../data/database.dart';

enum PantryCheck {
  have('Imam'),
  empty('Nestalo'),
  unknown('Ne znam količinu');

  const PantryCheck(this.label);
  final String label;
}

enum PantryFilter {
  all('Sve'),
  soon('Uskoro ističe'),
  expired('Isteklo');

  const PantryFilter(this.label);
  final String label;
}

bool pantryExpired(PantryItemRow item, DateTime now) =>
    item.expiresAt?.isBefore(now) ?? false;

bool pantrySoon(PantryItemRow item, DateTime now) {
  final end = item.expiresAt?.toLocal();
  if (end == null || end.isBefore(now)) return false;
  final today = now.toLocal();
  return !DateTime(
    end.year,
    end.month,
    end.day,
  ).isAfter(DateTime(today.year, today.month, today.day + 7));
}

String pantryDate(DateTime value) {
  final date = value.toLocal();
  return '${date.day}.${date.month}.${date.year}.';
}

String pantryAmount(double value) =>
    value.toString().replaceFirst(RegExp(r'\.0$'), '').replaceAll('.', ',');

class PantryItemTile extends StatelessWidget {
  const PantryItemTile({
    super.key,
    required this.item,
    required this.now,
    required this.onEdit,
    this.onCheck,
  });
  final PantryItemRow item;
  final DateTime now;
  final VoidCallback onEdit;
  final ValueChanged<PantryCheck>? onCheck;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final expired = pantryExpired(item, now);
    final soon = pantrySoon(item, now);
    final details = [
      item.quantity == null
          ? 'Količina nije potvrđena'
          : '${pantryAmount(item.quantity!)}${item.unit == null ? '' : ' ${item.unit}'}',
      if (item.expiresAt case final date?)
        '${expired
            ? 'Isteklo'
            : soon
            ? 'Uskoro ističe'
            : 'Rok'}: ${pantryDate(date)}',
      if (item.sourceShoppingItemId != null) 'Iz nabavke',
      item.confirmedAt == null
          ? 'Još nije provereno'
          : 'Provereno: ${pantryDate(item.confirmedAt!)}',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minTileHeight: 80,
        title: Text(item.name, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          details.join('\n'),
          style: TextStyle(
            color: expired ? colors.error : colors.onSurfaceVariant,
          ),
        ),
        trailing: onCheck == null
            ? const Icon(Icons.edit_outlined, semanticLabel: 'Izmeni namirnicu')
            : PopupMenuButton<PantryCheck>(
                tooltip: 'Proveri namirnicu',
                icon: const Icon(Icons.fact_check_outlined),
                onSelected: onCheck,
                itemBuilder: (_) => [
                  for (final check in PantryCheck.values)
                    PopupMenuItem(value: check, child: Text(check.label)),
                ],
              ),
        onTap: onEdit,
      ),
    );
  }
}
