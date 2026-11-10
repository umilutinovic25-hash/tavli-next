import 'package:flutter/material.dart';

import '../../domain/pan_converter.dart';
import '../../domain/recipe.dart';

class PanConverterDialog extends StatefulWidget {
  const PanConverterDialog({super.key, required this.recipe});
  final Recipe recipe;
  @override
  State<PanConverterDialog> createState() => _PanConverterDialogState();
}

class _PanConverterDialogState extends State<PanConverterDialog> {
  final _form = GlobalKey<FormState>();
  final _oldWidth = TextEditingController();
  final _oldLength = TextEditingController();
  final _oldHeight = TextEditingController();
  final _newWidth = TextEditingController();
  final _newLength = TextEditingController();
  final _newHeight = TextEditingController();
  PanShape _oldShape = PanShape.round;
  PanShape _newShape = PanShape.round;
  double? _factor;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _oldWidth,
      _oldLength,
      _oldHeight,
      _newWidth,
      _newLength,
      _newHeight,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _display(double value) =>
      double.parse(value.toStringAsPrecision(6))
          .toString()
          .replaceFirst(RegExp(r'\.0$'), '')
          .replaceAll('.', ',');

  String _ingredientLine(Ingredient ingredient, double factor) {
    final quantity = ingredient.quantity;
    final line = quantity == null
        ? '${ingredient.name} — količina nije navedena'
        : '${_display(quantity * factor)} ${ingredient.unit ?? ''} ${ingredient.name}'
              .trim();
    final note = ingredient.note?.trim();
    return note == null || note.isEmpty ? line : '$line ($note)';
  }

  double? _number(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
  void _calculate() {
    if (!_form.currentState!.validate()) return;
    try {
      final factor = panScale(
        BakingPan(
          shape: _oldShape,
          width: _number(_oldWidth.text)!,
          height: _number(_oldHeight.text)!,
          length: _number(_oldLength.text),
        ),
        BakingPan(
          shape: _newShape,
          width: _number(_newWidth.text)!,
          height: _number(_newHeight.text)!,
          length: _number(_newLength.text),
        ),
      );
      if (widget.recipe.ingredients.any(
        (i) => i.quantity != null && !(i.quantity! * factor).isFinite,
      )) {
        throw const FormatException('Neispravna količina');
      }
      setState(() {
        _factor = factor;
        _error = null;
      });
    } on FormatException {
      setState(() {
        _factor = null;
        _error = 'Proračun nije moguć za ove vrednosti.';
      });
    }
  }

  Widget _dimension(
    String label,
    TextEditingController controller,
    String key,
  ) => TextFormField(
    key: ValueKey(key),
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, suffixText: 'cm'),
    onChanged: (_) => setState(() {
      _factor = null;
      _error = null;
    }),
    validator: (text) {
      final n = _number(text ?? '');
      return n == null || !n.isFinite || n <= 0
          ? 'Unesi broj veći od nule.'
          : null;
    },
  );

  Widget _pan(String title, bool original) {
    final shape = original ? _oldShape : _newShape;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        DropdownButtonFormField<PanShape>(
          isExpanded: true,
          selectedItemBuilder: (_) => [
            for (final label in ['Okrugli', 'Pravougaoni'])
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          initialValue: shape,
          decoration: const InputDecoration(labelText: 'Oblik kalupa'),
          items: const [
            DropdownMenuItem(value: PanShape.round, child: Text('Okrugli')),
            DropdownMenuItem(
              value: PanShape.rectangular,
              child: Text('Pravougaoni'),
            ),
          ],
          onChanged: (value) => setState(() {
            if (original) {
              _oldShape = value!;
            } else {
              _newShape = value!;
            }
            _factor = null;
            _error = null;
          }),
        ),
        _dimension(
          shape == PanShape.round ? 'Prečnik' : 'Širina',
          original ? _oldWidth : _newWidth,
          original ? 'old-width' : 'new-width',
        ),
        if (shape == PanShape.rectangular)
          _dimension(
            'Dužina',
            original ? _oldLength : _newLength,
            original ? 'old-length' : 'new-length',
          ),
        _dimension(
          'Visina testa',
          original ? _oldHeight : _newHeight,
          original ? 'old-height' : 'new-height',
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Preračunaj kalup'),
    content: SizedBox(
      width: 560,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Za kalupe ravnih stranica. Vreme i temperatura pečenja se ne menjaju automatski.',
              ),
              const SizedBox(height: 16),
              _pan('Početni kalup', true),
              _pan('Novi kalup', false),
              FilledButton(
                onPressed: _calculate,
                child: const Text('Izračunaj'),
              ),
              if (_error case final error?)
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_factor case final factor?) ...[
                const SizedBox(height: 16),
                Text(
                  'Faktor: ${_display(factor)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Preračunati sastojci (zaokruženo na šest značajnih cifara)',
                ),
                for (final i in widget.recipe.ingredients)
                  Text(_ingredientLine(i, factor)),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Zatvori'),
      ),
    ],
  );
}
