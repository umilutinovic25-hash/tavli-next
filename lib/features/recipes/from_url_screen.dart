import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/recipe_url_import.dart';
import '../../providers.dart';
import 'recipe_form_screen.dart';
import 'recipe_view.dart';

final recipeUrlImporterProvider = Provider<RecipeUrlImporter>(
  (ref) => SupabaseRecipeUrlImporter(ref.watch(supabaseClientProvider)),
);

class FromUrlScreen extends ConsumerStatefulWidget {
  const FromUrlScreen({super.key});
  @override
  ConsumerState<FromUrlScreen> createState() => _FromUrlScreenState();
}

class _FromUrlScreenState extends ConsumerState<FromUrlScreen> {
  final _url = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final recipe = await ref
          .read(recipeUrlImporterProvider)
          .fetch(_url.text.trim());
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => RecipeFormScreen(draft: recipe),
        ),
      );
    } on RecipeUrlImportException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e.rateLimited
            ? 'Previše uvoza zaredom. Sačekaj malo pa pokušaj ponovo.'
            : e.noRecipe
            ? 'Na stranici nije pronađen strukturisan recept.'
            : 'Nije moguće učitati recept sa ove adrese. Proveri adresu i pokušaj ponovo.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sa internet adrese')),
    body: ReadableScroll(
      children: [
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Adresa recepta',
            hintText: 'https://...',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _fetch,
          child: const Text('Pregledaj recept'),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}
