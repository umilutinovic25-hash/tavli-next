import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tavli_ui/tavli_ui.dart';

import '../../app/animations/all_bought.dart';
import '../../data/database.dart';
import '../../domain/meal_plan.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_format.dart';
import '../../domain/shopping_source.dart';
import '../../providers.dart';
import '../planning/plan_format.dart';
import 'shopping_frame.dart';
import 'shopping_providers.dart';
import 'store_price_summary.dart';

/// "1,5 kg", "~35 ml", "2 kom"; null kad količina nije poznata.
String? amountLabel(
  double? quantity,
  String? unit, {
  bool approximate = false,
}) => quantity == null
    ? null
    : '${approximate ? '~' : ''}${[formatQuantity(quantity), ?unit].join(' ').trim()}';

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
    showTavliMessageOn(messenger, 'Već je primljeno u ostavu.');
    return;
  }
  if (changed == 0) return;
  showTavliMessageOn(
    messenger,
    bought ? 'Kupljeno: $name' : 'Vraćeno u nabavku: $name',
    actionLabel: 'Poništi',
    onAction: () => unawaited(repo.setBought(ids, bought: !bought)),
  );
}

/// Otvorene stavke po kategorijama (naslov odeljka i grupisana lista), pa
/// „Kupljeno · n“ sa kupljenim stavkama.
List<Widget> groupedRows<T>({
  required List<T> open,
  required List<T> bought,
  required String Function(T) category,
  required Widget Function(T) row,
  required String emptyText,
  required String allBoughtText,
  required TextTheme text,
  required ColorScheme colors,
}) => [
  if (open.isEmpty)
    Padding(
      padding: const EdgeInsets.symmetric(vertical: TavliSpacing.large),
      child: Column(
        children: [
          if (bought.isNotEmpty) const AllBoughtArt(),
          Text(
            bought.isEmpty ? emptyText : allBoughtText,
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    ),
  for (final (c, list) in byCategory(open, category)) ...[
    TavliSectionHeader(categoryLabel(c)),
    TavliListGroup(children: [for (final i in list) row(i)]),
    const SizedBox(height: TavliSpacing.small),
  ],
  if (bought.isNotEmpty) ...[
    TavliSectionHeader(
      'Kupljeno · ${bought.length}',
      style: TavliSectionHeaderStyle.bold,
    ),
    TavliListGroup(children: [for (final i in bought) row(i)]),
  ],
];

/// Lista jedne nedelje ili nabavke bez plana: brzo dodavanje, otvorene
/// stavke po kategorijama, pa kupljene sa prijemom u ostavu.
///
/// Na širokom ekranu sa dovoljno mesta dodir na stavku je bira za detalj
/// desno („Za koje obroke“); inače dug pritisak otvara isto u donjem listu.
class ShoppingItemsList extends ConsumerStatefulWidget {
  const ShoppingItemsList({
    super.key,
    required this.mode,
    required this.items,
    required this.listId,
    this.filters = const [],
    this.header = const [],
    this.emptyText = 'Ovde nema šta da se kupi.',
  });

  final Widget mode;
  final List<ShoppingItemRow> items;

  /// Lista u koju ide ručna stavka (pravi je po potrebi).
  final Future<String> Function() listId;
  final List<Widget> filters;

  /// Sadržaj iznad polja za dodavanje (npr. „Recepti u nabavci“).
  final List<Widget> header;
  final String emptyText;

  @override
  ConsumerState<ShoppingItemsList> createState() => _ShoppingItemsListState();
}

class _ShoppingItemsListState extends ConsumerState<ShoppingItemsList> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.items;
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
      showTavliMessageOn(messenger, 'Prebačeno u ostavu: $n');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final withDetail = hasShoppingDetail(context, constraints);
        // Izabrana stavka, inače prva otvorena (kao na platnu).
        ShoppingItemRow? selected;
        if (withDetail) {
          for (final i in items) {
            if (i.id == _selectedId) selected = i;
          }
          selected ??= open.firstOrNull ?? bought.firstOrNull;
        }

        Widget row(ShoppingItemRow i) => ShoppingItemTile(
          item: i,
          resolveList: widget.listId,
          received: received.contains(i.id),
          selected: selected?.id == i.id,
          onSelect: withDetail
              ? () => setState(() => _selectedId = i.id)
              : null,
        );

        return ShoppingFrame(
          mode: widget.mode,
          filters: widget.filters,
          pantry: toPantry.isEmpty
              ? null
              : (count: toPantry.length, onPressed: () => unawaited(receive())),
          detail: selected == null
              ? null
              : ShoppingItemDetail(
                  key: ValueKey(selected.id),
                  name: selected.name,
                  amount: amountLabel(selected.quantity, selected.unit),
                  ids: selected.isManual ? const [] : [selected.id],
                  bought: selected.isBought,
                ),
          children: [
            ...widget.header,
            QuickAddField(listId: widget.listId),
            const SizedBox(height: TavliSpacing.small),
            ...groupedRows(
              open: open,
              bought: bought,
              category: (i) => i.category,
              row: row,
              emptyText: widget.emptyText,
              allBoughtText: 'Sve je kupljeno.',
              text: theme.textTheme,
              colors: theme.colorScheme,
            ),
            StorePriceSummary(items: items),
          ],
        );
      },
    );
  }
}

/// Jedna stavka: dodir štiklira odmah; dug pritisak pokazuje za koje
/// obroke je (čitač ekrana: radnja „Za koje obroke“). Sa [onSelect] (lista
/// i detalj) dodir bira stavku, a štiklira se poljem.
class ShoppingItemTile extends ConsumerWidget {
  const ShoppingItemTile({
    super.key,
    required this.item,
    required this.resolveList,
    this.received = false,
    this.selected = false,
    this.onSelect,
  });

  final ShoppingItemRow item;
  final Future<String> Function() resolveList;
  final bool received;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amount = amountLabel(item.quantity, item.unit);
    final detail = [
      if (amount != null)
        amount
      else if (!item.isManual && !item.isBought)
        'Proveri količinu',
      if (received) 'U ostavi',
    ].join(' · ');
    void toggle() => unawaited(
      setBought(context, ref, [item.id], item.name, bought: !item.isBought),
    );
    Future<void> delete() async {
      final messenger = ScaffoldMessenger.of(context);
      final repo = ref.read(shoppingRepositoryProvider);
      await repo.deleteManual(item.id);
      showTavliMessageOn(
        messenger,
        'Obrisano: ${item.name}',
        actionLabel: 'Vrati',
        onAction: () => unawaited(
          repo.addManualToList(
            resolveList,
            item.name,
            quantity: item.quantity,
            unit: item.unit,
            category: item.category,
          ),
        ),
      );
    }

    final showSources = item.isManual || onSelect != null
        ? null
        : () => unawaited(showItemSources(context, ref, item));
    return TavliContextMenu(
      // Desni klik (računar): isto što i dugi pritisak.
      actions: [
        if (showSources != null)
          TavliMenuAction('Za koje obroke', onSelected: showSources),
        if (item.isManual && !item.isBought)
          TavliMenuAction(
            'Obriši',
            isDestructive: true,
            onSelected: () => unawaited(delete()),
          ),
      ],
      child: TavliCheckRow(
        title: item.name,
        detail: detail.isEmpty ? null : detail,
        checked: item.isBought,
        onChanged: received ? null : (_) => toggle(),
        onSelect: onSelect,
        selected: selected,
        onLongPress: showSources,
        longPressLabel: showSources == null ? null : 'Za koje obroke',
        trailing: item.isManual && !item.isBought
            ? TavliIconButton(
                glyph: TavliIcons.delete,
                semanticLabel: 'Obriši',
                onPressed: () => unawaited(delete()),
              )
            : null,
      ),
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
    await repo.addManualToList(widget.listId, name);
  }

  @override
  Widget build(BuildContext context) => TavliTextField(
    controller: _controller,
    label: 'Dodaj stavku',
    hint: 'npr. deterdžent',
    textInputAction: TextInputAction.done,
    textCapitalization: TextCapitalization.sentences,
    onSubmitted: (_) => unawaited(_add()),
    trailing: TavliIconButton(
      glyph: TavliIcons.add,
      semanticLabel: 'Dodaj',
      onPressed: () => unawaited(_add()),
    ),
  );
}

/// Za koje obroke ili recepte je stavka (za kupljenu: u trenutku kupovine),
/// u donjem listu.
Future<void> showItemSources(
  BuildContext context,
  WidgetRef ref,
  ShoppingItemRow item,
) async {
  final sources = await ref
      .read(shoppingRepositoryProvider)
      .itemSources(item.id);
  if (!context.mounted) return;
  await showTavliSheet<void>(
    context,
    title: item.name,
    builder: (context) => _SourcesList(sources: sources, bought: item.isBought),
  );
}

/// Detalj izabrane stavke na širokom ekranu: naziv, količina i „Za koje
/// obroke“. [ids] su stavke iz kojih se čita poreklo (cela lista plana ima
/// više nedeljnih stavki); prazno za ručnu stavku.
class ShoppingItemDetail extends ConsumerStatefulWidget {
  const ShoppingItemDetail({
    super.key,
    required this.name,
    required this.amount,
    required this.ids,
    required this.bought,
  });

  final String name;
  final String? amount;
  final List<String> ids;
  final bool bought;

  @override
  ConsumerState<ShoppingItemDetail> createState() => _ShoppingItemDetailState();
}

class _ShoppingItemDetailState extends ConsumerState<ShoppingItemDetail> {
  late Future<List<ItemSource>> _sources = _load();

  Future<List<ItemSource>> _load() async {
    final repo = ref.read(shoppingRepositoryProvider);
    final all = await Future.wait(widget.ids.map(repo.itemSources));
    return [for (final list in all) ...list];
  }

  @override
  void didUpdateWidget(ShoppingItemDetail old) {
    super.didUpdateWidget(old);
    if (old.bought != widget.bought || old.ids.join() != widget.ids.join()) {
      _sources = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = widget.amount;
    return TavliCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              widget.name,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (amount != null)
            Text(
              widget.bought ? '$amount kupljeno' : '$amount ukupno',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (widget.ids.isNotEmpty) ...[
            const SizedBox(height: TavliSpacing.small),
            FutureBuilder(
              future: _sources,
              builder: (context, snapshot) => switch (snapshot.data) {
                final sources? => _SourcesList(
                  sources: sources,
                  bought: widget.bought,
                ),
                null => const TavliLoading(),
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// „Za koje obroke“ (ili „Kupljeno za“) i obroci ili recepti stavke.
class _SourcesList extends StatelessWidget {
  const _SourcesList({required this.sources, required this.bought});

  final List<ItemSource> sources;
  final bool bought;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: TavliSpacing.small,
      children: [
        TavliSectionHeader(bought ? 'Kupljeno za' : 'Za koje obroke'),
        if (sources.isEmpty)
          Text('Dodato ranije, bez obroka.', style: theme.textTheme.bodyMedium),
        for (final s in sources) _SourceLine(s),
      ],
    );
  }
}

class _SourceLine extends StatelessWidget {
  const _SourceLine(this.source);

  final ItemSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = source;
    final servings = s.servings == null ? null : servingsLabel(s.servings!);
    final date = s.date;
    final subtitle = date != null
        ? [
            dayLabel(date),
            ?MealType.tryParse(s.mealType)?.label,
            ?servings,
          ].join(' · ')
        : ['Recept', ?servings].join(' · ');
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
