import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/time_budget.dart';
import '../recipes/recipe_view.dart' show ReadableScroll;
import 'planning_providers.dart';

const _weekdayNames = [
  'Ponedeljak',
  'Utorak',
  'Sreda',
  'Četvrtak',
  'Petak',
  'Subota',
  'Nedelja',
];

/// Raspoloživo vreme po danu u nedelji: limit aktivnog rada po obroku i
/// prozor za kuvanje. Važi za sve planove domaćinstva.
class TimeBudgetScreen extends ConsumerWidget {
  const TimeBudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(dayBudgetsProvider).value ?? const [];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Vreme po danu')),
      body: ReadableScroll(
        children: [
          Text(
            'Koliko aktivnog rada staje u jedan obrok i kada možeš da '
            'kuvaš. Plan pokazuje jela koja ne staju ili nemaju potvrđeno '
            'vreme.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (var day = 1; day <= 7; day++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_weekdayNames[day - 1]),
              subtitle: Text(_summary(budgetFor(budgets, day))),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _edit(context, ref, day, budgetFor(budgets, day)),
            ),
        ],
      ),
    );
  }

  static String _summary(DayBudget? b) {
    if (b == null || b.isEmpty) return 'Bez ograničenja';
    return [
      if (b.maxActiveMinutes case final m?) 'do $m min aktivnog rada',
      if (b.windowMinutes != null)
        'kuvanje ${clockLabel(b.windowStart!)}–${clockLabel(b.windowEnd!)}',
    ].join(' · ');
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    int day,
    DayBudget? current,
  ) async {
    final result = await showDialog<DayBudget>(
      context: context,
      builder: (context) => _DayDialog(day: day, current: current),
    );
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(timeBudgetRepositoryProvider).save(result);
    } on Object {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Vreme nije sačuvano. Pokušaj ponovo.')),
        );
    }
  }
}

class _DayDialog extends StatefulWidget {
  const _DayDialog({required this.day, this.current});

  final int day;
  final DayBudget? current;

  @override
  State<_DayDialog> createState() => _DayDialogState();
}

class _DayDialogState extends State<_DayDialog> {
  late final _limit = TextEditingController(
    text: widget.current?.maxActiveMinutes?.toString() ?? '',
  );
  late final _start = TextEditingController(
    text: switch (widget.current?.windowStart) {
      final m? => clockLabel(m),
      null => '',
    },
  );
  late final _end = TextEditingController(
    text: switch (widget.current?.windowEnd) {
      final m? => clockLabel(m),
      null => '',
    },
  );
  String? _error;

  @override
  void dispose() {
    _limit.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _save() {
    final limitText = _limit.text.trim();
    final limit = limitText.isEmpty ? null : int.tryParse(limitText);
    final startText = _start.text.trim();
    final endText = _end.text.trim();
    final start = startText.isEmpty ? null : parseClock(startText);
    final end = endText.isEmpty ? null : parseClock(endText);
    String? error;
    if (limitText.isNotEmpty &&
        (limit == null || limit <= 0 || limit > maxTimeMinutes)) {
      error = 'Limit je broj minuta veći od nule.';
    } else if ((startText.isNotEmpty && start == null) ||
        (endText.isNotEmpty && end == null)) {
      error = 'Vreme upiši kao 18:00.';
    } else if ((start == null) != (end == null)) {
      error = 'Upiši i početak i kraj prozora.';
    } else if (start != null && end != null && end <= start) {
      error = 'Kraj prozora mora biti posle početka.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(
      DayBudget(
        weekday: widget.day,
        maxActiveMinutes: limit,
        windowStart: start,
        windowEnd: end,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_weekdayNames[widget.day - 1]),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _limit,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Najviše aktivnog rada po obroku (min)',
                hintText: 'prazno = bez ograničenja',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _start,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      labelText: 'Kuvam od',
                      hintText: '18:00',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _end,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      labelText: 'do',
                      hintText: '18:45',
                    ),
                  ),
                ),
              ],
            ),
            if (_error case final e?) ...[
              const SizedBox(height: 8),
              Text(
                e,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Otkaži'),
        ),
        FilledButton(onPressed: _save, child: const Text('Sačuvaj')),
      ],
    );
  }
}
