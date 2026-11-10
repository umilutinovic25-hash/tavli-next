import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/animations/empty_fridge.dart';
import '../../app/placeholder_screen.dart';
import '../../app/tab_app_bar.dart';
import '../../data/database.dart';
import '../../data/pantry_repository.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_format.dart';
import '../recipes/recipe_providers.dart';
import '../shopping/shopping_providers.dart';
import 'pantry_check_dialog.dart';
import 'pantry_item_tile.dart';
import 'pantry_providers.dart';

class PantryScreen extends ConsumerStatefulWidget {
  const PantryScreen({super.key});
  @override
  ConsumerState<PantryScreen> createState() => _PantryScreenState();
}

class _PantryScreenState extends ConsumerState<PantryScreen> {
  final _search = TextEditingController();
  PantryFilter _filter = PantryFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  final _checking = <String>{};

  Future<void> _check(PantryItemRow item, PantryCheck check) async {
    if (_checking.contains(item.id)) return;
    setState(() => _checking.add(item.id));
    final repo = ref.read(pantryRepositoryProvider);
    try {
      if (check == PantryCheck.have) {
        final saved = await showDialog<bool>(
          context: context,
          builder: (_) => PantryCheckDialog(item: item, repository: repo),
        );
        if (saved != true) return;
      } else {
        await repo.checkQuantity(
          item.id,
          quantity: check == PantryCheck.empty ? 0 : null,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Stanje je provereno.')));
    } on PantryItemMissing {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Namirnica nije pronađena.')),
        );
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Provera nije sačuvana. Pokušaj ponovo.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checking.remove(item.id));
    }
  }

  Widget _addButton() => FilledButton.icon(
    onPressed: () => context.go('/pantry/new'),
    icon: const Icon(Icons.add),
    label: const Text('Dodaj namirnicu'),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ref
        .watch(pantryItemsProvider)
        .when(
          loading: () => const Scaffold(
            appBar: TabAppBar(),
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => EmptyStateScreen(
            art: const Icon(Icons.error_outline, size: 56),
            title: 'Ostava trenutno ne može da se prikaže.',
            action: OutlinedButton(
              onPressed: () => ref.invalidate(pantryItemsProvider),
              child: const Text('Pokušaj ponovo'),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return EmptyStateScreen(
                art: const EmptyFridge(),
                title: 'Još nema unetih namirnica',
                body: 'Ovde ćeš pratiti namirnice koje imaš kod kuće.',
                action: _addButton(),
              );
            }
            final now = ref.watch(clockProvider)();
            final query = normalizeForSearch(_search.text);
            final filtered = items
                .where(
                  (item) =>
                      normalizeForSearch(item.name).contains(query) &&
                      switch (_filter) {
                        PantryFilter.all => true,
                        PantryFilter.soon => pantrySoon(item, now),
                        PantryFilter.expired => pantryExpired(item, now),
                      },
                )
                .toList();
            final categories = <String, List<Widget>>{};
            for (final item in filtered) {
              final category = ingredientCategories.contains(item.category)
                  ? item.category
                  : 'ostalo';
              categories
                  .putIfAbsent(category, () => [])
                  .add(
                    PantryItemTile(
                      item: item,
                      now: now,
                      onEdit: () => context.go('/pantry/${item.id}/edit'),
                      onCheck: _checking.contains(item.id)
                          ? null
                          : (check) => _check(item, check),
                    ),
                  );
            }
            return Scaffold(
              appBar: const TabAppBar(),
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 840),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            'Ostava',
                            style: theme.textTheme.headlineMedium,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Namirnice koje imaš kod kuće.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _addButton(),
                        ),
                        const SizedBox(height: 16),
                        SearchBar(
                          controller: _search,
                          hintText: 'Pretraži ostavu',
                          leading: const Icon(Icons.search),
                          onChanged: (_) => setState(() {}),
                          trailing: [
                            if (_search.text.isNotEmpty)
                              IconButton(
                                tooltip: 'Obriši pretragu',
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(_search.clear),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final filter in PantryFilter.values)
                              ChoiceChip(
                                label: Text(filter.label),
                                selected: _filter == filter,
                                onSelected: (_) =>
                                    setState(() => _filter = filter),
                              ),
                          ],
                        ),
                        if (filtered.isEmpty) ...[
                          const SizedBox(height: 32),
                          Text(
                            'Nema namirnica za ovaj izbor',
                            style: theme.textTheme.titleMedium,
                          ),
                          const Text('Promeni pretragu ili filter.'),
                        ],
                        for (final category in ingredientCategories)
                          if (categories[category] case final tiles?) ...[
                            const SizedBox(height: 24),
                            Semantics(
                              header: true,
                              child: Text(
                                '${category[0].toUpperCase()}${category.substring(1)}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...tiles,
                          ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
  }
}
