import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/meal_plan.dart';
import 'meal_actions.dart';
import 'plan_format.dart';
import 'planning_providers.dart';

/// Izbor razloga i napomene; [current] je obrok na tom mestu (ako ga ima).
/// Posle čuvanja poruka nudi "Poništi".
Future<void> chooseAway(
  BuildContext context,
  WidgetRef ref, {
  required MealPlan plan,
  required MealSlot slot,
  PlannedMeal? current,
}) async {
  final choice = await showDialog<(AwayReason, String?)>(
    context: context,
    builder: (context) => _AwayDialog(slot: slot, current: current),
  );
  if (choice == null || !context.mounted) return;
  final repo = ref.read(mealPlanRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  final (reason, note) = choice;
  String? entryId;
  final ok = await runMealEdit(
    context,
    () async => entryId = await repo.setAway(plan.id, slot, reason, note: note),
  );
  final id = entryId;
  if (!ok || id == null) return;
  final hadMeal = current != null && !current.isAway;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('${slot.type.label} je „${reason.label}“.'),
        action: current?.isAway ?? false
            ? null
            : SnackBarAction(
                label: 'Poništi',
                onPressed: () => unawaited(
                  (hadMeal ? repo.restoreMeal(id) : repo.removeMeal(id))
                      .catchError((Object _) {}),
                ),
              ),
      ),
    );
}

class _AwayDialog extends StatefulWidget {
  const _AwayDialog({required this.slot, this.current});

  final MealSlot slot;
  final PlannedMeal? current;

  @override
  State<_AwayDialog> createState() => _AwayDialogState();
}

class _AwayDialogState extends State<_AwayDialog> {
  late AwayReason? _reason = widget.current?.awayReason;
  late final _note = TextEditingController(text: widget.current?.awayNote);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.current;
    final title = current == null || current.isAway
        ? null
        : current.snapshot?.title;
    final reason = _reason;
    return AlertDialog(
      title: const Text('Obrok van kuće'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${dayLabel(widget.slot.date)} · ${widget.slot.type.label}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in AwayReason.values)
                  ChoiceChip(
                    label: Text(r.label),
                    selected: _reason == r,
                    onSelected: (_) => setState(() => _reason = r),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: maxAwayNoteLength,
              decoration: const InputDecoration(
                labelText: 'Napomena (nije obavezno)',
                border: OutlineInputBorder(),
              ),
            ),
            Text(
              title == null
                  ? 'Mesto je zauzeto i ništa se ne dodaje u nabavku.'
                  : '„$title“ izlazi iz nabavke; kupljeno ostaje. Jelo '
                        'možeš da vratiš.',
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
          onPressed: reason == null
              ? null
              : () => Navigator.pop(context, (reason, _note.text)),
          child: const Text('Sačuvaj'),
        ),
      ],
    );
  }
}
