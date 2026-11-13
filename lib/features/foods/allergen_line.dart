import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/allergy.dart';
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
    final household =
        ref.watch(householdAllergiesProvider).value ?? HouseholdAllergies.none;
    final (:codes, :complete) = recipeAllergens(recipe, catalog);
    final member = checkAllergens(recipe.ingredients, catalog, household);
    // Uz alergije članova „Nepotvrđeno, proveri alergene“ zamenjuje opštu
    // napomenu o nepotpunim podacima.
    final incompleteNote = !complete && household.isEmpty;
    if (codes.isEmpty &&
        !incompleteNote &&
        member.hits.isEmpty &&
        !member.unconfirmed) {
      return const SizedBox.shrink();
    }
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
          MemberAllergenWarning(check: member),
          if (incompleteNote)
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

/// Upozorenje prema alergijama članova domaćinstva (039): pogodak je
/// istaknut, a nepotvrđen sastojak traži proveru. Bez alergija u
/// domaćinstvu ne prikazuje ništa.
class MemberAllergenWarning extends StatelessWidget {
  const MemberAllergenWarning({super.key, required this.check});

  final AllergyCheck check;

  @override
  Widget build(BuildContext context) {
    if (check.hits.isEmpty && !check.unconfirmed) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final hit = check.hits.isNotEmpty;
    final color = hit
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              hit
                  ? 'Sadrži alergen člana: ${check.allergens.join(', ')}'
                  : 'Nepotvrđeno, proveri alergene',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: hit ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [MemberAllergenWarning] za sastojke koji još nisu sačuvani (pregled AI
/// recepta, forma uvoza): sam čita katalog i alergije domaćinstva.
class IngredientsAllergenWarning extends ConsumerWidget {
  const IngredientsAllergenWarning(this.ingredients, {super.key});

  final List<Ingredient> ingredients;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(foodCatalogProvider).value;
    final household = ref.watch(householdAllergiesProvider).value;
    if (catalog == null || household == null) return const SizedBox.shrink();
    return MemberAllergenWarning(
      check: checkAllergens(ingredients, catalog, household),
    );
  }
}
