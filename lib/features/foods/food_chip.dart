import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';

/// Oznaka namirnice reda (sastojak, zaliha, stavka): naziv iz kataloga ili
/// „Nepotvrđeno“. Dodir otvara izbor namirnice.
class FoodChip extends ConsumerWidget {
  const FoodChip({required this.foodId, required this.onPressed, super.key});

  final String? foodId;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = foodId;
    final food = id == null
        ? null
        : ref.watch(foodCatalogProvider).value?.byId(id);
    final confirmed = id != null;
    return ActionChip(
      avatar: Icon(
        confirmed ? Icons.check_circle_outline : Icons.help_outline,
        size: 18,
      ),
      // Namirnica koje još nema na uređaju (sync) je i dalje potvrđena.
      label: Text(confirmed ? (food?.name ?? '…') : 'Nepotvrđeno'),
      onPressed: onPressed,
    );
  }
}
