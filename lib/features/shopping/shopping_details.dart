import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../foods/food_chip.dart';
import '../foods/food_picker.dart';
import '../recipes/recipe_providers.dart';

Future<void> showShoppingDetails(BuildContext context, ShoppingItemRow item) =>
    showDialog<void>(context: context, builder: (_) => _ShoppingDetails(item));

class _ShoppingDetails extends ConsumerStatefulWidget {
  const _ShoppingDetails(this.item);
  final ShoppingItemRow item;

  @override
  ConsumerState<_ShoppingDetails> createState() => _ShoppingDetailsState();
}

class _ShoppingDetailsState extends ConsumerState<_ShoppingDetails> {
  late final _brand = TextEditingController(text: widget.item.brand);
  late final _note = TextEditingController(text: widget.item.note);
  Uint8List? _photo;
  bool _removed = false;
  late String? _foodId = widget.item.foodId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _brand.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(bool camera) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await ref.read(photoPickerProvider).pick(camera: camera);
      if (picked == null) return;
      final jpeg = await ref.read(photoResizerProvider)(picked);
      if (jpeg.length > 5242880) throw const FormatException();
      if (mounted) {
        setState(() {
          _photo = jpeg;
          _removed = false;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Fotografija nije učitana. Pokušaj ponovo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = ref.read(recipePhotoStoreProvider);
    String? created;
    try {
      if (_photo case final bytes?) created = await store.save(bytes);
      final repo = ref.read(shoppingRepositoryProvider);
      if (_foodId case final food? when food != widget.item.foodId) {
        if (!await repo.setManualFood(widget.item.id, food)) {
          throw StateError('Stavka se više ne menja');
        }
      }
      final ok = await repo.updateDetails(
        widget.item.id,
        brand: _brand.text,
        note: _note.text,
        photoPath: created ?? (_removed ? null : widget.item.photoPath),
      );
      if (!ok) throw StateError('Stavka više ne postoji');
      if (mounted) Navigator.of(context).pop();
    } on Exception {
      if (created != null) await store.delete(created);
      if (mounted) {
        setState(
          () => _error = _photo != null
              ? 'Fotografija nije sačuvana. Pokušaj ponovo.'
              : 'Detalji nisu sačuvani. Pokušaj ponovo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = _removed ? null : widget.item.photoPath;
    final file = currentPath == null
        ? null
        : ref.watch(recipePhotoFileProvider(currentPath)).value;
    return AlertDialog(
      title: Text('Detalji stavke: ${widget.item.name}'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Namirnicu bira osoba samo za ručnu stavku; izvedena prati
              // recept.
              if (widget.item.isManual && !widget.item.isBought)
                FoodChip(
                  foodId: _foodId,
                  onPressed: _busy
                      ? null
                      : () async {
                          final id = await pickFood(
                            context,
                            text: widget.item.name,
                            category: widget.item.category,
                            unit: widget.item.unit,
                          );
                          if (id != null && mounted) {
                            setState(() => _foodId = id);
                          }
                        },
                ),
              TextField(
                controller: _brand,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Brend'),
              ),
              TextField(
                controller: _note,
                maxLength: 1000,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Napomena'),
              ),
              if (_photo != null)
                Image.memory(
                  _photo!,
                  height: 120,
                  semanticLabel: 'Fotografija proizvoda',
                )
              else if (file != null)
                Image.file(
                  file,
                  height: 120,
                  semanticLabel: 'Fotografija proizvoda',
                )
              else if (currentPath != null)
                const Text('Fotografija se preuzima.'),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _photo != null || currentPath != null
                      ? 'Promeni fotografiju'
                      : 'Dodaj fotografiju',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  if (ref.watch(photoPickerProvider).canUseCamera)
                    TextButton.icon(
                      onPressed: _busy ? null : () => _pick(true),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Kamera'),
                    ),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _pick(false),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galerija'),
                  ),
                  if (_photo != null || currentPath != null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _photo = null;
                              _removed = true;
                            }),
                      child: const Text('Ukloni fotografiju'),
                    ),
                ],
              ),
              if (_error case final message?)
                Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Otkaži'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Sačuvaj'),
        ),
      ],
    );
  }
}
