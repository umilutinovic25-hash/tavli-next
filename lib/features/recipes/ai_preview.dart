import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/animations/simmering_pot.dart';
import '../../domain/quantity_review.dart';
import '../../domain/recipe.dart';
import '../../domain/shopping_source.dart';
import '../foods/allergen_line.dart';
import 'ingredient_review_sheet.dart';
import 'photo_recipe_comparison.dart';
import 'recipe_view.dart';

/// Recept koji je AI napravio, pre čuvanja.
class AiRecipePreview extends StatelessWidget {
  const AiRecipePreview({
    super.key,
    required this.recipe,
    required this.onSave,
    required this.onRetry,
    required this.onDiscard,
    this.photoBytes,
    this.saving = false,
    this.onEditIngredient,
  });

  final Recipe recipe;
  final Uint8List? photoBytes;
  final bool saving;
  final ValueChanged<int>? onEditIngredient;
  final VoidCallback onSave;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final invalidQuantity =
        photoBytes != null &&
        recipe.ingredients.any(
          (i) => quantityReviewIssue(i) == QuantityReviewIssue.invalid,
        );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: IngredientsAllergenWarning(recipe.ingredients),
        ),
        Expanded(
          child: photoBytes != null
              ? PhotoRecipeComparison(
                  recipe: recipe,
                  photo: photoBytes!,
                  onEditIngredient: saving ? null : onEditIngredient,
                )
              : ReadableScroll(children: [RecipeView(recipe, showTitle: true)]),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: saving ? null : onDiscard,
                  child: const Text('Odbaci'),
                ),
                OutlinedButton.icon(
                  onPressed: saving || invalidQuantity
                      ? null
                      : () => showIngredientReview(
                          context,
                          snapshot: RecipeSnapshot.fromRecipe(recipe),
                          originKey: 'recipe:${recipe.id}',
                        ),
                  icon: const Icon(Icons.checklist),
                  label: const Text('Proveri sastojke'),
                ),
                OutlinedButton.icon(
                  onPressed: saving ? null : onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Pokušaj ponovo'),
                ),
                FilledButton.icon(
                  onPressed: saving || invalidQuantity ? null : onSave,
                  icon: const Icon(Icons.check),
                  label: const Text('Sačuvaj'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Indikator dok AI radi (lonac koji krčka sa porukama), uz "Prekini" kad
/// lanac modela traje predugo. [pot] = false kad animaciju već daje ekran
/// (npr. skeniranje slike).
class AiBusy extends StatelessWidget {
  const AiBusy(this.text, {super.key, this.onCancel, this.pot = true});

  final String text;
  final VoidCallback? onCancel;
  final bool pot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pot) ...[
          const Center(child: SimmeringPot()),
          const SizedBox(height: 4),
        ] else
          const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (onCancel != null)
          Center(
            child: TextButton(
              onPressed: onCancel,
              child: const Text('Prekini'),
            ),
          ),
      ],
    );
  }
}

/// Greška AI-ja sa dugmićima za sledeći korak.
class AiErrorBox extends StatelessWidget {
  const AiErrorBox(this.message, {super.key, required this.actions});

  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: TextStyle(color: colors.onErrorContainer)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }
}
