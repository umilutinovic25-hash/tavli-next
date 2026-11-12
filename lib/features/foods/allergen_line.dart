import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/food.dart';
import '../../domain/recipe.dart';
import '../../providers.dart';

/// Oznake alergena recepta iz potvrđenih namirnica (EU 14, redosled iz
/// Uredbe). Nikad ne tvrdi „bez alergena“: bez oznaka i sa potpunim
/// podacima ne prikazuje ništa, a uz nepotvrđen sastojak upozorava.
class AllergenLine extends ConsumerWidget {
  const AllergenLine(this.recipe, {super.key});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(foodCatalogProvider).value;
    if (catalog == null) return const SizedBox.shrink();
    final (:codes, :complete) = recipeAllergens(recipe, catalog);
    if (codes.isEmpty && complete) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final names = [
      for (final MapEntry(:key, :value) in euAllergens.entries)
        if (codes.contains(key)) value,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (names.isNotEmpty)
            Text(
              'Sadrži: ${names.join(', ')}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          if (!complete)
            Text(
              'Podaci o alergenima nisu potpuni.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
