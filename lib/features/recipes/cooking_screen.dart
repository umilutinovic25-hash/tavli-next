import 'package:flutter/material.dart';

import '../../domain/recipe.dart';
import '../../domain/recipe_format.dart';
import '../../domain/shopping_demand.dart' show scaleQuantity;
import '../../domain/shopping_source.dart';
import 'keep_screen_on.dart';

/// Privremena sesija nad sačuvanim receptom ili odobrenim snimkom plana.
class CookingScreen extends StatefulWidget {
  const CookingScreen({
    super.key,
    required this.snapshot,
    required this.servings,
  });

  final RecipeSnapshot snapshot;
  final int servings;

  @override
  State<CookingScreen> createState() => _CookingScreenState();
}

class _CookingScreenState extends State<CookingScreen> {
  final _ingredientsDone = <int>{};
  final _stepsDone = <int>{};
  var _step = 0;

  void _toggle(Set<int> checked, int index, bool? value) {
    setState(() {
      if (value == true) {
        checked.add(index);
      } else {
        checked.remove(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final theme = Theme.of(context);
    final ingredients = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Sastojci', style: theme.textTheme.titleLarge),
        Text(servingsLabel(widget.servings), style: theme.textTheme.bodyMedium),
        if (snapshot.ingredients.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Nema sastojaka.'),
          ),
        for (final (index, ingredient) in snapshot.ingredients.indexed)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _ingredientsDone.contains(index),
            onChanged: (value) => _toggle(_ingredientsDone, index, value),
            title: Text(
              ingredientLine(
                Ingredient(
                  name: ingredient.name,
                  quantity: widget.servings == snapshot.baseServings
                      ? ingredient.quantity
                      : scaleQuantity(
                          ingredient.quantity,
                          baseServings: snapshot.baseServings,
                          servings: widget.servings,
                        ),
                  unit: ingredient.unit,
                  category: ingredient.category,
                  note: ingredient.note,
                ),
              ),
            ),
          ),
      ],
    );
    final steps = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Priprema', style: theme.textTheme.titleLarge),
        if (snapshot.steps.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Koraci pripreme nisu uneti.'),
          )
        else ...[
          const SizedBox(height: 8),
          Text(
            'Korak ${_step + 1} od ${snapshot.steps.length}',
            style: theme.textTheme.titleMedium,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _stepsDone.contains(_step),
            onChanged: (value) => _toggle(_stepsDone, _step, value),
            title: Text(
              snapshot.steps[_step],
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _step == 0 ? null : () => setState(() => _step--),
                child: const Text('Prethodni'),
              ),
              FilledButton.tonal(
                onPressed: _step == snapshot.steps.length - 1
                    ? null
                    : () => setState(() => _step++),
                child: const Text('Sledeći'),
              ),
            ],
          ),
        ],
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('Kuvanje · ${snapshot.title}'),
        actions: const [KeepScreenOnButton()],
      ),
      body: KeepScreenOnScope(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Oznake važe samo tokom ovog kuvanja.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: ingredients),
                            const SizedBox(width: 32),
                            Expanded(child: steps),
                          ],
                        )
                      else ...[
                        ingredients,
                        const SizedBox(height: 24),
                        steps,
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
