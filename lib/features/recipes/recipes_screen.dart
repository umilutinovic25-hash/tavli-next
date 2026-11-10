import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/animations/spoon_refresh.dart';
import '../../app/section_heading.dart';
import '../../app/tab_app_bar.dart';
import '../../app/theme/tavli_colors.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_format.dart';
import 'add_recipe_sheet.dart';
import 'recipe_detail_screen.dart';
import 'recipe_grid.dart';
import 'recipe_photo.dart';
import 'recipe_providers.dart';

/// Od ove širine sadržaja lista i recept stoje jedno pored drugog.
const splitViewMinWidth = 840.0;

/// Tab "Recepti": lista sa pretragom; na širokom ekranu i izabrani recept.
class RecipesScreen extends StatelessWidget {
  const RecipesScreen({super.key, this.selectedId});

  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= splitViewMinWidth;
        final selected = selectedId;
        return Scaffold(
          appBar: const TabAppBar(),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showAddRecipeSheet(context),
            icon: const Icon(Icons.add),
            label: const Text('Dodaj recept'),
          ),
          body: wide
              ? Row(
                  children: [
                    SizedBox(
                      width: 360,
                      child: _RecipeList(selectedId: selected),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: selected == null
                          ? const _NothingSelected()
                          : RecipeDetailScreen(id: selected, embedded: true),
                    ),
                  ],
                )
              : _RecipeList(selectedId: selected),
        );
      },
    );
  }
}

/// Ruta `/recipes/:id`: podeljen prikaz na širokom ekranu, inače ceo ekran.
class RecipeRoute extends StatelessWidget {
  const RecipeRoute({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= splitViewMinWidth
          ? RecipesScreen(selectedId: id)
          : RecipeDetailScreen(id: id),
    );
  }
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Izaberi recept',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _RecipeList extends ConsumerStatefulWidget {
  const _RecipeList({this.selectedId});

  final String? selectedId;

  @override
  ConsumerState<_RecipeList> createState() => _RecipeListState();
}

class _RecipeListState extends ConsumerState<_RecipeList> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(recipeSearchProvider));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Osvežavanje traje samo dok se lista čita iz baze.
  Future<void> _refresh() async {
    ref.invalidate(recipesProvider);
    await ref.read(recipesProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(recipeSearchProvider);
    final grid = ref.watch(recipeGridViewProvider);
    return ref
        .watch(recipesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const _Message(
            icon: Icons.error_outline,
            title: 'Recepti nisu učitani.',
          ),
          data: (all) {
            if (all.isEmpty) {
              return const _Message(
                icon: Icons.menu_book_outlined,
                title: 'Još nema recepata',
                body: 'Dodaj prvi recept iz slike, po nazivu jela ili ručno.',
              );
            }
            final recipes = filterRecipes(all, query);
            final controls = <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SearchBar(
                  controller: _search,
                  hintText: 'Pretraži recepte',
                  leading: const Icon(Icons.search),
                  onChanged: ref.read(recipeSearchProvider.notifier).set,
                  trailing: [
                    if (query.isNotEmpty)
                      IconButton(
                        tooltip: 'Obriši pretragu',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          ref.read(recipeSearchProvider.notifier).set('');
                        },
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.view_list_outlined),
                        tooltip: 'Prikaži listu',
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.grid_view_outlined),
                        tooltip: 'Prikaži mrežu',
                      ),
                    ],
                    selected: {grid},
                    onSelectionChanged: (value) => ref
                        .read(recipeGridViewProvider.notifier)
                        .set(value.single),
                  ),
                ),
              ),
            ];
            if (grid && recipes.isNotEmpty) {
              return Column(
                children: [
                  ...controls,
                  Expanded(
                    child: SpoonRefresh(
                      onRefresh: _refresh,
                      child: RecipeGrid(
                        recipes: recipes,
                        selectedId: widget.selectedId,
                      ),
                    ),
                  ),
                ],
              );
            }
            return Column(
              children: [
                ...controls,
                Expanded(
                  child: recipes.isEmpty
                      ? _Message(
                          icon: Icons.search_off,
                          title: 'Nema recepata za „${query.trim()}“.',
                        )
                      : SpoonRefresh(
                          onRefresh: _refresh,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                            itemCount: recipes.length + 1,
                            itemBuilder: (context, i) {
                              if (i == 0) {
                                return const Padding(
                                  padding: EdgeInsets.only(top: 12, bottom: 24),
                                  child: SectionHeading(
                                    eyebrow: 'Tvoja kuhinja',
                                    title: 'Recepti',
                                    subtitle:
                                        'Sačuvaj ideje kojima se rado vraćaš.',
                                  ),
                                );
                              }
                              final recipe = recipes[i - 1];
                              return _RecipeTile(
                                recipe,
                                index: i - 1,
                                selected: recipe.id == widget.selectedId,
                              );
                            },
                          ),
                        ),
                ),
              ],
            );
          },
        );
  }
}

/// Kartica recepta: sličica (ili boja teme) i naziv sa porcijama i vremenom.
class _RecipeTile extends StatelessWidget {
  const _RecipeTile(this.recipe, {required this.index, required this.selected});

  final Recipe recipe;
  final int index;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final path = recipe.imagePath;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          selected: selected,
          shape: const RoundedRectangleBorder(),
          contentPadding: const EdgeInsets.fromLTRB(10, 6, 16, 6),
          minTileHeight: 84,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox.square(
              dimension: 64,
              child: path == null
                  ? ColoredBox(
                      color: TavliColors.of(context).tint(index),
                      child: Icon(
                        Icons.soup_kitchen_outlined,
                        size: 30,
                        color: colors.onPrimaryContainer,
                      ),
                    )
                  : RecipePhoto(path, size: 64),
            ),
          ),
          titleTextStyle: Theme.of(context).textTheme.titleMedium,
          title: Text(recipe.title),
          subtitle: Text(
            [
              servingsLabel(recipe.servings),
              if (recipe.prepMinutes != null) '${recipe.prepMinutes} min',
            ].join(' · '),
          ),
          onTap: () => context.go('/recipes/${recipe.id}'),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, this.body});

  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              const SizedBox(height: 4),
              Text(body!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
