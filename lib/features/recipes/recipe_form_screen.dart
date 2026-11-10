import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/ids.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_format.dart';
import '../../domain/recipe_version.dart';
import '../../domain/time_budget.dart';
import 'recipe_providers.dart';

/// Ručni unos novog recepta ([id] == null) ili izmena postojećeg.
class RecipeFormScreen extends ConsumerStatefulWidget {
  const RecipeFormScreen({super.key, this.id});

  final String? id;

  @override
  ConsumerState<RecipeFormScreen> createState() => _RecipeFormScreenState();
}

class _RecipeFormScreenState extends ConsumerState<RecipeFormScreen> {
  final _title = TextEditingController();
  final _servings = TextEditingController(text: '2');
  final _prep = TextEditingController();
  final _active = TextEditingController();
  final _total = TextEditingController();
  String? _timingError;
  final _steps = TextEditingController();
  List<Ingredient> _ingredients = [];
  Recipe? _original;
  bool _loading = false;
  bool _dirty = false;
  bool _saving = false;
  String? _titleError;
  String? _ingredientsError;

  @override
  void initState() {
    super.initState();
    final id = widget.id;
    if (id != null) {
      _loading = true;
      unawaited(_load(id));
    }
  }

  Future<void> _load(String id) async {
    final recipe = await ref.read(recipeRepositoryProvider).get(id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _original = recipe;
      if (recipe != null) {
        _title.text = recipe.title;
        _servings.text = '${recipe.servings}';
        _prep.text = recipe.prepMinutes?.toString() ?? '';
        _active.text = recipe.activeMinutes?.toString() ?? '';
        _total.text = recipe.totalMinutes?.toString() ?? '';
        _steps.text = recipe.steps.join('\n');
        _ingredients = [...recipe.ingredients];
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _servings.dispose();
    _prep.dispose();
    _active.dispose();
    _total.dispose();
    _steps.dispose();
    super.dispose();
  }

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _editIngredient([int? index]) async {
    final result = await showDialog<Ingredient>(
      context: context,
      builder: (context) => _IngredientDialog(
        initial: index == null ? null : _ingredients[index],
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _ingredients = [..._ingredients, result];
      } else {
        _ingredients = [..._ingredients]..[index] = result;
      }
      _dirty = true;
      _ingredientsError = null;
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    setState(() {
      _titleError = title.isEmpty ? 'Unesi naziv recepta.' : null;
      _ingredientsError = _ingredients.isEmpty
          ? 'Dodaj bar jedan sastojak.'
          : null;
    });
    int? minutes(TextEditingController c) => int.tryParse(c.text.trim());
    final active = minutes(_active);
    final total = minutes(_total);
    String? timingError;
    if ((_active.text.trim().isNotEmpty && active == null) ||
        (_total.text.trim().isNotEmpty && total == null)) {
      timingError = 'Vreme upiši u celim minutima.';
    } else if (!isValidTiming(activeMinutes: active, totalMinutes: total)) {
      timingError =
          'Aktivno vreme je broj minuta veći od nule i nije duže od '
          'ukupnog.';
    }
    setState(() => _timingError = timingError);
    if (_titleError != null ||
        _ingredientsError != null ||
        timingError != null) {
      return;
    }

    final servings = (int.tryParse(_servings.text.trim()) ?? 2).clamp(1, 99);
    final prep = int.tryParse(_prep.text.trim());
    final steps = [
      for (final line in _steps.text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    final repo = ref.read(recipeRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final original = _original;
    final Recipe recipe;
    setState(() => _saving = true);
    if (original == null) {
      final now = ref.read(clockProvider)();
      recipe = Recipe(
        id: newId(),
        title: title,
        servings: servings,
        prepMinutes: prep,
        ingredients: _ingredients,
        steps: steps,
        source: RecipeSource.manual,
        createdAt: now,
        activeMinutes: active,
        totalMinutes: total,
      );
      await repo.create(recipe);
    } else {
      recipe = original.copyWith(
        title: title,
        servings: servings,
        prepMinutes: prep,
        clearPrepMinutes: prep == null,
        ingredients: _ingredients,
        steps: steps,
        clearTiming: true,
        activeMinutes: active,
        totalMinutes: total,
      );
      await repo.update(recipe, kind: ChangeKind.manual);
    }
    if (!mounted) return;
    setState(() => _dirty = false);
    context.go('/recipes/${recipe.id}');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Recept je sačuvan.')));
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Odbaciti izmene?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Nastavi uređivanje'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Odbaci'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    setState(() => _dirty = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.id != null;
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(editing ? 'Izmeni recept' : 'Novi recept'),
          actions: [
            TextButton(
              onPressed: _loading || _saving ? null : _save,
              child: const Text('Sačuvaj'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : editing && _original == null
            ? const Center(child: Text('Recept više ne postoji.'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _title,
                            onChanged: (_) => _changed(),
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText: 'Naziv',
                              errorText: _titleError,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: 160,
                                child: TextField(
                                  controller: _servings,
                                  onChanged: (_) => _changed(),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    labelText: 'Broj porcija',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 200,
                                child: TextField(
                                  controller: _prep,
                                  onChanged: (_) => _changed(),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    labelText: 'Vreme pripreme (min)',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 200,
                                child: TextField(
                                  controller: _active,
                                  onChanged: (_) => _changed(),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    labelText: 'Aktivno vreme (min)',
                                    helperText: 'Koliko radiš',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 200,
                                child: TextField(
                                  controller: _total,
                                  onChanged: (_) => _changed(),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    labelText: 'Ukupno vreme (min)',
                                    helperText: 'Od početka do stola',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_timingError case final error?)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                error,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          const SizedBox(height: 20),
                          Text('Sastojci', style: theme.textTheme.titleMedium),
                          for (final (n, i) in _ingredients.indexed)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(ingredientLine(i)),
                              subtitle: Text(i.category),
                              onTap: () => _editIngredient(n),
                              trailing: IconButton(
                                tooltip: 'Ukloni sastojak',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => setState(() {
                                  _ingredients = [..._ingredients]..removeAt(n);
                                  _dirty = true;
                                }),
                              ),
                            ),
                          if (_ingredientsError case final error?)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                error,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _editIngredient,
                              icon: const Icon(Icons.add),
                              label: const Text('Dodaj sastojak'),
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _steps,
                            onChanged: (_) => _changed(),
                            minLines: 4,
                            maxLines: null,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Koraci pripreme (jedan po redu)',
                              alignLabelWithHint: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _IngredientDialog extends StatefulWidget {
  const _IngredientDialog({this.initial});

  final Ingredient? initial;

  @override
  State<_IngredientDialog> createState() => _IngredientDialogState();
}

class _IngredientDialogState extends State<_IngredientDialog> {
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _quantity = TextEditingController(
    text: widget.initial?.quantity == null
        ? ''
        : formatQuantity(widget.initial!.quantity!),
  );
  late final _unit = TextEditingController(text: widget.initial?.unit);
  late final _note = TextEditingController(text: widget.initial?.note);
  late String _category = widget.initial?.category ?? 'ostalo';

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _unit.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) return;
    // Isto čitanje kao za AI odgovor: "0,5", "1/2", prazno → bez količine.
    Navigator.of(context).pop(
      Ingredient.fromJson({
        'name': _name.text,
        'quantity': _quantity.text,
        'unit': _unit.text,
        'category': _category,
        'note': _note.text,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sastojak'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Naziv'),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Količina'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(labelText: 'Jedinica'),
                  ),
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Kategorija'),
              items: [
                for (final c in ingredientCategories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (c) => setState(() => _category = c ?? 'ostalo'),
            ),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Napomena'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Otkaži'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : _submit,
          child: const Text('Sačuvaj'),
        ),
      ],
    );
  }
}
