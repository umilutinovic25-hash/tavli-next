import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/meal_plan.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_format.dart';
import '../../domain/shopping_source.dart';
import '../../providers.dart';
import '../planning/plan_format.dart';
import '../recipes/recipe_providers.dart';
import 'shopping_details.dart';
import 'shopping_providers.dart';

/// "1,5 kg", "2 kom"; null kad količina nije poznata.
String? amountLabel(double? quantity, String? unit) => quantity == null
    ? null
    : [formatQuantity(quantity), ?unit].join(' ').trim();

/// "Voće i povrće"
String categoryLabel(String category) => category.isEmpty
    ? category
    : category[0].toUpperCase() + category.substring(1);

/// Redosled kategorija kao kroz prodavnicu; nepoznata ide u "ostalo".
List<(String, List<T>)> byCategory<T>(
  List<T> items,
  String Function(T) category,
) {
  final groups = <String, List<T>>{};
  for (final i in items) {
    final c = ingredientCategories.contains(category(i))
        ? category(i)
        : 'ostalo';
    groups.putIfAbsent(c, () => []).add(i);
  }
  return [
    for (final c in ingredientCategories)
      if (groups[c] case final list?) (c, list),
  ];
}

/// Štiklira (ili vraća) stavke odmah, bez potvrde, uz "Poništi".
Future<void> setBought(
  BuildContext context,
  WidgetRef ref,
  List<String> ids,
  String name, {
  required bool bought,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(shoppingRepositoryProvider);
  final changed = await repo.setBought(ids, bought: bought);
  messenger.hideCurrentSnackBar();
  if (changed == 0 && !bought) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Već je primljeno u ostavu.')),
    );
    return;
  }
  if (changed == 0) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(bought ? 'Kupljeno: $name' : 'Vraćeno u nabavku: $name'),
      action: SnackBarAction(
        label: 'Poništi',
        onPressed: () => unawaited(repo.setBought(ids, bought: !bought)),
      ),
    ),
  );
}

/// Lista jedne nedelje ili nabavke bez plana: brzo dodavanje, otvorene
/// stavke po kategorijama, pa kupljene sa prijemom u ostavu.
class ShoppingItemsList extends ConsumerWidget {
  const ShoppingItemsList({
    super.key,
    required this.items,
    required this.listId,
    this.header = const [],
    this.emptyText = 'Ovde nema šta da se kupi.',
  });

  final List<ShoppingItemRow> items;

  /// Lista u koju ide ručna stavka (pravi je po potrebi).
  final Future<String> Function() listId;
  final List<Widget> header;
  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final received = ref.watch(receivedItemsProvider).value ?? const {};
    final open = [
      for (final i in items)
        if (!i.isBought) i,
    ];
    final bought = [
      for (final i in items)
        if (i.isBought) i,
    ];
    final toPantry = [
      for (final i in bought)
        if (!received.contains(i.id)) i.id,
    ];

    Future<void> receive() async {
      final messenger = ScaffoldMessenger.of(context);
      final n = await ref
          .read(pantryRepositoryProvider)
          .receivePurchases(toPantry);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Prebačeno u ostavu: $n')));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        ...header,
        QuickAddField(listId: listId),
        const SizedBox(height: 8),
        if (open.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              bought.isEmpty ? emptyText : 'Sve je kupljeno.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final (category, list) in byCategory(open, (i) => i.category)) ...[
          CategoryHeader(categoryLabel(category)),
          for (final i in list) ShoppingItemTile(item: i),
        ],
        if (bought.isNotEmpty) ...[
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Kupljeno · ${bought.length}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (toPantry.isNotEmpty)
                TextButton.icon(
                  onPressed: receive,
                  icon: const Icon(Icons.kitchen_outlined),
                  label: Text('Prebaci u ostavu (${toPantry.length})'),
                ),
            ],
          ),
          for (final i in bought)
            ShoppingItemTile(item: i, received: received.contains(i.id)),
        ],
      ],
    );
  }
}

class CategoryHeader extends StatelessWidget {
  const CategoryHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// Jedna stavka: dodir štiklira odmah; "i" pokazuje za koje obroke je.
class ShoppingItemTile extends ConsumerWidget {
  const ShoppingItemTile({
    super.key,
    required this.item,
    this.received = false,
  });

  final ShoppingItemRow item;
  final bool received;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final amount = amountLabel(item.quantity, item.unit);
    final subtitle = [
      if (amount != null)
        amount
      else if (!item.isManual && !item.isBought)
        'Proveri količinu',
      ?item.brand,
      ?item.note,
      if (received) 'U ostavi',
    ].join(' · ');
    void toggle() => unawaited(
      setBought(context, ref, [item.id], item.name, bought: !item.isBought),
    );
    Future<void> delete() async {
      final messenger = ScaffoldMessenger.of(context);
      final repo = ref.read(shoppingRepositoryProvider);
      await repo.deleteManual(item.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Obrisano: ${item.name}'),
            action: SnackBarAction(
              label: 'Vrati',
              onPressed: () => unawaited(repo.restoreManual(item)),
            ),
          ),
        );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 56,
      leading: Checkbox(
        value: item.isBought,
        onChanged: received ? null : (_) => toggle(),
      ),
      title: Row(
        children: [
          if (item.photoPath case final path?) ...[
            Consumer(
              builder: (context, ref, _) {
                final file = ref.watch(recipePhotoFileProvider(path)).value;
                return file == null
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.photo_outlined),
                      )
                    : Image.file(
                        file,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        semanticLabel: 'Fotografija proizvoda',
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      );
              },
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              item.name,
              style: item.isBought
                  ? TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
          ),
        ],
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Detalji stavke',
            icon: Icon(
              item.photoPath == null ? Icons.edit_note : Icons.photo_outlined,
            ),
            onPressed: () => unawaited(showShoppingDetails(context, item)),
          ),
          if (item.isManual && !item.isBought)
            IconButton(
              tooltip: 'Obriši',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => unawaited(delete()),
            )
          else if (!item.isManual)
            IconButton(
              tooltip: 'Za koje obroke',
              icon: const Icon(Icons.info_outline),
              onPressed: () => unawaited(showItemSources(context, ref, item)),
            ),
        ],
      ),
      onTap: received ? null : toggle,
    );
  }
}

/// Polje za brzo dodavanje ručne stavke.
class QuickAddField extends ConsumerStatefulWidget {
  const QuickAddField({super.key, required this.listId});

  final Future<String> Function() listId;

  @override
  ConsumerState<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends ConsumerState<QuickAddField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    _controller.clear();
    final repo = ref.read(shoppingRepositoryProvider);
    await repo.addManual(await widget.listId(), name);
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    textInputAction: TextInputAction.done,
    textCapitalization: TextCapitalization.sentences,
    onSubmitted: (_) => unawaited(_add()),
    decoration: InputDecoration(
      labelText: 'Dodaj stavku',
      hintText: 'npr. deterdžent',
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        tooltip: 'Dodaj',
        icon: const Icon(Icons.add),
        onPressed: () => unawaited(_add()),
      ),
    ),
  );
}

/// Za koje obroke ili recepte je stavka (za kupljenu: u trenutku kupovine).
Future<void> showItemSources(
  BuildContext context,
  WidgetRef ref,
  ShoppingItemRow item,
) async {
  final sources = await ref
      .read(shoppingRepositoryProvider)
      .itemSources(item.id);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(item.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(item.isBought ? 'Kupljeno za:' : 'Potrebno za:'),
          if (sources.isEmpty)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Dodato ranije, bez obroka.'),
            ),
          for (final s in sources) _SourceTile(s),
        ],
      ),
    ),
  );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile(this.source);

  final ItemSource source;

  @override
  Widget build(BuildContext context) {
    final s = source;
    final servings = s.servings == null ? null : servingsLabel(s.servings!);
    final date = s.date;
    if (date != null) {
      final meal = MealType.tryParse(s.mealType)?.label;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.calendar_today_outlined),
        title: Text(s.title),
        subtitle: Text([dayLabel(date), ?meal, ?servings].join(' · ')),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.menu_book_outlined),
      title: Text(s.title),
      subtitle: Text(['Recept', ?servings].join(' · ')),
    );
  }
}
