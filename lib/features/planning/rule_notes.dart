import 'package:flutter/material.dart';

import '../../domain/day_rules.dart';

/// Rezultati pravila dana za jedno jelo: krši, izuzetak, odstupa od želje,
/// neprovereno. Pravilo koje jelo poštuje se ne prikazuje.
class RuleNotes extends StatelessWidget {
  const RuleNotes(this.results, {super.key, this.overrides = const {}});

  final List<RuleResult> results;
  final Set<String> overrides;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = [
      for (final r in results)
        if (ruleResultText(r, overridden: overrides.contains(r.rule.id))
            case final text?)
          (r, text),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (r, text) in lines)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  r.fit == RuleFit.unknown ? Icons.help_outline : Icons.rule,
                  size: 16,
                  color: _color(r, theme),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _color(r, theme),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _color(RuleResult r, ThemeData theme) =>
      r.fit == RuleFit.fail &&
          r.rule.mode == RuleMode.required &&
          !overrides.contains(r.rule.id)
      ? theme.colorScheme.error
      : theme.colorScheme.onSurfaceVariant;
}
