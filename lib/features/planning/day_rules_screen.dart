import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/day_rules.dart';
import '../../domain/meal_plan.dart';
import '../recipes/recipe_view.dart' show ReadableScroll;
import 'planning_providers.dart';

/// Pravila po danima domaćinstva: dodavanje i brisanje.
class DayRulesScreen extends ConsumerWidget {
  const DayRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(dayRulesProvider).value ?? const [];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pravila po danima')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Dodaj pravilo'),
      ),
      body: ReadableScroll(
        children: [
          Text(
            'Npr. ponedeljak bez mesa ili petak riba. Predlog plana poštuje '
            'obavezna pravila; jelo koje ih krši čuva se samo uz izuzetak za '
            'taj obrok.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (rules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Još nema pravila.'),
            ),
          for (final r in rules)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(r.label),
              subtitle: Text(
                r.mode == RuleMode.required ? 'Obavezno' : 'Želja',
              ),
              trailing: IconButton(
                tooltip: 'Obriši pravilo „${r.label}“',
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    ref.read(dayRuleRepositoryProvider).remove(r.id),
              ),
            ),
          const SizedBox(height: 72),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_RuleDraft>(
      context: context,
      builder: (context) => const _RuleDialog(),
    );
    if (draft == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(dayRuleRepositoryProvider)
          .add(
            weekday: draft.weekday,
            kind: draft.kind,
            mealType: draft.mealType,
            value: draft.value,
            mode: draft.mode,
          );
    } on Object {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Pravilo nije sačuvano. Pokušaj ponovo.'),
          ),
        );
    }
  }
}

typedef _RuleDraft = ({
  int weekday,
  MealType? mealType,
  RuleKind kind,
  String? value,
  RuleMode mode,
});

class _RuleDialog extends StatefulWidget {
  const _RuleDialog();

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  int _weekday = 1;
  MealType? _mealType;
  RuleKind _kind = RuleKind.noMeat;
  RuleMode _mode = RuleMode.required;
  final _value = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _save() {
    final value = _value.text.trim();
    if (_kind.needsValue &&
        (value.isEmpty || value.length > maxRuleValueLength)) {
      setState(() => _error = 'Upiši naziv sastojka (do 40 znakova).');
      return;
    }
    Navigator.of(context).pop((
      weekday: _weekday,
      mealType: _mealType,
      kind: _kind,
      value: _kind.needsValue ? value : null,
      mode: _mode,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo pravilo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _weekday,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Dan'),
              items: [
                for (var d = 1; d <= 7; d++)
                  DropdownMenuItem(value: d, child: Text(weekdayNames[d - 1])),
              ],
              onChanged: (d) => setState(() => _weekday = d ?? _weekday),
            ),
            DropdownButtonFormField<MealType?>(
              initialValue: _mealType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Obrok'),
              items: [
                const DropdownMenuItem(child: Text('Svi obroci')),
                for (final t in MealType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) => setState(() => _mealType = t),
            ),
            DropdownButtonFormField<RuleKind>(
              initialValue: _kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Pravilo'),
              items: [
                for (final k in RuleKind.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (k) => setState(() {
                _kind = k ?? _kind;
                _error = null;
              }),
            ),
            if (_kind.needsValue)
              TextField(
                controller: _value,
                maxLength: maxRuleValueLength,
                decoration: InputDecoration(
                  labelText: 'Sastojak',
                  errorText: _error,
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Obavezno'),
              subtitle: const Text('Isključeno: samo želja'),
              value: _mode == RuleMode.required,
              onChanged: (v) => setState(
                () => _mode = v ? RuleMode.required : RuleMode.preferred,
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
        FilledButton(onPressed: _save, child: const Text('Sačuvaj')),
      ],
    );
  }
}
