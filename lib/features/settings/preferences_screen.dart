import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/user_preferences.dart';
import '../../providers.dart';
import '../recipes/recipe_view.dart' show ReadableScroll;

/// Profil → Preferencije: ishrana, namirnice koje ne volimo, alergije i broj
/// osoba. Svaka izmena se odmah čuva, a AI ih dobija uz predloge recepata i
/// plana.
class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider).value;
    if (prefs == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Preferencije')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);

    Future<void> save(UserPreferences next) async {
      try {
        await ref.read(preferencesRepositoryProvider).save(next);
      } on Object {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Preferencije nisu sačuvane. Pokušaj ponovo.'),
            ),
          );
      }
    }

    const gap = SizedBox(height: 24);
    return Scaffold(
      appBar: AppBar(title: const Text('Preferencije')),
      body: ReadableScroll(
        children: [
          Text(
            'Koriste se u predlozima recepata i plana. AI ih dobija uz svaki '
            'predlog.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          gap,
          Text('Ishrana', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final diet in FoodDiet.values)
                FilterChip(
                  label: Text(diet.label),
                  selected: prefs.diet.contains(diet),
                  onSelected: (on) => unawaited(
                    save(
                      prefs.copyWith(
                        diet: on
                            ? {...prefs.diet, diet}
                            : prefs.diet.difference({diet}),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          gap,
          _ItemsEditor(
            title: 'Ne volim',
            note: 'AI ih izbegava kad može.',
            field: 'Dodaj namirnicu',
            addTooltip: 'Dodaj namirnicu',
            items: prefs.dislikes,
            onChanged: (items) =>
                unawaited(save(prefs.copyWith(dislikes: items))),
          ),
          gap,
          _ItemsEditor(
            title: 'Alergije',
            note: 'AI ih nikad ne koristi, ni u jednom sastojku.',
            field: 'Dodaj alergiju',
            addTooltip: 'Dodaj alergiju',
            items: prefs.allergies,
            onChanged: (items) =>
                unawaited(save(prefs.copyWith(allergies: items))),
          ),
          gap,
          Text('Broj osoba', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Koliko članova domaćinstva jede.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Manje osoba',
                icon: const Icon(Icons.remove),
                onPressed: prefs.servings > minHouseholdServings
                    ? () => unawaited(
                        save(prefs.copyWith(servings: prefs.servings - 1)),
                      )
                    : null,
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${prefs.servings}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Više osoba',
                icon: const Icon(Icons.add),
                onPressed: prefs.servings < maxHouseholdServings
                    ? () => unawaited(
                        save(prefs.copyWith(servings: prefs.servings + 1)),
                      )
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lista stavki sa poljem za unos; stavke se brišu sa čipa.
class _ItemsEditor extends StatefulWidget {
  const _ItemsEditor({
    required this.title,
    required this.note,
    required this.field,
    required this.addTooltip,
    required this.items,
    required this.onChanged,
  });

  final String title;
  final String note;
  final String field;
  final String addTooltip;
  final List<String> items;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_ItemsEditor> createState() => _ItemsEditorState();
}

class _ItemsEditorState extends State<_ItemsEditor> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final value = text.toLowerCase();
    if (value.length > maxPreferenceItemLength) {
      setState(() => _error = 'Najviše $maxPreferenceItemLength znakova.');
      return;
    }
    if (widget.items.length >= maxPreferenceItems &&
        !widget.items.contains(value)) {
      setState(() => _error = 'Najviše $maxPreferenceItems stavki.');
      return;
    }
    _controller.clear();
    setState(() => _error = null);
    widget.onChanged(normalizeItems([...widget.items, value]));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          widget.note,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  labelText: widget.field,
                  errorText: _error,
                ),
              ),
            ),
            IconButton(
              tooltip: widget.addTooltip,
              icon: const Icon(Icons.add),
              onPressed: _add,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.items.isEmpty)
          Text(
            'Nema stavki.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in widget.items)
                InputChip(
                  label: Text(item),
                  onDeleted: () =>
                      widget.onChanged([...widget.items]..remove(item)),
                ),
            ],
          ),
      ],
    );
  }
}
