import 'package:flutter/material.dart';

import '../../domain/meal_plan.dart';
import '../../domain/recipe_format.dart';
import '../../domain/time_budget.dart';
import 'time_check_note.dart';

/// Jedno mesto u planu: vrsta obroka, jelo, vreme, porcije i oznake
/// Zaključano/Skuvano (tekstom, ne samo bojom).
class MealEntryCard extends StatelessWidget {
  const MealEntryCard({
    super.key,
    required this.slot,
    required this.meal,
    this.selected = false,
    this.onTap,
    this.timeCheck,
  });

  final MealSlot slot;
  final PlannedMeal? meal;
  final bool selected;
  final VoidCallback? onTap;

  /// Provera vremena za taj dan (prikazuje se samo prekoračenje i
  /// nepoznato).
  final TimeCheck? timeCheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final meal = this.meal;
    final snapshot = meal?.snapshot;
    final details = [
      if (snapshot?.prepMinutes case final m?) '$m min',
      if (meal != null) servingsLabel(meal.servings),
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: selected ? colors.secondaryContainer : null,
      child: InkWell(
        onTap: meal == null ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slot.type.label, style: theme.textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(
                  meal == null
                      ? 'Nije planirano'
                      : (snapshot?.title ?? 'Recept nije dostupan'),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: meal == null ? colors.onSurfaceVariant : null,
                  ),
                ),
                TimeCheckNote(timeCheck),
                if (details.isNotEmpty || meal != null) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (details.isNotEmpty)
                        Text(
                          details,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      if (meal?.isLocked ?? false)
                        const _Tag(
                          icon: Icons.lock_outline,
                          text: 'Zaključano',
                        ),
                      if (meal?.isCooked ?? false)
                        const _Tag(
                          icon: Icons.check_circle_outline,
                          text: 'Skuvano',
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.labelLarge),
      ],
    );
  }
}
