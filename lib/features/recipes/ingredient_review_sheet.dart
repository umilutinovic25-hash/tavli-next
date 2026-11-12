import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/shopping_repository.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_format.dart';
import '../../domain/shopping_demand.dart';
import '../../domain/shopping_source.dart';
import '../../domain/shopping_sync.dart' show sameIngredient;
import '../../providers.dart';
import '../shopping/shopping_providers.dart';

/// "Proveri sastojke": porcije, šta je kod kuće i dodavanje samo onoga što
/// fali u Nabavku. Pregled ništa ne čuva; tek "Dodaj u nabavku" pamti
/// zamrznut recept kao pripremu (bez recepta u biblioteci i bez plana).
/// [originKey] je isti za isti recept, pa ponovno dodavanje menja istu
/// pripremu; [recipeId] je recept iz biblioteke, ako je sačuvan.
Future<void> showIngredientReview(
  BuildContext context, {
  required RecipeSnapshot snapshot,
  required String originKey,
  String? recipeId,
}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  return showModalBottomSheet<void>(
    context: context,
    // Iznad trake tabova i njenih poruka, da dugmad ne budu prekrivena.
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => IngredientReviewSheet(
      snapshot: snapshot,
      originKey: originKey,
      recipeId: recipeId,
    ),
  );
}

class IngredientReviewSheet extends ConsumerStatefulWidget {
  const IngredientReviewSheet({
    super.key,
    required this.snapshot,
    required this.originKey,
    this.recipeId,
  });

  final RecipeSnapshot snapshot;
  final String originKey;
  final String? recipeId;

  @override
  ConsumerState<IngredientReviewSheet> createState() =>
      _IngredientReviewSheetState();
}

class _IngredientReviewSheetState extends ConsumerState<IngredientReviewSheet> {
  late int _servings = widget.snapshot.baseServings.clamp(
    minServings,
    maxServings,
  );

  /// Indeksi sastojaka koje osoba ima kod kuće.
  final _have = <int>{};
  RecipePreparation? _current;
  bool _planned = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final repo = ref.read(shoppingRepositoryProvider);
    final current = await repo.currentPreparation(widget.originKey);
    final planned =
        widget.recipeId != null && await repo.isPlanned(widget.recipeId!);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _planned = planned;
      _current = current;
      if (current != null) {
        // Ranije "imam": sastojci koji nisu u pripremi.
        final missing = current.snapshot.ingredients;
        _servings = current.servings;
        for (final (n, i) in widget.snapshot.ingredients.indexed) {
          if (!missing.any(
            (m) => sameIngredient(m.name, m.foodId, i.name, i.foodId),
          )) {
            _have.add(n);
          }
        }
      }
    });
  }

  Ingredient _scaled(Ingredient i) => i.quantity == null
      ? i
      : Ingredient(
          name: i.name,
          quantity: scaleQuantity(
            i.quantity,
            baseServings: widget.snapshot.baseServings,
            servings: _servings,
          ),
          unit: i.unit,
          category: i.category,
          note: i.note,
        );

  Future<void> _add({required bool repeat}) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    final view = ref.read(shoppingViewProvider.notifier);
    final missing = [
      for (final (n, i) in widget.snapshot.ingredients.indexed)
        if (!_have.contains(n)) i,
    ];
    await ref
        .read(shoppingRepositoryProvider)
        .addRecipePreparation(
          snapshot: widget.snapshot.withIngredients(missing),
          servings: _servings,
          originKey: widget.originKey,
          recipeId: widget.recipeId,
          repeat: repeat,
        );
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            missing.isEmpty
                ? 'Sve imaš; ništa nije dodato.'
                : 'Dodato u nabavku: ${missing.length}',
          ),
          action: SnackBarAction(
            label: 'Otvori',
            onPressed: () {
              view.setMode(ShoppingMode.recipe);
              router.go('/shopping');
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ingredients = widget.snapshot.ingredients;
    final missing = ingredients.length - _have.length;
    final current = _current;
    final busy = _loading || _saving;

    final actions = <Widget>[
      if (current == null)
        FilledButton.icon(
          onPressed: busy || missing == 0 ? null : () => _add(repeat: false),
          icon: const Icon(Icons.add_shopping_cart),
          label: Text(missing == 0 ? 'Sve imaš' : 'Dodaj u nabavku ($missing)'),
        )
      else ...[
        FilledButton.icon(
          onPressed: busy ? null : () => _add(repeat: false),
          icon: const Icon(Icons.check),
          label: const Text('Ažuriraj nabavku'),
        ),
        OutlinedButton.icon(
          onPressed: busy || missing == 0 ? null : () => _add(repeat: true),
          icon: const Icon(Icons.replay),
          label: const Text('Ponovi nabavku'),
        ),
      ],
    ];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Text('Proveri sastojke', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(widget.snapshot.title, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 12),
                if (_planned)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: const Text('Ovaj recept je već u planu.'),
                      subtitle: const Text(
                        'Njegova nabavka je u „Po planu“. Dodavanje ovde je '
                        'posebna priprema.',
                      ),
                      trailing: TextButton(
                        onPressed: () {
                          final router = GoRouter.of(context);
                          ref
                              .read(shoppingViewProvider.notifier)
                              .setMode(ShoppingMode.plan);
                          Navigator.of(context).pop();
                          router.go('/shopping');
                        },
                        child: const Text('Pogledaj'),
                      ),
                    ),
                  ),
                if (current != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Već je u nabavci. „Ažuriraj“ menja istu pripremu, '
                      '„Ponovi nabavku“ dodaje novu.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        servingsLabel(_servings),
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: 'Manje porcija',
                      onPressed: _servings > minServings
                          ? () => setState(() => _servings--)
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Više porcija',
                      onPressed: _servings < maxServings
                          ? () => setState(() => _servings++)
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Označi šta imaš kod kuće.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                for (final (n, i) in ingredients.indexed)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _have.contains(n),
                    onChanged: _loading
                        ? null
                        : (v) => setState(
                            () => v == true ? _have.add(n) : _have.remove(n),
                          ),
                    title: Text(ingredientLine(_scaled(i))),
                    secondary: _have.contains(n) ? const Text('imam') : null,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ),
        ],
      ),
    );
  }
}
