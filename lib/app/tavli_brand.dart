import 'package:flutter/material.dart';

/// Isti znak u zaglavlju i bočnoj navigaciji; boje prati izabrana tema.
class TavliBrand extends StatelessWidget {
  const TavliBrand({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mark = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.spa_outlined,
        size: 22,
        color: theme.colorScheme.onPrimary,
        semanticLabel: compact ? 'Tavli' : null,
      ),
    );
    if (compact) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: mark),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'Tavli',
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 20,
              letterSpacing: -0.6,
            ),
          ),
        ),
      ],
    );
  }
}
