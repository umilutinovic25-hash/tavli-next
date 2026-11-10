import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/recipe_format.dart';
import '../../domain/shopping_demand.dart';
import '../../domain/use_first.dart';

class SuggestionCard extends StatelessWidget {
  const SuggestionCard({super.key, required this.suggestion});
  final RecipeSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final expiry = s.earliestExpiry?.toLocal();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.recipe.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (expiry != null)
              Text(
                'Potroši prvo: ${s.soonIngredients.join(', ')} · rok ${expiry.day}.${expiry.month}.${expiry.year}.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            Text(
              s.ready
                  ? 'Sve poznate količine su dostupne'
                  : '${s.coveredCount}/${s.ingredients.length} sastojaka potpuno pokriveno',
            ),
            Text('Porcije: ${s.servings}'),
            for (final i in s.ingredients.where((i) => i.missingMicros != 0))
              Text(
                i.missingMicros == null
                    ? 'Proveri količinu: ${i.name}'
                    : 'Nedostaje: ${i.name} · ${_amount(i.missingMicros!, i.baseUnit)}',
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () =>
                  context.go('/recipes/${Uri.encodeComponent(s.recipe.id)}'),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Otvori recept'),
            ),
          ],
        ),
      ),
    );
  }
}

String _amount(int micros, String unit) {
  var amount = fromMicros(micros);
  if ((unit == 'g' || unit == 'ml') && amount >= 1000) {
    amount /= 1000;
    unit = unit == 'g' ? 'kg' : 'l';
  }
  return '${formatQuantity(amount)} $unit'.trim();
}
