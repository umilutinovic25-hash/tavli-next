import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/meal_plan.dart';
import '../../domain/recipe_format.dart';
import '../../domain/time_budget.dart';
import '../recipes/ai_preview.dart';
import '../recipes/recipe_view.dart';
import 'meal_actions.dart';
import 'plan_format.dart';
import 'plan_generation.dart';
import 'planning_providers.dart';
import 'time_check_note.dart';

/// Drugi i treći korak: napredak, predlog po danima i odobrenje. Ništa se
/// ne čuva dok osoba ne izabere "Sačuvaj plan" (ili izričito nepotpun plan).
class PlanPreviewScreen extends ConsumerWidget {
  const PlanPreviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(planGenerationProvider);
    final controller = ref.read(planGenerationProvider.notifier);
    final draft = state.draft;
    // Ponovni predlog postojećeg plana: nema podešavanja, prikazuju se
    // samo mesta koja se menjaju, uz jelo koje zamenjuju.
    final isChange = draft?.base != null;
    final current = isChange
        ? {
            for (final m
                in ref.watch(plannedMealsProvider(draft!.base!.planId)).value ??
                    const <PlannedMeal>[])
              m.slot: m,
          }
        : const <MealSlot, PlannedMeal>{};

    Future<void> discard() async {
      final router = GoRouter.of(context);
      if (await confirmDiscardPlan(context)) {
        controller.discard();
        router.go('/plan');
      }
    }

    void backToSetup() =>
        isChange ? unawaited(discard()) : context.go('/plan/new');

    if (draft == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Predlog plana')),
        body: ReadableScroll(
          children: [
            const Text('Nema otvorenog predloga.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: backToSetup,
              child: const Text('Nazad na podešavanje'),
            ),
          ],
        ),
      );
    }

    Future<void> save({bool partial = false}) async {
      final messenger = ScaffoldMessenger.of(context);
      final router = GoRouter.of(context);
      final id = await controller.save(partial: partial);
      if (id == null) return;
      router.go('/plan');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              isChange
                  ? 'Izmene su sačuvane.'
                  : partial
                  ? 'Nepotpun plan je sačuvan.'
                  : 'Plan je sačuvan.',
            ),
          ),
        );
    }

    /// Zamena jednog jela pre čuvanja: AI predlog ili recept iz biblioteke.
    Future<void> replace(MealSlot slot) async {
      final choice = await pickReplacementSource(context);
      if (choice == null || !context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final replaced = switch (choice) {
        ReplacementSource.ai => await controller.replaceSlot(slot),
        ReplacementSource.library => await () async {
          final recipe = await pickLibraryRecipe(context, ref);
          if (recipe == null) return false;
          controller.useRecipe(slot, recipe);
          return true;
        }(),
      };
      if (!replaced) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Jelo je zamenjeno.')));
    }

    final request = draft.request;
    final total = request.slots.length;
    final ready = draft.readySlots.length;
    final empty = total - ready;
    final theme = Theme.of(context);
    final phase = state.phase;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) backToSetup();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isChange ? 'Pregled izmena' : 'Predlog plana'),
          leading: BackButton(onPressed: backToSetup),
        ),
        body: ReadableScroll(
          children: [
            Text(rangeLabel(request.range), style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${mealsCount(total)} · ${servingsLabel(request.servings)} '
              'po obroku · predlog još nije sačuvan',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (phase == GenerationPhase.generating) ...[
              LinearProgressIndicator(
                value: total == 0 ? null : ready / total,
                semanticsLabel: 'Napredak predloga',
              ),
              const SizedBox(height: 8),
              Text('Pripremam plan… Pripremljeno $ready od $total obroka.'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: controller.cancel,
                  child: const Text('Prekini'),
                ),
              ),
            ],
            if (phase == GenerationPhase.failed)
              AiErrorBox(
                '${state.error ?? 'Predlog nije završen.'} '
                'Gotovo je $ready od $total; nastavak pravi samo ono što '
                'nedostaje.',
                actions: [
                  TextButton(
                    onPressed: () => unawaited(controller.generate()),
                    child: const Text('Nastavi'),
                  ),
                ],
              ),
            if (phase == GenerationPhase.cancelled)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Prekinuto. Gotovo je $ready od $total; '
                    'možeš da nastaviš kad želiš.',
                  ),
                ),
              ),
            if (state.error != null &&
                phase != GenerationPhase.failed &&
                phase != GenerationPhase.generating) ...[
              const SizedBox(height: 8),
              Text(
                state.error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            for (final day in request.range.days)
              if (request.slots.any((s) => s.date == day)) ...[
                const SizedBox(height: 12),
                Text(dayLabel(day), style: theme.textTheme.titleMedium),
                for (final slot in request.slots.where((s) => s.date == day))
                  _SlotTile(
                    draft: draft,
                    slot: slot,
                    timeCheck: mealTimeCheck(
                      draft.snapshotFor(slot),
                      slot.date,
                      ref.watch(dayBudgetsProvider).value ?? const [],
                    ),
                    previous: current[slot]?.snapshot?.title,
                    replacing: state.replacing == slot,
                    onReplace: state.busy
                        ? null
                        : () => unawaited(replace(slot)),
                    onCancelReplace: controller.cancel,
                  ),
              ],
            const SizedBox(height: 24),
            ..._actions(
              phase: phase,
              complete: draft.isComplete,
              ready: ready,
              empty: empty,
              onSave: () => unawaited(save()),
              onSavePartial: () => unawaited(save(partial: true)),
              onContinue: () => unawaited(controller.generate()),
              onDiscard: () => unawaited(discard()),
              onBack: isChange ? null : backToSetup,
              saveLabel: isChange ? 'Prihvati' : 'Sačuvaj plan',
              replacing: state.replacing != null,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions({
    required GenerationPhase phase,
    required bool complete,
    required int ready,
    required int empty,
    required VoidCallback onSave,
    required VoidCallback onSavePartial,
    required VoidCallback onContinue,
    required VoidCallback onDiscard,
    required VoidCallback? onBack,
    required String saveLabel,
    required bool replacing,
  }) {
    final saving = phase == GenerationPhase.saving || replacing;
    if (phase == GenerationPhase.generating) return const [];
    return [
      if (complete)
        FilledButton.icon(
          onPressed: saving ? null : onSave,
          icon: const Icon(Icons.check),
          label: Text(saveLabel),
        )
      else ...[
        FilledButton.icon(
          onPressed: saving ? null : onContinue,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Nastavi generisanje'),
        ),
        if (ready > 0) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: saving ? null : onSavePartial,
            child: const Text('Sačuvaj nepotpun plan'),
          ),
          const SizedBox(height: 4),
          Text(
            '${mealsCount(empty)} ostaje prazno.',
            textAlign: TextAlign.center,
          ),
        ],
      ],
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          if (onBack != null)
            TextButton(
              onPressed: saving ? null : onBack,
              child: const Text('Promeni izbore'),
            ),
          TextButton(
            onPressed: saving ? null : onDiscard,
            child: const Text('Odbaci'),
          ),
        ],
      ),
    ];
  }
}

/// Pita pre odbacivanja nesačuvanog predloga.
Future<bool> confirmDiscardPlan(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Odbaciti predlog?'),
        content: const Text(
          'Predlog nije sačuvan. Sačuvani planovi, recepti i nabavka '
          'ostaju kakvi su bili.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nazad'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Odbaci'),
          ),
        ],
      ),
    ) ??
    false;

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.draft,
    required this.slot,
    this.previous,
    this.replacing = false,
    this.onReplace,
    this.onCancelReplace,
    this.timeCheck,
  });

  final TimeCheck? timeCheck;
  final PlanDraft draft;
  final MealSlot slot;

  /// AI upravo traži drugo jelo za ovo mesto.
  final bool replacing;

  /// "Zameni jelo"; null dok traje generisanje, čuvanje ili druga zamena.
  final VoidCallback? onReplace;
  final VoidCallback? onCancelReplace;

  /// Jelo koje predlog zamenjuje (pregled izmena).
  final String? previous;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final proposal = draft.proposals[slot];
    final snapshot = draft.snapshotFor(slot);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final label = Text(slot.type.label, style: theme.textTheme.labelLarge);
    if (proposal == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: label,
        subtitle: Text('Nije planirano', style: muted),
      );
    }
    if (replacing) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: label,
        subtitle: Text('${proposal.title}\nTražim drugo jelo…', style: muted),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            TextButton(
              onPressed: onCancelReplace,
              child: const Text('Prekini'),
            ),
          ],
        ),
      );
    }
    final replace = IconButton(
      onPressed: onReplace,
      icon: const Icon(Icons.swap_horiz),
      tooltip: 'Zameni jelo',
    );
    final origin = [
      proposal.isNew ? 'Nov recept' : 'Iz mojih recepata',
      if (previous case final p?) 'umesto: $p',
    ].join(' · ');
    if (snapshot == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: label,
        subtitle: Text(
          '${proposal.title}\n$origin · sastojci još nisu spremni',
        ),
        isThreeLine: true,
        trailing: replace,
      );
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: label,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${proposal.title}\n$origin', style: muted),
          TimeCheckNote(timeCheck),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [replace, const Icon(Icons.expand_more)],
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        Text(
          'Sastojci za ${servingsLabel(snapshot.baseServings)}'
          '${snapshot.prepMinutes == null ? '' : ' · ${snapshot.prepMinutes} min'}',
          style: theme.textTheme.labelLarge,
        ),
        for (final i in snapshot.ingredients) Text('• ${ingredientLine(i)}'),
      ],
    );
  }
}
