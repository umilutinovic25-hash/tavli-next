import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/recipe.dart';
import '../../domain/recipe_format.dart';
import '../../domain/recipe_nutrition.dart';
import '../../providers.dart';

/// Vrednost po porciji ispod sastojaka: kalorije i makroi sa znakom ~
/// (procena) i pokrivenošću („računato za 7 od 8 sastojaka“). Bez ijednog
/// pokrivenog sastojka ne prikazuje ništa, da ne bude pogrešnog broja.
class NutritionLine extends ConsumerWidget {
  const NutritionLine(this.recipe, {super.key});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(foodCatalogProvider).value;
    if (catalog == null) return const SizedBox.shrink();
    final result = recipeNutritionPerServing(
      recipe.ingredients,
      servings: recipe.servings,
      catalog: catalog,
    );
    if (result == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final v = result.perServing;
    String grams(double g) => formatQuantity((g * 10).round() / 10);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Po porciji ~${v.kcal.round()} kcal · proteini ${grams(v.protein)} g'
            ' · masti ${grams(v.fat)} g · ugljeni hidrati ${grams(v.carbs)} g',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            'Računato za ${result.counted} od ${result.total} '
            '${_ingredientsWord(result.total)}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// „od 1/2/3/4/21 sastojka“, ali „od 5/12/20 sastojaka“.
String _ingredientsWord(int n) {
  final lastTwo = n % 100;
  final last = n % 10;
  if (lastTwo >= 11 && lastTwo <= 14) return 'sastojaka';
  return last >= 1 && last <= 4 ? 'sastojka' : 'sastojaka';
}
