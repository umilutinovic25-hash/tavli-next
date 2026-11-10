import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cook_soon_repository.dart';
import '../../domain/cook_soon.dart';
import '../../domain/meal_plan.dart';
import '../../domain/plan_calendar.dart';
import '../../domain/recipe_format.dart';
import '../recipes/recipe_providers.dart';
import 'meal_actions.dart';
import 'plan_format.dart';
import 'planning_providers.dart';

void _say(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

String _cookSoonError(Object e) => e is CookSoonItemNotFoundException
    ? 'Recept više nije u redu „Uskoro kuvam“.'
    : mealErrorText(e);

Future<void> _run(
  BuildContext context,
  Future<void> Function() action, {
  String? done,
}) async {
  try {
    await action();
    if (done != null && context.mounted) _say(context, done);
  } on Exception catch (e) {
    if (context.mounted) _say(context, _cookSoonError(e));
  }
}

enum _ItemAction { up, down, remove }

/// Red "Uskoro kuvam" u Planu: recepti bez datuma, raspoređuju se dugmetom.
class CookSoonSection extends ConsumerWidget {
  const CookSoonSection({super.key, required this.plan, required this.meals});

  final MealPlan plan;
  final List<PlannedMeal> meals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cookSoonItemsProvider).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final repo = ref.read(cookSoonRepositoryProvider);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('Uskoro kuvam', style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Recepti bez datuma; nabavka se pravi tek kad ih rasporediš.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final (index, item) in items.indexed)
              ListTile(
                title: Text(item.snapshot.title),
                subtitle: Text(servingsLabel(item.servings)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => showScheduleDialog(
                        context,
                        ref,
                        item: item,
                        plan: plan,
                        meals: meals,
                      ),
                      child: const Text('Rasporedi'),
                    ),
                    PopupMenuButton<_ItemAction>(
                      tooltip: 'Još opcija za „${item.snapshot.title}“',
                      onSelected: (action) => _run(
                        context,
                        () => switch (action) {
                          _ItemAction.up => repo.move(item.id, index - 1),
                          _ItemAction.down => repo.move(item.id, index + 1),
                          _ItemAction.remove => repo.remove(item.id),
                        },
                        done: action == _ItemAction.remove
                            ? 'Uklonjeno iz reda „Uskoro kuvam“.'
                            : null,
                      ),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: _ItemAction.up,
                          enabled: index > 0,
                          child: const Text('Pomeri gore'),
                        ),
                        PopupMenuItem(
                          value: _ItemAction.down,
                          enabled: index < items.length - 1,
                          child: const Text('Pomeri dole'),
                        ),
                        const PopupMenuItem(
                          value: _ItemAction.remove,
                          child: Text('Ukloni iz reda'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bira dan i obrok plana za stavku i pokazuje šta se dešava sa tim
/// mestom pre potvrde.
Future<void> showScheduleDialog(
  BuildContext context,
  WidgetRef ref, {
  required CookSoonItem item,
  required MealPlan plan,
  required List<PlannedMeal> meals,
}) async {
  final plans = ref.read(mealPlanRepositoryProvider);
  final base = PlanBase(
    planId: plan.id,
    fingerprint: await plans.fingerprint(plan.id),
  );
  if (!context.mounted) return;
  final today = CivilDate.today(ref.read(clockProvider));
  final slot = await showDialog<MealSlot>(
    context: context,
    builder: (context) =>
        _ScheduleDialog(item: item, plan: plan, meals: meals, today: today),
  );
  if (slot == null || !context.mounted) return;
  await _run(
    context,
    () => ref
        .read(cookSoonRepositoryProvider)
        .schedule(item.id, plan: plan, slot: slot, base: base),
    done: '„${item.snapshot.title}“ je u planu.',
  );
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({
    required this.item,
    required this.plan,
    required this.meals,
    required this.today,
  });

  final CookSoonItem item;
  final MealPlan plan;
  final List<PlannedMeal> meals;
  final CivilDate today;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  late final List<CivilDate> _days = [
    for (final d in widget.plan.range.days)
      if (!d.isBefore(widget.today)) d,
  ];
  late final List<MealType> _types = [
    for (final t in MealType.values)
      if (widget.plan.mealTypes.contains(t)) t,
  ];
  late final Map<MealSlot, PlannedMeal> _bySlot = {
    for (final m in widget.meals) m.slot: m,
  };
  CivilDate? _day;
  late MealType _type = _types.first;

  @override
  void initState() {
    super.initState();
    // Prvo slobodno mesto, inače prvi preostali dan.
    for (final d in _days) {
      for (final t in _types) {
        if (_day == null && !_bySlot.containsKey(MealSlot(d, t))) {
          _day = d;
          _type = t;
        }
      }
    }
    _day ??= _days.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = _day;
    final slot = day == null ? null : MealSlot(day, _type);
    final current = slot == null ? null : _bySlot[slot];
    final protected = current != null && (current.isLocked || current.isCooked);
    final status = switch (current) {
      null when slot == null =>
        'Plan je prošao. Izaberi ili napravi plan za naredne dane.',
      null =>
        'Mesto je prazno; obrok dobija ${servingsLabel(widget.item.servings)}.',
      final m when protected =>
        '„${m.snapshot?.title ?? 'Obrok'}“ je '
            '${m.isCooked ? 'skuvan' : 'zaključan'} i ne menja se.',
      final m =>
        'Zameniće „${m.snapshot?.title ?? 'obrok'}“; '
            'obrok zadržava ${servingsLabel(m.servings)}.',
    };
    return AlertDialog(
      title: Text('Rasporedi „${widget.item.snapshot.title}“'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(rangeLabel(widget.plan.range)),
            const SizedBox(height: 12),
            if (_days.isNotEmpty) ...[
              DropdownButtonFormField<CivilDate>(
                initialValue: day,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Dan',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final d in _days)
                    DropdownMenuItem(value: d, child: Text(dayLabel(d))),
                ],
                onChanged: (d) => setState(() => _day = d),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MealType>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Obrok',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final t in _types)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (t) => setState(() => _type = t ?? _type),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              status,
              style: protected
                  ? theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    )
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Otkaži'),
        ),
        FilledButton(
          onPressed: slot == null || protected
              ? null
              : () => Navigator.pop(context, slot),
          child: Text(current == null ? 'Rasporedi' : 'Zameni'),
        ),
      ],
    );
  }
}
