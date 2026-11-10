import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/saved_recipe_search.dart';
import 'recipe_providers.dart';

class SavedSearchDialog extends ConsumerStatefulWidget {
  const SavedSearchDialog({super.key, required this.initial});
  final RecipeSearchFilter initial;
  @override
  ConsumerState<SavedSearchDialog> createState() => _SavedSearchDialogState();
}

class _SavedSearchDialogState extends ConsumerState<SavedSearchDialog> {
  late final TextEditingController query, minutes, include, exclude;
  final form = GlobalKey<FormState>();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    query = TextEditingController(text: widget.initial.query);
    minutes = TextEditingController(
      text: widget.initial.maxMinutes?.toString() ?? '',
    );
    include = TextEditingController(text: widget.initial.includeIngredient);
    exclude = TextEditingController(text: widget.initial.excludeIngredient);
  }

  @override
  void dispose() {
    query.dispose();
    minutes.dispose();
    include.dispose();
    exclude.dispose();
    super.dispose();
  }

  RecipeSearchFilter get filter => RecipeSearchFilter(
    query: query.text.trim(),
    maxMinutes: int.tryParse(minutes.text.trim()),
    includeIngredient: include.text.trim(),
    excludeIngredient: exclude.text.trim(),
  );

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (!mounted || name == null) return;
    setState(() => busy = true);
    try {
      await ref.read(recipeRepositoryProvider).saveSearch(name, filter);
    } on Exception catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pretraga nije sačuvana. Pokušaj ponovo.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(String id) async {
    setState(() => busy = true);
    try {
      await ref.read(recipeRepositoryProvider).deleteSearch(id);
    } on Exception catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pretraga nije obrisana. Pokušaj ponovo.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedRecipeSearchesProvider);
    return AlertDialog(
      title: const Text('Filteri'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: query,
                  decoration: const InputDecoration(
                    labelText: 'Pretraži recepte',
                  ),
                ),
                TextFormField(
                  controller: minutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Do minuta'),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isNotEmpty &&
                        (int.tryParse(text) == null || int.parse(text) <= 0)) {
                      return 'Unesi pozitivan broj minuta.';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: include,
                  decoration: const InputDecoration(labelText: 'Sa sastojkom'),
                ),
                TextFormField(
                  controller: exclude,
                  decoration: const InputDecoration(labelText: 'Bez sastojka'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pretraga po nazivu sastojka; nije provera alergena.',
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: busy ? null : save,
                  child: const Text('Sačuvaj pretragu'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Sačuvane pretrage',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                saved.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) =>
                      const Text('Sačuvane pretrage nisu učitane.'),
                  data: (searches) => Column(
                    children: [
                      for (final search in searches)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(search.name),
                          onTap: busy
                              ? null
                              : () => Navigator.pop(context, search.filter),
                          trailing: IconButton(
                            tooltip: 'Obriši pretragu',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: busy ? null : () => remove(search.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy
              ? null
              : () => Navigator.pop(context, const RecipeSearchFilter()),
          child: const Text('Očisti filtere'),
        ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Otkaži'),
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () {
                  if (form.currentState!.validate()) {
                    Navigator.pop(context, filter);
                  }
                },
          child: const Text('Primeni'),
        ),
      ],
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final controller = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Naziv pretrage'),
    content: Form(
      key: form,
      child: TextFormField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Naziv pretrage'),
        validator: (value) =>
            (value?.trim().isEmpty ?? true) ? 'Unesi naziv pretrage.' : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Otkaži'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: const Text('Sačuvaj'),
      ),
    ],
  );
}
