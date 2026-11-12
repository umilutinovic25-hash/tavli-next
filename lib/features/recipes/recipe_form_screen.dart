import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/food.dart';
import '../../domain/ids.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_format.dart';
import '../../domain/recipe_version.dart';
import '../../domain/shopping_sync.dart' show ingredientKey;
import '../../domain/step_links.dart';
import '../../domain/time_budget.dart';
import '../../providers.dart';
import '../foods/allergen_line.dart';
import '../foods/food_chip.dart';
import '../foods/food_picker.dart';
import 'recipe_providers.dart';
import 'recipe_view.dart' show StepUseLine;

/// Isti editor za ručni unos i ispravku otvorenog foto-pregleda.
Future<Ingredient?> showRecipeIngredientEditor(
  BuildContext context, {
  Ingredient? initial,
  bool validateQuantity = false,
}) => showDialog<Ingredient>(
  context: context,
  builder: (_) =>
      _IngredientDialog(initial: initial, validateQuantity: validateQuantity),
);

/// Ručni unos novog recepta ([id] == null) ili izmena postojećeg.
class RecipeFormScreen extends ConsumerStatefulWidget {
  const RecipeFormScreen({super.key, this.id, this.draft});

  final String? id;
  final Recipe? draft;

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

  /// Koraci iz polja i njihove veze; veze prate tekst koraka.
  List<String> _stepTexts = [];
  List<List<StepUse>> _uses = [];
  Recipe? _original;
  bool _loading = false;
  bool _dirty = false;
  bool _saving = false;
  String? _titleError;
  String? _ingredientsError;

  /// AI predlozi koje je osoba odbacila (id ili naziv sastojka); samo prikaz.
  final _dismissed = <String>{};

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft != null) {
      _fill(draft);
    }
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
        _fill(recipe);
      }
    });
  }

  void _fill(Recipe recipe) {
    _title.text = recipe.title;
    _servings.text = '${recipe.servings}';
    _prep.text = recipe.prepMinutes?.toString() ?? '';
    _active.text = recipe.activeMinutes?.toString() ?? '';
    _total.text = recipe.totalMinutes?.toString() ?? '';
    _steps.text = recipe.steps.join('\n');
    _ingredients = [...recipe.ingredients];
    _stepTexts = recipe.steps;
    _uses = [for (var i = 0; i < recipe.steps.length; i++) recipe.usesFor(i)];
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

  List<String> _parseSteps() => [
    for (final line in _steps.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  void _stepsChanged() {
    final next = _parseSteps();
    setState(() {
      _uses = realignStepUses(_stepTexts, _uses, next);
      _stepTexts = next;
      _dirty = true;
    });
  }

  Future<void> _editUses(int step) async {
    // Sastojak dobija stalni id tek kad zatreba za vezu.
    setState(() => _ingredients = withIngredientIds(_ingredients, newId));
    final result = await showDialog<List<StepUse>>(
      context: context,
      builder: (context) => _StepUsesDialog(
        step: _stepTexts[step],
        ingredients: _ingredients,
        initial: _uses[step],
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _uses = [..._uses]..[step] = result;
      _dirty = true;
    });
  }

  Future<void> _removeIngredient(int index) async {
    final ingredient = _ingredients[index];
    final usedIn = _uses
        .where((u) => u.any((x) => x.ingredientId == ingredient.id))
        .length;
    if (ingredient.id != null && usedIn > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Ukloniti „${ingredient.name}“?'),
          content: Text(
            'Koristi se u ${usedIn == 1 ? '1 koraku' : '$usedIn koraka'}. '
            'Te veze ostaju označene kao „Sastojak više nije u receptu“ '
            'dok ih ne izmeniš.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Otkaži'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ukloni'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _ingredients = [..._ingredients]..removeAt(index);
      _dirty = true;
    });
  }

  Future<void> _editIngredient([int? index]) async {
    final result = await showRecipeIngredientEditor(
      context,
      initial: index == null ? null : _ingredients[index],
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _ingredients = [..._ingredients, result.withId(newId())];
      } else {
        // Izmena zadržava id, pa veze sa koracima ostaju.
        final id = _ingredients[index].id;
        _ingredients = [..._ingredients]
          ..[index] = id == null ? result : result.withId(id);
      }
      _dirty = true;
      _ingredientsError = null;
    });
  }

  /// Predlog nove namirnice samo za uvezen recept (AI, fotografija, link) i
  /// samo za sastojak koji ni katalog ne prepoznaje.
  bool _suggests(Ingredient i, FoodCatalog? catalog) {
    final source = widget.draft?.source ?? _original?.source;
    if (source == null || source == RecipeSource.manual) return false;
    if (catalog == null || _dismissed.contains(i.id ?? i.name)) return false;
    return catalog.match(i.name) == null && suggestFood(i) != null;
  }

  Future<void> _confirmSuggestion(int index) async {
    final i = _ingredients[index];
    final id = await createFood(
      context,
      text: i.name,
      category: i.category,
      unit: i.unit,
    );
    if (id == null || !mounted) return;
    final category = ref.read(foodCatalogProvider).value?.byId(id)?.category;
    setState(() {
      _ingredients = [..._ingredients]
        ..[index] = Ingredient.fromJson({
          ...i.toJson(),
          'foodId': id,
          if (category != null && ingredientCategories.contains(category))
            'category': category,
        });
      _dirty = true;
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
    final steps = _parseSteps();
    final stepUses = realignStepUses(_stepTexts, _uses, steps);
    final repo = ref.read(recipeRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final original = _original;
    final Recipe recipe;
    setState(() => _saving = true);
    if (original == null) {
      final now = ref.read(clockProvider)();
      recipe =
          (widget.draft ??
                  Recipe(
                    id: newId(),
                    title: title,
                    servings: servings,
                    prepMinutes: prep,
                    ingredients: _ingredients,
                    steps: steps,
                    stepUses: stepUses,
                    source: RecipeSource.manual,
                    createdAt: now,
                    activeMinutes: active,
                    totalMinutes: total,
                  ))
              .copyWith(
                title: title,
                servings: servings,
                prepMinutes: prep,
                clearPrepMinutes: prep == null,
                ingredients: _ingredients,
                steps: steps,
                stepUses: stepUses,
                clearTiming: true,
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
        stepUses: stepUses,
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
    final catalog = ref.watch(foodCatalogProvider).value;
    final editing = widget.id != null;
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            editing
                ? 'Izmeni recept'
                : widget.draft != null
                ? 'Pregled uvoza'
                : 'Novi recept',
          ),
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
                          if (widget.draft case final draft?) ...[
                            const Text(
                              'Proveri uvezene sastojke i porcije pre čuvanja. Količine su u tekstu sastojaka; razdvoji ih za nabavku. Ako porcije nisu prepoznate, postavljene su na 2.',
                            ),
                            const SizedBox(height: 8),
                            SelectableText('Izvor: ${draft.sourceUrl}'),
                            IngredientsAllergenWarning(_ingredients),
                            const SizedBox(height: 16),
                          ],
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
                          for (final (n, i) in _ingredients.indexed) ...[
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(ingredientLine(i)),
                              subtitle: Text(
                                i.foodId == null
                                    ? '${i.category} · Nepotvrđeno'
                                    : i.category,
                              ),
                              onTap: () => _editIngredient(n),
                              trailing: IconButton(
                                tooltip: 'Ukloni sastojak',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _removeIngredient(n),
                              ),
                            ),
                            if (_suggests(i, catalog))
                              _FoodSuggestion(
                                name: i.name,
                                onConfirm: () => _confirmSuggestion(n),
                                onDismiss: () => setState(
                                  () => _dismissed.add(i.id ?? i.name),
                                ),
                              ),
                          ],
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
                            onChanged: (_) => _stepsChanged(),
                            minLines: 4,
                            maxLines: null,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Koraci pripreme (jedan po redu)',
                              alignLabelWithHint: true,
                            ),
                          ),
                          if (_stepTexts.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Text(
                              'Sastojci po koracima',
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              'Poveži sastojke sa korakom u kome se koriste.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            for (final (n, step) in _stepTexts.indexed)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${n + 1}. $step',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle:
                                    n < _uses.length && _uses[n].isNotEmpty
                                    ? Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          for (final u in _uses[n])
                                            StepUseLine(u, _ingredients),
                                        ],
                                      )
                                    : null,
                                trailing: TextButton(
                                  onPressed: _ingredients.isEmpty
                                      ? null
                                      : () => _editUses(n),
                                  child: Text(
                                    'Poveži',
                                    semanticsLabel:
                                        'Poveži sastojke sa korakom ${n + 1}',
                                  ),
                                ),
                              ),
                            for (final c in useConflicts(_ingredients, _uses))
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '„${c.ingredient.name}“: koraci koriste '
                                  '${formatQuantity(c.usedQuantity)}, a recept '
                                  'ima ${formatQuantity(c.ingredient.quantity!)}.',
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                          ],
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

/// AI (ili uvoz) je doneo sastojak koji katalog ne zna. Ništa se ne upisuje
/// dok osoba ne potvrdi formu nove namirnice.
class _FoodSuggestion extends StatelessWidget {
  const _FoodSuggestion({
    required this.name,
    required this.onConfirm,
    required this.onDismiss,
  });

  final String name;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Card.outlined(
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('AI predlaže novu namirnicu: „$name“.'),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(onPressed: onDismiss, child: const Text('Odbaci')),
              FilledButton.tonal(
                onPressed: onConfirm,
                child: const Text('Potvrdi'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _IngredientDialog extends ConsumerStatefulWidget {
  const _IngredientDialog({this.initial, this.validateQuantity = false});

  final Ingredient? initial;
  final bool validateQuantity;

  @override
  ConsumerState<_IngredientDialog> createState() => _IngredientDialogState();
}

class _IngredientDialogState extends ConsumerState<_IngredientDialog> {
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _quantity = TextEditingController(
    text: widget.initial?.quantity == null
        ? ''
        : formatQuantity(
            widget.initial!.quantity!,
            preservePrecision: widget.validateQuantity,
          ),
  );
  late final _unit = TextEditingController(text: widget.initial?.unit);
  late final _note = TextEditingController(text: widget.initial?.note);
  late String _category = widget.initial?.category ?? 'ostalo';
  late String? _foodId = widget.initial?.foodId;

  /// Naziv za koji važi [_foodId]; drugi naziv je druga stvar.
  late String _foodFor = widget.initial?.name ?? '';
  String? _quantityError;

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
    final ingredient = Ingredient.fromJson({
      'name': _name.text,
      'quantity': _quantity.text,
      'unit': _unit.text,
      'category': _category,
      'note': _note.text,
      'foodId': _food(ref.read(foodCatalogProvider).value),
    });
    final q = ingredient.quantity;
    if (widget.validateQuantity &&
        _quantity.text.trim().isNotEmpty &&
        (q == null || !q.isFinite || q <= 0)) {
      setState(
        () => _quantityError =
            'Unesi pozitivan broj ili ostavi prazno ako količina nije poznata.',
      );
      return;
    }
    Navigator.of(context).pop(ingredient);
  }

  /// Izbor osobe, inače tačan alias iz kataloga (isto pravilo kao pri
  /// čuvanju u repozitorijumu), pa se namirnica vidi odmah dok se kuca.
  String? _food(FoodCatalog? catalog) =>
      (ingredientKey(_name.text) == ingredientKey(_foodFor) ? _foodId : null) ??
      catalog?.match(_name.text);

  /// Izbor namirnice upisuje samo `foodId`; tekst ostaje kako je upisan, a
  /// kategorija se preuzima iz namirnice (osoba je može promeniti).
  Future<void> _pickFood() async {
    final id = await pickFood(
      context,
      text: _name.text,
      category: _category,
      unit: _unit.text,
    );
    if (id == null || !mounted) return;
    final catalog = ref.read(foodCatalogProvider).value;
    final category = catalog?.byId(id)?.category;
    setState(() {
      _foodId = id;
      _foodFor = _name.text;
      if (category != null && ingredientCategories.contains(category)) {
        _category = category;
      }
    });
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
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FoodChip(
                foodId: _food(ref.watch(foodCatalogProvider).value),
                onPressed: _name.text.trim().isEmpty ? null : _pickFood,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Količina',
                      errorText: _quantityError,
                      errorMaxLines: 5,
                    ),
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
              // Novi izbor namirnice postavlja njenu kategoriju.
              key: ValueKey(_foodId),
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

/// Sastojci koji se koriste u jednom koraku, uz opcionu količinu.
class _StepUsesDialog extends StatefulWidget {
  const _StepUsesDialog({
    required this.step,
    required this.ingredients,
    required this.initial,
  });

  final String step;
  final List<Ingredient> ingredients;
  final List<StepUse> initial;

  @override
  State<_StepUsesDialog> createState() => _StepUsesDialogState();
}

class _StepUsesDialogState extends State<_StepUsesDialog> {
  late final Set<String> _checked = {
    for (final u in widget.initial) u.ingredientId,
  };
  late final Map<String, TextEditingController> _quantity = {
    for (final id in [for (final i in widget.ingredients) ?i.id])
      id: TextEditingController(
        text: switch (_initialFor(id)?.quantity) {
          final q? => formatQuantity(q),
          null => '',
        },
      ),
  };

  /// Veze na sastojke kojih više nema; ostaju dok ih osoba ne isključi.
  late final List<StepUse> _unresolved = [
    for (final u in widget.initial)
      if (isUnresolved(u, widget.ingredients)) u,
  ];

  StepUse? _initialFor(String id) {
    for (final u in widget.initial) {
      if (u.ingredientId == id) return u;
    }
    return null;
  }

  @override
  void dispose() {
    for (final c in _quantity.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<StepUse> _result() => [
    for (final i in widget.ingredients)
      if (i.id case final id? when _checked.contains(id))
        StepUse(
          ingredientId: id,
          quantity: Ingredient.fromJson({
            'name': i.name,
            'quantity': _quantity[id]!.text,
          }).quantity,
          unit: _initialFor(id)?.unit,
        ),
    for (final u in _unresolved)
      if (_checked.contains(u.ingredientId)) u,
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sastojci u koraku'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.step),
            const SizedBox(height: 8),
            for (final i in widget.ingredients)
              if (i.id case final id?) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _checked.contains(id),
                  title: Text(ingredientLine(i)),
                  onChanged: (v) => setState(
                    () => v == true ? _checked.add(id) : _checked.remove(id),
                  ),
                ),
                if (_checked.contains(id))
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 8),
                    child: TextField(
                      controller: _quantity[id],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Količina u ovom koraku (nije obavezno)',
                        suffixText: _initialFor(id)?.unit ?? i.unit,
                      ),
                    ),
                  ),
              ],
            for (final u in _unresolved)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _checked.contains(u.ingredientId),
                title: const Text('Sastojak više nije u receptu'),
                onChanged: (v) => setState(
                  () => v == true
                      ? _checked.add(u.ingredientId)
                      : _checked.remove(u.ingredientId),
                ),
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
          onPressed: () => Navigator.of(context).pop(_result()),
          child: const Text('Sačuvaj'),
        ),
      ],
    );
  }
}
