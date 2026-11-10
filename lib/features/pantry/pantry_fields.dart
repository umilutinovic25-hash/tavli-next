import 'package:flutter/material.dart';

import '../../domain/recipe.dart';

double? parsePantryQuantity(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

DateTime? parsePantryExpiry(String text) {
  final match = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})\.?$')
      .firstMatch(text.trim());
  if (match == null) return null;
  final day = int.parse(match[1]!),
      month = int.parse(match[2]!),
      year = int.parse(match[3]!);
  final date = DateTime(year, month, day);
  if (date.day != day || date.month != month || year < 1900 || year > 9998) {
    return null;
  }
  return DateTime(
    year,
    month,
    day + 1,
  ).subtract(const Duration(microseconds: 1));
}

class PantryFields extends StatelessWidget {
  const PantryFields({
    super.key,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.expiry,
    required this.category,
    required this.onCategoryChanged,
    required this.enabled,
    required this.onSubmit,
  });
  final TextEditingController name, quantity, unit, expiry;
  final String category;
  final ValueChanged<String> onCategoryChanged;
  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextFormField(
        key: const ValueKey('pantry-name'),
        controller: name,
        enabled: enabled,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Naziv'),
        validator: (value) => value!.trim().isEmpty ? 'Unesi naziv.' : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        key: const ValueKey('pantry-quantity'),
        controller: quantity,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Količina',
          helperText: 'Prazno ako količina nije potvrđena.',
          helperMaxLines: 3,
        ),
        validator: (value) =>
            value!.trim().isEmpty ||
                (parsePantryQuantity(quantity.text) != null &&
                    parsePantryQuantity(quantity.text)!.isFinite &&
                    parsePantryQuantity(quantity.text)! > 0)
            ? null
            : 'Unesi broj veći od nule.',
      ),
      const SizedBox(height: 16),
      TextFormField(
        key: const ValueKey('pantry-unit'),
        controller: unit,
        enabled: enabled,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Jedinica',
          hintText: 'kg, g, l, ml, kom',
        ),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        initialValue: category,
        isExpanded: true,
        selectedItemBuilder: (context) => [
          for (final category in ingredientCategories)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        decoration: const InputDecoration(labelText: 'Kategorija'),
        items: [
          for (final category in ingredientCategories)
            DropdownMenuItem(value: category, child: Text(category)),
        ],
        onChanged: enabled ? (value) => onCategoryChanged(value!) : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        key: const ValueKey('pantry-expiry'),
        controller: expiry,
        enabled: enabled,
        keyboardType: TextInputType.datetime,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Rok trajanja',
          hintText: '31.12.2026.',
          helperText: 'Prazno ako rok nije naveden.',
          helperMaxLines: 3,
        ),
        validator: (value) =>
            value!.trim().isEmpty || parsePantryExpiry(expiry.text) != null
            ? null
            : 'Unesi datum u obliku d.m.gggg.',
        onFieldSubmitted: (_) => onSubmit(),
      ),
    ],
  );
}
