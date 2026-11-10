import 'package:flutter/material.dart';

import '../../domain/plan_calendar.dart';
import '../../domain/shopping_source.dart';
import '../../domain/time_budget.dart';

/// Provera vremena za obrok na dan [date]; null kad dan nema ograničenja.
TimeCheck? mealTimeCheck(
  RecipeSnapshot? snapshot,
  CivilDate date,
  List<DayBudget> budgets,
) {
  if (snapshot == null) return null;
  return checkTime(
    budget: budgetFor(budgets, date.weekday),
    activeMinutes: snapshot.activeMinutes,
    totalMinutes: snapshot.totalMinutes,
  );
}

/// Kratka oznaka provere vremena: tekstom, ne samo bojom. [detailed]
/// prikazuje i razloge i "staje".
class TimeCheckNote extends StatelessWidget {
  const TimeCheckNote(this.check, {super.key, this.detailed = false});

  final TimeCheck? check;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final check = this.check;
    if (check == null || (check.fit == TimeFit.fits && !detailed)) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (check.fit) {
      TimeFit.exceeds => (
        Icons.timer_off_outlined,
        'Preko vremena',
        colors.error,
      ),
      TimeFit.unknown => (
        Icons.help_outline,
        'Vreme nepoznato',
        colors.onSurfaceVariant,
      ),
      TimeFit.fits => (
        Icons.timer_outlined,
        'Staje u vreme za taj dan',
        colors.primary,
      ),
    };
    final text = detailed && check.reasons.isNotEmpty
        ? '$label: ${check.reasons.join(' ')}'
        : label;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
