import 'package:flutter/material.dart';

/// Oznaka „Nepotvrđeno“ u redu liste (Ostava, nabavka, detalj recepta):
/// ikonica sa opisom, da red ne postane viši. Pun tekst i izbor namirnice
/// su u formi reda (`FoodChip`).
class UnconfirmedMark extends StatelessWidget {
  const UnconfirmedMark({super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Nepotvrđeno',
    child: Icon(
      Icons.help_outline,
      size: 18,
      semanticLabel: 'Nepotvrđeno',
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
