import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/tavli_colors.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_format.dart';
import 'recipe_photo.dart';

/// Ista biblioteka i rute kao u listi; ovo je samo drugi način prikaza.
class RecipeGrid extends StatelessWidget {
  const RecipeGrid({super.key, required this.recipes, this.selectedId});

  final List<Recipe> recipes;
  final String? selectedId;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final columns = scaler.scale(16) > 20
          ? 1
          : ((constraints.maxWidth - 32) / 164).floor().clamp(1, 3);
      return GridView.builder(
        key: const PageStorageKey('recipe-grid'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 140 + scaler.scale(16) * 7,
        ),
        itemCount: recipes.length,
        itemBuilder: (context, index) => _RecipeGridCard(
          recipe: recipes[index],
          index: index,
          selected: recipes[index].id == selectedId,
        ),
      );
    },
  );
}

class _RecipeGridCard extends StatelessWidget {
  const _RecipeGridCard({
    required this.recipe,
    required this.index,
    required this.selected,
  });

  final Recipe recipe;
  final int index;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Card(
        margin: EdgeInsets.zero,
        color: selected ? colors.primaryContainer : null,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go('/recipes/${recipe.id}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 96,
                    child: recipe.imagePath != null
                        ? RecipePhoto(recipe.imagePath!, height: 96)
                        : ColoredBox(
                            color: TavliColors.of(context).tint(index),
                            child: Icon(
                              Icons.soup_kitchen_outlined,
                              size: 48,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  recipe.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      servingsLabel(recipe.servings),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (recipe.prepMinutes case final minutes?)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$minutes min',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
