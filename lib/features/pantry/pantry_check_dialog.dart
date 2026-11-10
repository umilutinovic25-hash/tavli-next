import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/pantry_repository.dart';
import 'pantry_fields.dart';
import 'pantry_item_tile.dart';

class PantryCheckDialog extends StatefulWidget {
  const PantryCheckDialog({
    super.key,
    required this.item,
    required this.repository,
  });
  final PantryItemRow item;
  final PantryRepository repository;
  @override
  State<PantryCheckDialog> createState() => _PantryCheckDialogState();
}

class _PantryCheckDialogState extends State<PantryCheckDialog> {
  final _form = GlobalKey<FormState>();
  late final _quantity = TextEditingController(
    text: widget.item.quantity == null
        ? ''
        : pantryAmount(widget.item.quantity!),
  );
  late final _unit = TextEditingController(text: widget.item.unit);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.checkQuantity(
        widget.item.id,
        quantity: parsePantryQuantity(_quantity.text),
        unit: _unit.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on PantryItemMissing {
      if (mounted) setState(() => _error = 'Namirnica nije pronađena.');
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Provera nije sačuvana. Pokušaj ponovo.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Proveri količinu'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item.name),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('check-quantity'),
              controller: _quantity,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Količina'),
              validator: (text) {
                final q = parsePantryQuantity(text ?? '');
                return q == null || !q.isFinite || q <= 0
                    ? 'Unesi broj veći od nule.'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('check-unit'),
              controller: _unit,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Jedinica'),
              onFieldSubmitted: (_) => _save(),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Odustani'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Čuvam…' : 'Potvrdi'),
        ),
      ],
    ),
  );
}
