import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/food.dart';
import '../../domain/recipe.dart';
import '../../providers.dart';
import 'new_food_form.dart';

/// Od ove širine izbor je dijalog, ispod je donji list (kao traka tabova).
const foodPickerWideWidth = 720.0;

/// Izbor namirnice za red sa tekstom [text]: pretraga kataloga ili nova
/// sopstvena namirnica. Vraća id namirnice ili null kad osoba odustane.
Future<String?> pickFood(
  BuildContext context, {
  required String text,
  String category = 'ostalo',
  String? unit,
}) => _showAdaptive(
  context,
  FoodPickerSheet(text: text, category: category, unit: unit),
);

/// Odmah otvara popunjenu formu nove namirnice (npr. za AI predlog). Vraća id
/// nove sopstvene namirnice ili null kad osoba odustane.
Future<String?> createFood(
  BuildContext context, {
  required String text,
  String category = 'ostalo',
  String? unit,
}) => _showAdaptive(
  context,
  Builder(
    builder: (context) => NewFoodForm(
      text: text,
      initial: _draftFor(text, category, unit),
      onSaved: (id) => Navigator.of(context).pop(id),
      onCancel: () => Navigator.of(context).pop(),
    ),
  ),
);

FoodDraft _draftFor(String text, String category, String? unit) =>
    suggestFood(Ingredient(name: text, unit: unit, category: category)) ??
    FoodDraft(name: '', category: category, baseUnit: null);

Future<String?> _showAdaptive(BuildContext context, Widget child) {
  if (MediaQuery.sizeOf(context).width >= foodPickerWideWidth) {
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
          child: child,
        ),
      ),
    );
  }
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) =>
        FractionallySizedBox(heightFactor: 0.85, child: child),
  );
}

class FoodPickerSheet extends ConsumerStatefulWidget {
  const FoodPickerSheet({
    required this.text,
    this.category = 'ostalo',
    this.unit,
    super.key,
  });

  /// Upisani tekst reda; predlog za novu namirnicu i njen alias.
  final String text;
  final String category;
  final String? unit;

  @override
  ConsumerState<FoodPickerSheet> createState() => _FoodPickerSheetState();
}

class _FoodPickerSheetState extends ConsumerState<FoodPickerSheet> {
  var _query = '';
  var _creating = false;

  @override
  Widget build(BuildContext context) {
    if (_creating) {
      return NewFoodForm(
        text: widget.text,
        initial: _draftFor(widget.text, widget.category, widget.unit),
        onSaved: (id) => Navigator.of(context).pop(id),
        onCancel: () => setState(() => _creating = false),
      );
    }
    final catalog = ref.watch(foodCatalogProvider).value ?? FoodCatalog.empty;
    final results = catalog.search(_query);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Izaberi namirnicu',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Pretraži namirnice',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, i) {
                final f = results[i];
                return ListTile(
                  title: Text(f.name),
                  subtitle: Text(f.category),
                  onTap: () => Navigator.of(context).pop(f.id),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Nova namirnica'),
            onPressed: () => setState(() => _creating = true),
          ),
        ],
      ),
    );
  }
}
