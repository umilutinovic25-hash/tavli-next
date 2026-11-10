import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/meal_plan_repository.dart';
import '../../domain/meal_plan.dart';
import '../../domain/plan_calendar.dart';
import '../recipes/recipe_providers.dart';
import 'plan_format.dart';
import 'planning_providers.dart';

Future<void> saveWeekTemplate(
  BuildContext context,
  WidgetRef ref,
  MealPlan plan,
  CivilDate selected,
) async {
  var input = '';
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Sačuvaj nedelju kao šablon'),
      content: TextField(
        onChanged: (value) => input = value,
        autofocus: true,
        maxLength: 100,
        decoration: const InputDecoration(labelText: 'Naziv šablona'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Otkaži'),
        ),
        FilledButton(
          onPressed: () {
            if (input.trim().isNotEmpty) {
              Navigator.pop(dialogContext, input.trim());
            }
          },
          child: const Text('Sačuvaj'),
        ),
      ],
    ),
  );
  if (name == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(mealPlanRepositoryProvider)
        .saveWeekTemplate(plan.id, selected, name);
    messenger.showSnackBar(const SnackBar(content: Text('Šablon je sačuvan.')));
  } on InvalidWeekTemplateException {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'U ovoj nedelji nema obroka sa sačuvanim receptom ili neki recept nedostaje.',
        ),
      ),
    );
  } on Exception {
    messenger.showSnackBar(
      const SnackBar(content: Text('Šablon nije sačuvan. Pokušaj ponovo.')),
    );
  }
}

Future<void> openWeekTemplates(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _TemplatesDialog(),
);

class _TemplatesDialog extends ConsumerStatefulWidget {
  const _TemplatesDialog();
  @override
  ConsumerState<_TemplatesDialog> createState() => _TemplatesDialogState();
}

class _TemplatesDialogState extends ConsumerState<_TemplatesDialog> {
  String? selectedId;
  CivilDate? anchor;
  int servings = 2;
  bool saving = false;
  String? error;

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(weekTemplatesProvider);
    final today = CivilDate.today(ref.watch(clockProvider));
    final date = anchor ?? today;
    return AlertDialog(
      title: const Text('Šabloni nedelje'),
      content: SizedBox(
        width: 500,
        child: templates.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Text('Šabloni trenutno nisu dostupni.'),
          data: (list) {
            if (list.isEmpty) return const Text('Nema sačuvanih šablona.');
            final selected =
                list.where((t) => t.id == selectedId).firstOrNull ?? list.first;
            final week = weekOf(date);
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selected.id,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Šablon'),
                    items: [
                      for (final t in list)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text(t.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) => setState(() => selectedId = value),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: date.toWire(),
                              firstDate: today.toWire(),
                              lastDate: DateTime(today.year + 10, 12, 31),
                            );
                            if (picked != null && mounted) {
                              setState(
                                () => anchor = CivilDate.fromDateTime(picked),
                              );
                            }
                          },
                    icon: const Icon(Icons.calendar_month),
                    label: Text('Nedelja: ${rangeLabel(week)}'),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: servings,
                    decoration: const InputDecoration(
                      labelText: 'Porcije po obroku',
                    ),
                    items: [
                      for (var i = 1; i <= 20; i++)
                        DropdownMenuItem(value: i, child: Text('$i')),
                    ],
                    onChanged: saving
                        ? null
                        : (value) => setState(() => servings = value!),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pregled',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final meal in selected.meals)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(meal.snapshot.title),
                      subtitle: Text(
                        '${dayLabel(week.start.addDays(meal.weekday - 1))} · ${meal.type.label} · $servings porcija',
                      ),
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Otkaži'),
        ),
        if (templates.value case final list? when list.isNotEmpty)
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    final selected =
                        list.where((t) => t.id == selectedId).firstOrNull ??
                        list.first;
                    setState(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      final id = await ref
                          .read(mealPlanRepositoryProvider)
                          .applyWeekTemplate(selected.id, date, servings);
                      if (!mounted || !context.mounted) return;
                      ref.read(planViewProvider.notifier).selectPlan(id);
                      Navigator.pop(context);
                    } on Exception {
                      if (mounted) {
                        setState(() {
                          saving = false;
                          error = 'Plan nije sačuvan. Pokušaj ponovo.';
                        });
                      }
                    }
                  },
            child: const Text('Sačuvaj plan'),
          ),
      ],
    );
  }
}
