import 'package:flutter/material.dart';

import '../../domain/shopping_demand.dart';

/// Privremen izbor naziva; nikad ne predstavlja potvrdu zalihe.
class QuickIngredientsInput extends StatefulWidget {
  const QuickIngredientsInput({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  @override
  State<QuickIngredientsInput> createState() => _QuickIngredientsInputState();
}

class _QuickIngredientsInputState extends State<QuickIngredientsInput> {
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _add() {
    if (widget.selected.length >= 3) return;
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      setState(() => _error = 'Unesi naziv namirnice.');
      return;
    }
    if (name.length > 80) {
      setState(() => _error = 'Naziv može imati najviše 80 znakova.');
      return;
    }
    final key = dictionaryIngredientKey(name, 1);
    if (widget.selected.any((n) => dictionaryIngredientKey(n, 1) == key)) {
      setState(() => _error = 'Ova namirnica je već izabrana.');
      return;
    }
    setState(() {
      _name.clear();
      _error = null;
    });
    widget.onChanged([...widget.selected, name]);
  }

  void _remove(String name) {
    setState(() => _error = null);
    widget.onChanged([
      for (final n in widget.selected)
        if (n != name) n,
    ]);
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('Potroši ove 3 namirnice'),
    subtitle: widget.selected.isEmpty ? null : Text(widget.selected.join(', ')),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 16),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Izaberi do 3 namirnice. Naziv ne potvrđuje količinu; računamo samo potvrđenu zalihu iz Ostave.',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final name in widget.selected)
            InputChip(
              label: Text(name),
              deleteButtonTooltipMessage: 'Ukloni $name',
              onDeleted: () => _remove(name),
            ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('quick-ingredient-name'),
        controller: _name,
        enabled: widget.selected.length < 3,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: 'Namirnica',
          helperText: 'Najviše 3 namirnice',
          errorText: _error,
          errorMaxLines: 3,
        ),
        onSubmitted: (_) => _add(),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: widget.selected.length < 3 ? _add : null,
            icon: const Icon(Icons.add),
            label: const Text('Dodaj u izbor'),
          ),
          if (widget.selected.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => _error = null);
                widget.onChanged(const []);
              },
              child: const Text('Obriši izbor'),
            ),
        ],
      ),
    ],
  );
}
