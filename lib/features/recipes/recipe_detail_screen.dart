import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/recipe.dart';
import '../../domain/shopping_source.dart';
import '../planning/planning_providers.dart';
import 'cooking_screen.dart';
import 'ingredient_review_sheet.dart';
import 'keep_screen_on.dart';
import 'recipe_json_actions.dart';
import 'recipe_providers.dart';
import 'recipe_view.dart';
import 'versions_sheet.dart';

enum _MenuAction { cookSoon, undo, versions, export, delete }

/// Detalji recepta. [embedded] je desni deo podeljenog prikaza (bez "nazad").
class RecipeDetailScreen extends ConsumerWidget {
  const RecipeDetailScreen({
    super.key,
    required this.id,
    this.embedded = false,
  });

  final String id;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(recipeProvider(id))
        .when(
          loading: () => Scaffold(
            appBar: AppBar(automaticallyImplyLeading: !embedded),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Scaffold(
            appBar: AppBar(automaticallyImplyLeading: !embedded),
            body: const Center(child: Text('Recept nije učitan.')),
          ),
          data: (recipe) => recipe == null
              ? Scaffold(
                  appBar: AppBar(automaticallyImplyLeading: !embedded),
                  body: Center(
                    child: Text(
                      embedded ? 'Izaberi recept' : 'Recept više ne postoji.',
                    ),
                  ),
                )
              : _Detail(recipe: recipe, embedded: embedded),
        );
  }
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({required this.recipe, required this.embedded});

  final Recipe recipe;
  final bool embedded;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  bool _cooking = false;

  Future<void> _startCooking() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final recipe = widget.recipe;
    setState(() => _cooking = true);
    // Dispose the detail's scope before the cooking screen takes ownership.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final route = MaterialPageRoute<void>(
      builder: (_) => CookingScreen(
        snapshot: RecipeSnapshot.fromRecipe(recipe),
        servings: recipe.servings,
      ),
    );
    await navigator.push<void>(route);
    // A pop completes before its exit transition disposes the old scope.
    await route.completed;
    if (mounted) setState(() => _cooking = false);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final recipe = widget.recipe;
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(recipeRepositoryProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Obrisati „${recipe.title}“?'),
        content: const Text('Brišu se i prethodne verzije i slika.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Otkaži'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Obriši'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    context.go('/recipes');
    await repo.delete(recipe.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Recept je obrisan.')));
  }

  Future<void> _addToCookSoon(BuildContext context, WidgetRef ref) async {
    final recipe = widget.recipe;
    final messenger = ScaffoldMessenger.of(context);
    var text = 'Dodato u „Uskoro kuvam“. Rasporedi ga u Planu.';
    try {
      await ref.read(cookSoonRepositoryProvider).add(recipe);
    } on Exception {
      text = 'Recept nije dodat. Pokušaj ponovo.';
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;
    final embedded = widget.embedded;
    final hasVersions =
        ref.watch(recipeVersionsProvider(recipe.id)).value?.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !embedded,
        title: Text(recipe.title),
        actions: [
          const KeepScreenOnButton(),
          IconButton(
            tooltip: 'Izmeni sa AI',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => context.go('/recipes/${recipe.id}/chat'),
          ),
          IconButton(
            tooltip: 'Izmeni',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.go('/recipes/${recipe.id}/edit'),
          ),
          PopupMenuButton<_MenuAction>(
            tooltip: 'Još opcija',
            onSelected: (action) => switch (action) {
              _MenuAction.cookSoon => _addToCookSoon(context, ref),
              _MenuAction.undo => undoLastChange(context, ref, recipe.id),
              _MenuAction.versions => showVersionsSheet(context, recipe.id),
              _MenuAction.export => exportRecipeJson(context, ref, recipe),
              _MenuAction.delete => _delete(context, ref),
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _MenuAction.cookSoon,
                child: Text('Dodaj u „Uskoro kuvam“'),
              ),
              PopupMenuItem(
                value: _MenuAction.undo,
                enabled: hasVersions,
                child: const Text('Poništi poslednju izmenu'),
              ),
              const PopupMenuItem(
                value: _MenuAction.versions,
                child: Text('Prethodne verzije'),
              ),
              const PopupMenuItem(
                value: _MenuAction.export,
                child: Text('Izvezi kao JSON'),
              ),
              const PopupMenuItem(
                value: _MenuAction.delete,
                child: Text('Obriši recept'),
              ),
            ],
          ),
        ],
      ),
      body: _cooking
          ? const SizedBox.shrink()
          : KeepScreenOnScope(
              child: ReadableScroll(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _startCooking,
                        icon: const Icon(Icons.soup_kitchen_outlined),
                        label: const Text('Kreni sa kuvanjem'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => showIngredientReview(
                          context,
                          snapshot: RecipeSnapshot.fromRecipe(recipe),
                          originKey: 'recipe:${recipe.id}',
                          recipeId: recipe.id,
                        ),
                        icon: const Icon(Icons.checklist),
                        label: const Text('Proveri sastojke'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  RecipeView(recipe),
                ],
              ),
            ),
    );
  }
}
