import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/recipe.dart';
import '../../domain/recipe_format.dart';
import 'recipe_photo.dart';

/// Sadržaj recepta: slika, porcije, sastojci po kategorijama, koraci.
/// Koristi se u detaljima, pregledu AI recepta i predlogu izmene.
class RecipeView extends StatelessWidget {
  const RecipeView(
    this.recipe, {
    super.key,
    this.photoBytes,
    this.showTitle = false,
  });

  final Recipe recipe;

  /// Slika koja još nije sačuvana (pregled recepta iz slike).
  final Uint8List? photoBytes;
  final bool showTitle;

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
          ],
        ),
        const SizedBox(height: 16),
        Text('Sastojci', style: theme.textTheme.titleMedium),
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
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• ${ingredientLine(i)}'),
            ),
        ],
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
                  Expanded(child: Text(step)),
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
