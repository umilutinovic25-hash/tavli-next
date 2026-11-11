import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/food_repository.dart';
import '../../domain/food.dart';
import '../../domain/recipe.dart';
import '../../providers.dart';

/// Nova sopstvena namirnica domaćinstva. Upisani tekst reda ([text]) postaje
/// njen alias, pa se red i ubuduće prepoznaje. Ništa se ne upisuje dok
/// osoba ne sačuva.
class NewFoodForm extends ConsumerStatefulWidget {
  const NewFoodForm({
    required this.text,
    required this.initial,
    required this.onSaved,
    this.onCancel,
    super.key,
  });

  final String text;
  final FoodDraft initial;
  final ValueChanged<String> onSaved;
  final VoidCallback? onCancel;

  @override
  ConsumerState<NewFoodForm> createState() => _NewFoodFormState();
}

class _NewFoodFormState extends ConsumerState<NewFoodForm> {
  late final _name = TextEditingController(text: widget.text.trim());
  late var _category = ingredientCategories.contains(widget.initial.category)
      ? widget.initial.category
      : 'ostalo';
  late var _unit = BaseUnit.values.asNameMap()[widget.initial.baseUnit];
  final _allergens = <String>{};
  String? _error;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _ready => !_saving && _unit != null && _name.text.trim().isNotEmpty;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = FoodDraft(
        name: _name.text,
        category: _category,
        baseUnit: _unit?.name,
      ).validate();
      // Tekst reda postaje alias samo ako ga katalog već ne zna (red koji je
      // prepoznat a osoba ipak pravi novu namirnicu zadržava zajednički).
      final repo = ref.read(foodRepositoryProvider);
      final known = (await repo.catalog()).match(widget.text);
      final id = await repo.createOwn(
        draft,
        aliases: [if (known == null) widget.text],
        allergens: {..._allergens},
      );
      if (mounted) widget.onSaved(id);
    } on FoodAliasTakenException {
      if (mounted) {
        setState(() => _error = 'Ova namirnica već postoji u katalogu.');
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nova namirnica', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: FoodDraft.maxNameLength,
            decoration: const InputDecoration(labelText: 'Naziv namirnice'),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Kategorija'),
            items: [
              for (final c in ingredientCategories)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: 16),
          Text(
            'Osnovna jedinica',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          SegmentedButton<BaseUnit>(
            emptySelectionAllowed: true,
            segments: [
              for (final u in BaseUnit.values)
                ButtonSegment(value: u, label: Text(u.name)),
            ],
            selected: {?_unit},
            onSelectionChanged: (s) =>
                setState(() => _unit = s.isEmpty ? null : s.first),
          ),
          const SizedBox(height: 16),
          Text('Alergeni', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          // Samo fiksna EU lista; slobodan unos nije moguć.
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final MapEntry(:key, :value) in euAllergens.entries)
                FilterChip(
                  label: Text(value),
                  selected: _allergens.contains(key),
                  onSelected: _saving
                      ? null
                      : (on) => setState(
                          () =>
                              on ? _allergens.add(key) : _allergens.remove(key),
                        ),
                ),
            ],
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 12),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _ready ? _save : null,
            child: const Text('Sačuvaj kao moju namirnicu'),
          ),
          if (widget.onCancel case final cancel?)
            TextButton(onPressed: cancel, child: const Text('Nazad')),
        ],
      ),
    );
  }
}
