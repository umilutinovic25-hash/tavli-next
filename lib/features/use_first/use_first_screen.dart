import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/recipe.dart';
import '../../domain/use_first.dart';
import '../recipes/recipe_providers.dart';
import '../shopping/shopping_providers.dart';
import 'suggestion_card.dart';

final suggestionStockProvider = StreamProvider.autoDispose<List<PantryStock>>(
  (ref) => ref.watch(pantryRepositoryProvider).watchSuggestionStock(),
);

class UseFirstButton extends StatelessWidget {
  const UseFirstButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Potroši prvo',
    icon: const Icon(Icons.restaurant_outlined),
    onPressed: () => context.push('/use-first'),
  );
}

class UseFirstScreen extends ConsumerStatefulWidget {
  const UseFirstScreen({super.key});
  @override
  ConsumerState<UseFirstScreen> createState() => _UseFirstScreenState();
}

class _UseFirstScreenState extends ConsumerState<UseFirstScreen> {
  int _servings = 2;
  bool _readyOnly = false;
  String _query = '';
  late final Timer _timer;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
    _lifecycle = AppLifecycleListener(onResume: _refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recipes = ref.watch(recipesProvider);
    final stock = ref.watch(suggestionStockProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Potroši prvo'),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/pantry');
            }
          },
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: recipes.hasError || stock.hasError
              ? _message(
                  'Predlozi trenutno nisu dostupni.',
                  'Pokušaj ponovo',
                  () {
                    ref.invalidate(recipesProvider);
                    ref.invalidate(suggestionStockProvider);
                  },
                )
              : !recipes.hasValue || !stock.hasValue
              ? const Center(child: CircularProgressIndicator())
              : _content(recipes.requireValue, stock.requireValue),
        ),
      ),
    );
  }

  Widget _content(List<Recipe> recipes, List<PantryStock> stock) {
    final suggestions = suggestRecipes(
      recipes,
      stock,
      now: ref.read(clockProvider)(),
      servings: _servings,
    );
    final filtered = suggestions
        .where(
          (s) =>
              (!_readyOnly || s.ready) &&
              s.recipe.title.toLowerCase().contains(
                _query.toLowerCase().trim(),
              ),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Od onoga što već imaš',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Prednost imaju namirnice kojima rok ističe u narednih 7 dana. Računamo potvrđene, slobodne količine iz Ostave.',
        ),
        const SizedBox(height: 12),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            const Text('Porcije'),
            IconButton(
              tooltip: 'Manje porcija',
              onPressed: _servings > 1
                  ? () => setState(() => _servings--)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            Text('$_servings', semanticsLabel: '$_servings porcija'),
            IconButton(
              tooltip: 'Više porcija',
              onPressed: _servings < 20
                  ? () => setState(() => _servings++)
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Pretraži predloge',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Svi predlozi'),
              selected: !_readyOnly,
              onSelected: (_) => setState(() => _readyOnly = false),
            ),
            ChoiceChip(
              label: const Text('Mogu sada'),
              selected: _readyOnly,
              onSelected: (_) => setState(() => _readyOnly = true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (recipes.isEmpty)
          _message(
            'Sačuvaj recepte da bismo ih povezali sa Ostavom.',
            'Otvori recepte',
            () => context.go('/recipes'),
          )
        else if (suggestions.isEmpty)
          _message(
            'Nema recepata sa raspoloživim sastojcima. Proveri količine, potvrdu i rokove u Ostavi.',
            'Otvori Ostavu',
            () => context.go('/pantry'),
          )
        else if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nema predloga za izabranu pretragu i filter.'),
          )
        else ...[
          Text('Predlozi: ${filtered.length} · Porcije: $_servings'),
          const SizedBox(height: 8),
          for (final suggestion in filtered)
            SuggestionCard(suggestion: suggestion),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Svaki predlog računa se zasebno. Pregled ne rezerviše i ne troši namirnice.',
            ),
          ),
        ],
      ],
    );
  }

  Widget _message(String text, String label, VoidCallback action) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        const SizedBox(height: 12),
        FilledButton(onPressed: action, child: Text(label)),
      ],
    ),
  );
}
