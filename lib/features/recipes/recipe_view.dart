import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/quantity_review.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_format.dart';
import '../../domain/step_links.dart';
import '../foods/unconfirmed_mark.dart';
import 'recipe_photo.dart';

/// Sadržaj recepta: slika, porcije, sastojci po kategorijama, koraci.
/// Koristi se u detaljima, pregledu AI recepta i predlogu izmene.
class RecipeView extends StatelessWidget {
  const RecipeView(
    this.recipe, {
    super.key,
    this.photoBytes,
    this.showTitle = false,
    this.reviewQuantities = false,
    this.onEditIngredient,
    this.ingredientsNote,
    this.markUnconfirmed = false,
  });

  final Recipe recipe;

  /// Slika koja još nije sačuvana (pregled recepta iz slike).
  final Uint8List? photoBytes;
  final bool showTitle;
  final bool reviewQuantities;
  final ValueChanged<int>? onEditIngredient;

  /// Ispod naslova „Sastojci“ (npr. oznake alergena u detalju recepta).
  final Widget? ingredientsNote;

  /// Oznaka „Nepotvrđeno“ uz sastojak bez namirnice (detalj recepta; AI
  /// pregledi je nemaju jer se sastojci prepoznaju tek pri čuvanju).
  final bool markUnconfirmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = recipe.imagePath;
    final bytes = photoBytes;
    final origin = recipe.answeredBy != null
        ? 'Napravio: ${recipe.answeredBy}'
        : recipe.source == RecipeSource.manual
        ? 'Ručno unet'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
              semanticLabel: 'Slika recepta',
            ),
          )
        else if (path != null)
          RecipePhoto(path, height: 220),
        if (bytes != null || path != null) const SizedBox(height: 16),
        if (showTitle) ...[
          Text(recipe.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: const Icon(Icons.people_outline, size: 18),
              label: Text(servingsLabel(recipe.servings)),
            ),
            if (recipe.prepMinutes != null)
              Chip(
                avatar: const Icon(Icons.timer_outlined, size: 18),
                label: Text('${recipe.prepMinutes} min'),
              ),
            if (recipe.activeMinutes case final m?)
              Chip(
                avatar: const Icon(Icons.back_hand_outlined, size: 18),
                label: Text('Aktivno $m min'),
              ),
            if (recipe.totalMinutes case final m?)
              Chip(
                avatar: const Icon(Icons.hourglass_bottom, size: 18),
                label: Text('Ukupno $m min'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Sastojci', style: theme.textTheme.titleMedium),
        ?ingredientsNote,
        for (final (category, items) in groupByCategory(
          recipe.ingredients,
        )) ...[
          const SizedBox(height: 12),
          Text(
            category,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          for (final (index, i) in recipe.ingredients.indexed)
            if (items.contains(i))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: onEditIngredient == null
                    ? markUnconfirmed && i.foodId == null
                          ? Row(
                              children: [
                                Flexible(child: _ingredient(context, i)),
                                const SizedBox(width: 6),
                                const UnconfirmedMark(),
                              ],
                            )
                          : _ingredient(context, i)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _ingredient(context, i)),
                          IconButton(
                            key: ValueKey('review-ingredient-$index'),
                            tooltip: 'Izmeni sastojak: ${i.name}',
                            onPressed: () => onEditIngredient!(index),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
              ),
        ],
        for (final c in useConflicts(recipe.ingredients, recipe.stepUses))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '„${c.ingredient.name}“: koraci koriste '
              '${formatQuantity(c.usedQuantity)}'
              '${c.ingredient.unit == null ? '' : ' ${c.ingredient.unit}'}, '
              'a recept ima ${formatQuantity(c.ingredient.quantity!)}'
              '${c.ingredient.unit == null ? '' : ' ${c.ingredient.unit}'}.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text('Priprema', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (recipe.steps.isEmpty)
          Text(
            'Koraci pripreme nisu uneti.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final (n, step) in recipe.steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${n + 1}.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(step),
                        for (final use in recipe.usesFor(n))
                          StepUseLine(use, recipe.ingredients),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        if (recipe.sourceUrl case final sourceUrl?) ...[
          const SizedBox(height: 16),
          SelectableText('Izvor: $sourceUrl', style: theme.textTheme.bodySmall),
        ],
        if (origin != null) ...[
          const SizedBox(height: 16),
          Text(origin, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }

  Widget _ingredient(BuildContext context, Ingredient ingredient) {
    final line = Text(
      '• ${ingredientLine(ingredient, preservePrecision: reviewQuantities)}',
    );
    final issue = reviewQuantities ? quantityReviewIssue(ingredient) : null;
    if (issue == null) return line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                issue.label,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Sastojak uz korak: "300 g brašno"; bez količine samo naziv (raspodela
/// se ne izmišlja); sastojak koji više nije u receptu se jasno označava.
class StepUseLine extends StatelessWidget {
  const StepUseLine(this.use, this.ingredients, {super.key});

  final StepUse use;
  final List<Ingredient> ingredients;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Ingredient? ingredient;
    for (final i in ingredients) {
      if (i.id == use.ingredientId) ingredient = i;
    }
    final text = ingredient == null
        ? 'Sastojak više nije u receptu'
        : [
            if (use.quantity case final q?) formatQuantity(q),
            if (use.quantity != null) ?(use.unit ?? ingredient.unit),
            ingredient.name,
          ].join(' ');
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '↳ $text',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: ingredient == null
              ? theme.colorScheme.error
              : theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Sadržaj ekrana ograničen na čitljivu širinu i sa skrolovanjem.
class ReadableScroll extends StatelessWidget {
  const ReadableScroll({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
