import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/database.dart';
import '../../data/pantry_repository.dart';
import '../../domain/recipe.dart';
import '../shopping/shopping_providers.dart';
import 'pantry_fields.dart';
import 'pantry_item_tile.dart';

class PantryFormScreen extends ConsumerStatefulWidget {
  const PantryFormScreen({super.key, this.item});
  final PantryItemRow? item;
  @override
  ConsumerState<PantryFormScreen> createState() => _PantryFormScreenState();
}

class _PantryFormScreenState extends ConsumerState<PantryFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name);
  late final _quantity = TextEditingController(
    text: widget.item?.quantity == null
        ? ''
        : pantryAmount(widget.item!.quantity!),
  );
  late final _unit = TextEditingController(text: widget.item?.unit);
  late final _expiry = TextEditingController(
    text: widget.item?.expiresAt == null
        ? ''
        : pantryDate(widget.item!.expiresAt!),
  );
  late String _category = ingredientCategories.contains(widget.item?.category)
      ? widget.item!.category
      : 'ostalo';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_name, _quantity, _unit, _expiry]) {
      controller.dispose();
    }
    super.dispose();
  }

  double? get _amount => parsePantryQuantity(_quantity.text);

  DateTime? _date() => parsePantryExpiry(_expiry.text);

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(pantryRepositoryProvider);
      if (widget.item case final item?) {
        await repo.update(
          item.id,
          name: _name.text,
          quantity: _amount,
          unit: _unit.text,
          category: _category,
          expiresAt: _date(),
        );
      } else {
        await repo.create(
          name: _name.text,
          quantity: _amount,
          unit: _unit.text,
          category: _category,
          expiresAt: _date(),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Namirnica je sačuvana.')));
      context.go('/pantry');
    } on PantryItemMissing {
      if (mounted) setState(() => _error = 'Namirnica nije pronađena.');
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Izmena nije sačuvana. Pokušaj ponovo.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ukloni namirnicu?'),
        content: Text(
          '${widget.item!.name}\nIstorija kupovine ostaje sačuvana.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Odustani'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ukloni'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(pantryRepositoryProvider).remove(widget.item!.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Namirnica je uklonjena.')));
      context.go('/pantry');
    } on PantryItemMissing {
      if (mounted) setState(() => _error = 'Namirnica nije pronađena.');
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Uklanjanje nije uspelo. Pokušaj ponovo.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.item == null ? 'Dodaj namirnicu' : 'Izmeni namirnicu'),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                PantryFields(
                  name: _name,
                  quantity: _quantity,
                  unit: _unit,
                  expiry: _expiry,
                  category: _category,
                  enabled: !_saving,
                  onCategoryChanged: (value) =>
                      setState(() => _category = value),
                  onSubmit: _save,
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Čuvam…' : 'Sačuvaj'),
                ),
                if (widget.item != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _remove,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Obriši'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
