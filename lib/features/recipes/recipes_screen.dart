import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tavli_ui/tavli_ui.dart';

import '../../ai/ai_errors.dart';
import '../../ai/embedding_client.dart';
import '../../ai/recipe_semantic_search.dart';
import '../../app/animations/empty_tabs.dart';
import '../../app/animations/spoon_refresh.dart';
import '../../app/app_menu.dart';
import '../../app/home_shell.dart' show wideLayoutWidth;
import '../../app/tab_app_bar.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_format.dart';
import '../../domain/recipe_labels.dart';
import '../../domain/recipe_search.dart';
import 'add_recipe_sheet.dart';
import 'recipe_detail_screen.dart';
import 'recipe_photo.dart';
import 'recipe_providers.dart';

/// Od ove širine sadržaja recepti su mreža u tri kolone sa zaglavljem
/// (platno, macOS i Windows · Recepti); uže je lista kartica kao na telefonu.
const _gridMinWidth = 840.0;

/// Polje za pretragu u zaglavlju, kao na platnu.
const _searchWidth = 300.0;

/// Kolone mreže recepata na računaru, kao na platnu; kolone su jednake i
/// rastu sa prozorom.
const _gridColumns = 3;

/// Prazan prostor ispod liste na telefonu, da plutajuće dugme ne pokrije
/// poslednji recept.
const _floatingButtonClearance = 88.0;

/// Tab "Recepti", po platnu. Telefon: pretraga, lista kartica u jednoj
/// koloni i plutajuće „Dodaj recept“. Računar: zaglavlje sa pretragom i
/// „Dodaj recept“ i mreža u tri kolone. Recept se otvara kao ceo ekran.
class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ⌘N iz trake menija na macOS-u.
    ref.listen(menuRequestsProvider, (_, next) {
      if (next?.command == MenuCommand.newRecipe &&
          ModalRoute.isCurrentOf(context) == true) {
        unawaited(showAddRecipeSheet(context));
      }
    });
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _gridMinWidth;
        // Uz bočnu navigaciju (računar) „Dodaj recept“ je u zaglavlju, kao
        // na platnu, i kad je prozor uzak za mrežu.
        final header =
            wide || MediaQuery.sizeOf(context).width >= wideLayoutWidth;
        return Scaffold(
          appBar: const TabAppBar(),
          floatingActionButton: header
              ? null
              : TavliFloatingButton(
                  icon: Icons.add,
                  label: 'Dodaj recept',
                  onPressed: () => showAddRecipeSheet(context),
                ),
          body: _RecipesBody(wide: wide, header: header),
        );
      },
    );
  }
}

/// Ruta `/recipes/:id`: recept kao ceo ekran na svim platformama (platno
/// nema listu i detalj u Receptima).
class RecipeRoute extends StatelessWidget {
  const RecipeRoute({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => RecipeDetailScreen(id: id);
}

class _RecipesBody extends ConsumerStatefulWidget {
  const _RecipesBody({required this.wide, required this.header});

  /// Mreža kartica umesto liste.
  final bool wide;

  /// Zaglavlje „Recepti“ sa pretragom i „Dodaj recept“ (računar).
  final bool header;

  @override
  ConsumerState<_RecipesBody> createState() => _RecipesBodyState();
}

class _RecipesBodyState extends ConsumerState<_RecipesBody> {
  late final TextEditingController _search;

  // Pretraga prelazi iz liste u zaglavlje kad se prozor raširi; ključ čuva
  // isto polje, pa tekst i fokus ostaju.
  final _searchKey = GlobalKey();
  final _searchFocus = FocusNode(debugLabel: 'Pretraži recepte');
  Timer? _semanticSearchTimer;
  List<Recipe>? _semanticResults;
  Object? _semanticError;
  bool _semanticLoading = false;
  bool _semanticSearch = false;
  int _semanticGeneration = 0;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(recipeSearchProvider).query);
  }

  @override
  void dispose() {
    _semanticSearchTimer?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Osvežavanje traje samo dok se lista čita iz baze.
  Future<void> _refresh() async {
    ref.invalidate(recipesProvider);
    await ref.read(recipesProvider.future);
  }

  Widget _searchField() => TavliSearchField(
    key: _searchKey,
    hint: 'Pretraži recepte',
    controller: _search,
    focusNode: _searchFocus,
    onChanged: ref.read(recipeSearchProvider.notifier).setQuery,
  );

  Future<void> _toggleSemanticSearch(bool enabled) async {
    if (!enabled) {
      _semanticGeneration++;
      setState(() {
        _semanticSearch = false;
        _semanticResults = null;
        _semanticError = null;
      });
      _semanticSearchTimer?.cancel();
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pretraga preko OpenAI-ja'),
        content: const Text(
          'Upit i tekst recepata biće poslati OpenAI-ju radi pretrage. '
          'Nastavi samo sa sadržajem koji želiš da pošalješ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Otkaži'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Nastavi'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _semanticSearch = true;
      _semanticResults = null;
      _semanticError = null;
    });
    _queueSemanticSearch(ref.read(recipeSearchProvider));
  }

  void _queueSemanticSearch(RecipeFilter filter) {
    final generation = ++_semanticGeneration;
    _semanticSearchTimer?.cancel();
    if (!_semanticSearch || filter.query.trim().isEmpty) {
      setState(() {
        _semanticLoading = false;
        _semanticResults = null;
        _semanticError = null;
      });
      return;
    }
    setState(() {
      _semanticLoading = true;
      _semanticError = null;
    });
    _semanticSearchTimer = Timer(const Duration(milliseconds: 450), () {
      unawaited(_runSemanticSearch(filter, generation));
    });
  }

  Future<void> _runSemanticSearch(RecipeFilter filter, int generation) async {
    try {
      final all = await ref.read(recipesProvider.future);
      final service = ref.read(recipeSemanticSearchServiceProvider);
      if (service == null) throw const EmbeddingServiceUnavailableException();
      final results = await service.search(
        query: filter.query,
        recipes: all,
        filter: filter,
      );
      if (!mounted ||
          !_semanticSearch ||
          generation != _semanticGeneration ||
          ref.read(recipeSearchProvider) != filter) {
        return;
      }
      setState(() {
        _semanticLoading = false;
        _semanticResults = results;
        _semanticError = null;
      });
    } on Object catch (error) {
      if (!mounted ||
          !_semanticSearch ||
          generation != _semanticGeneration ||
          ref.read(recipeSearchProvider) != filter) {
        return;
      }
      setState(() {
        _semanticLoading = false;
        _semanticError = error;
      });
    }
  }

  Widget _semanticButton() => TavliIconButton(
    glyph: TavliIcons.sparkle,
    semanticLabel: _semanticSearch
        ? 'Isključi pretragu po smislu'
        : 'Pretraži po smislu',
    selected: _semanticSearch,
    onPressed: () => _toggleSemanticSearch(!_semanticSearch),
  );

  Widget _filterButton(RecipeFilter filter) => TavliIconButton(
    glyph: TavliIcons.filter,
    semanticLabel: filter.hasFilters
        ? 'Filteri (${filter.activeFilters})'
        : 'Filteri',
    selected: filter.hasFilters,
    onPressed: () => showTavliSheet<void>(
      context,
      title: 'Filteri',
      builder: (_) => const _RecipeFilterSheet(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // ⌘F iz trake menija na macOS-u.
    ref.listen(menuRequestsProvider, (_, next) {
      if (next?.command == MenuCommand.searchRecipes) {
        _searchFocus.requestFocus();
      }
    });
    final filter = ref.watch(recipeSearchProvider);
    ref.listen(recipeSearchProvider, (previous, next) {
      if (_semanticSearch && previous != next) _queueSemanticSearch(next);
    });
    ref.listen(recipesProvider, (previous, next) {
      if (_semanticSearch && previous?.value != next.value) {
        _queueSemanticSearch(ref.read(recipeSearchProvider));
      }
    });
    final content = ref
        .watch(recipesProvider)
        .when(
          loading: () => const TavliLoading(),
          error: (_, _) => const _ScrollableMessage(
            TavliEmptyState(
              glyph: TavliIcons.info,
              title: 'Recepti nisu učitani.',
            ),
          ),
          data: (all) {
            if (all.isEmpty) {
              return const _ScrollableMessage(
                TavliEmptyState(
                  art: EmptyCookbook(),
                  title: 'Još nema recepata',
                  message:
                      'Dodaj prvi recept sa slike, po nazivu jela ili ručno.',
                ),
              );
            }
            final recipes = _semanticSearch && filter.query.trim().isNotEmpty
                ? _semanticResults ?? const <Recipe>[]
                : searchRecipes(all, filter);
            if (_semanticSearch && filter.query.trim().isNotEmpty) {
              if (_semanticLoading) return const TavliLoading();
              if (_semanticError != null) {
                final message = switch (_semanticError) {
                  EmbeddingServiceUnavailableException() =>
                    'Pretraga preko AI-ja trenutno nije dostupna.',
                  GatewayQuotaError() =>
                    'AI limit je dostignut. Pokušaj kasnije.',
                  RateLimitError() => 'OpenAI je trenutno ograničio broj zahteva. Pokušaj kasnije.',
                  GatewayAuthError() => 'Sesija je istekla. Prijavi se ponovo.',
                  GatewayUnavailableError() =>
                    'Pretraga preko AI-ja trenutno nije dostupna.',
                  EmbeddingRequestException(:final message) => message,
                  _ => 'Semantička pretraga trenutno nije uspela.',
                };
                return _ScrollableMessage(
                  TavliEmptyState(glyph: TavliIcons.info, title: message),
                );
              }
            }
            if (recipes.isEmpty) {
              return _ScrollableMessage(
                _semanticSearch && filter.query.trim().isNotEmpty
                    ? const TavliEmptyState(
                        glyph: TavliIcons.search,
                        title: 'Nema sličnih recepata.',
                      )
                    : filter.hasFilters
                    ? TavliEmptyState(
                        glyph: TavliIcons.search,
                        title: 'Nema recepata za izabrane filtere.',
                        action: TavliButton.secondary(
                          label: 'Očisti filtere',
                          onPressed: ref
                              .read(recipeSearchProvider.notifier)
                              .clearFilters,
                        ),
                      )
                    : TavliEmptyState(
                        glyph: TavliIcons.search,
                        title: 'Nema recepata za „${filter.query.trim()}“.',
                      ),
              );
            }
            if (!widget.wide) {
              return _RecipeList(recipes, onRefresh: _refresh);
            }
            return _RecipeGrid(recipes);
          },
        );

    if (!widget.header) {
      final hasRecipes = ref.watch(recipesProvider).value?.isNotEmpty ?? false;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasRecipes)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TavliSpacing.large,
                TavliSpacing.small,
                TavliSpacing.large,
                TavliSpacing.medium,
              ),
              child: Row(
                children: [
                  Expanded(child: _searchField()),
                  const SizedBox(width: TavliSpacing.small),
                  _semanticButton(),
                  const SizedBox(width: TavliSpacing.small),
                  _filterButton(filter),
                ],
              ),
            ),
          Expanded(child: content),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            TavliSpacing.large,
            TavliSpacing.large,
            TavliSpacing.large,
            TavliSpacing.medium,
          ),
          child: TavliPageHeader(
            title: 'Recepti',
            actions: [
              SizedBox(width: _searchWidth, child: _searchField()),
              _semanticButton(),
              _filterButton(filter),
              TavliButton.primary(
                label: 'Dodaj recept',
                icon: Icons.add,
                onPressed: () => showAddRecipeSheet(context),
              ),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}

/// Vreme pa porcije, kao na platnu („75 min · 4 porcije“).
String _recipeFacts(Recipe recipe) => [
  if (recipe.prepMinutes != null) '${recipe.prepMinutes} min',
  servingsLabel(recipe.servings),
].join(' · ');

/// Naziv i vreme sa porcijama, kao na kartici recepta.
class _RecipeTitle extends StatelessWidget {
  const _RecipeTitle(this.recipe);

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(recipe.title, style: t.titleMedium),
        Text(
          _recipeFacts(recipe),
          style: t.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Lista kartica sa sličicom u jednoj koloni (telefon, platno · Recepti).
class _RecipeList extends StatelessWidget {
  const _RecipeList(this.recipes, {required this.onRefresh});

  final List<Recipe> recipes;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return SpoonRefresh(
      onRefresh: onRefresh,
      child: TavliCardGrid(
        // Položaj liste se pamti i kad se prozor na kratko raširi u mrežu.
        key: const PageStorageKey('recipes-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        spacing: TavliSpacing.small,
        padding: const EdgeInsets.fromLTRB(
          TavliSpacing.large,
          0,
          TavliSpacing.large,
          _floatingButtonClearance,
        ),
        itemCount: recipes.length,
        itemBuilder: (context, i) {
          final recipe = recipes[i];
          final path = recipe.imagePath;
          return _RecipeMenu(
            recipe,
            child: TavliCard(
              padding: const EdgeInsets.all(TavliSpacing.small),
              onTap: () => context.go('/recipes/${recipe.id}'),
              child: Row(
                children: [
                  TavliThumbnail.row(
                    tintIndex: i,
                    photo: path == null ? null : RecipePhoto(path),
                  ),
                  const SizedBox(width: TavliSpacing.medium),
                  Expanded(child: _RecipeTitle(recipe)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Mreža recepata u tri kolone na širokom ekranu.
class _RecipeGrid extends StatelessWidget {
  const _RecipeGrid(this.recipes);

  final List<Recipe> recipes;

  @override
  Widget build(BuildContext context) {
    return TavliCardGrid(
      key: const PageStorageKey('recipes-grid'),
      columns: _gridColumns,
      padding: const EdgeInsets.fromLTRB(
        TavliSpacing.large,
        0,
        TavliSpacing.large,
        TavliSpacing.large,
      ),
      itemCount: recipes.length,
      itemBuilder: (context, i) {
        final recipe = recipes[i];
        final path = recipe.imagePath;
        return _RecipeMenu(
          recipe,
          child: TavliCard(
            padding: EdgeInsets.zero,
            onTap: () => context.go('/recipes/${recipe.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TavliThumbnail.cardTop(
                  tintIndex: i,
                  photo: path == null ? null : RecipePhoto(path),
                ),
                Padding(
                  padding: const EdgeInsets.all(TavliSpacing.medium),
                  child: _RecipeTitle(recipe),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Donji list sa filterima. Izbor se primenjuje odmah; „Sve“ isključuje
/// filter.
class _RecipeFilterSheet extends ConsumerWidget {
  const _RecipeFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(recipeSearchProvider);
    final search = ref.read(recipeSearchProvider.notifier);

    Widget section<T>(
      String title,
      List<TavliOption<T?>> options,
      T? selected,
      RecipeFilter Function(T?) apply,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: TavliSpacing.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TavliSectionHeader(title),
          const SizedBox(height: TavliSpacing.small),
          TavliChoice<T?>.chips(
            options: [TavliOption<T?>(null, 'Sve'), ...options],
            selected: selected,
            onChanged: (v) => search.set(apply(v)),
          ),
        ],
      ),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section<MealSuitability>(
            'Obrok',
            [for (final m in MealSuitability.values) TavliOption(m, m.label)],
            filter.meal,
            (v) => filter.copyWith(meal: () => v),
          ),
          section<DishWeight>(
            'Težina',
            [for (final w in DishWeight.values) TavliOption(w, w.label)],
            filter.weight,
            (v) => filter.copyWith(weight: () => v),
          ),
          section<DishKind>(
            'Vrsta jela',
            [for (final k in DishKind.values) TavliOption(k, k.label)],
            filter.dishKind,
            (v) => filter.copyWith(dishKind: () => v),
          ),
          section<int>(
            'Vreme pripreme',
            [for (final m in prepTimeLimits) TavliOption(m, 'Do $m min')],
            filter.maxPrepMinutes,
            (v) => filter.copyWith(maxPrepMinutes: () => v),
          ),
          TavliButtonRow(
            expand: true,
            children: [
              TavliButton.secondary(
                label: 'Očisti filtere',
                onPressed: filter.hasFilters ? search.clearFilters : null,
              ),
              TavliButton.primary(
                label: 'Prikaži recepte',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Desni klik na recept (računar): iste radnje kao na ekranu recepta.
class _RecipeMenu extends StatelessWidget {
  const _RecipeMenu(this.recipe, {required this.child});

  final Recipe recipe;
  final Widget child;

  @override
  Widget build(BuildContext context) => TavliContextMenu(
    actions: [
      TavliMenuAction(
        'Otvori',
        onSelected: () => context.go('/recipes/${recipe.id}'),
      ),
      TavliMenuAction(
        'Izmeni',
        icon: Icons.edit_outlined,
        onSelected: () => context.go('/recipes/${recipe.id}/edit'),
      ),
    ],
    child: child,
  );
}

/// Prazno stanje koje se pomera kad uz veći tekst i navigaciju nema mesta.
class _ScrollableMessage extends StatelessWidget {
  const _ScrollableMessage(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}
