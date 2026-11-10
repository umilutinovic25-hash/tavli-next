import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/household.dart';
import '../../domain/household_invite.dart';
import 'household_actions.dart';
import 'invite_code_sheet.dart';

/// Vlasnik: „Pozovi člana“ i aktivne pozivnice sa poništavanjem.
class InvitesSection extends ConsumerStatefulWidget {
  const InvitesSection({super.key});

  @override
  ConsumerState<InvitesSection> createState() => _InvitesSectionState();
}

class _InvitesSectionState extends ConsumerState<InvitesSection> {
  List<HouseholdInvite> _invites = const [];
  var _creating = false;

  @override
  void initState() {
    super.initState();
    // Lista stiže kad stigne; ekran se ne blokira dok čeka mrežu.
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final invites = await ref.read(householdActionsProvider).loadInvites();
    if (mounted && invites != null) setState(() => _invites = invites);
  }

  void _show(String message) {
    if (message.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    final outcome = await ref.read(householdActionsProvider).createInvite();
    if (!mounted) return;
    setState(() => _creating = false);
    if (outcome case HouseholdDone(:final code?)) {
      await _reload();
      if (!mounted) return;
      final invite = _invites.where((i) => i.code == code).firstOrNull;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => InviteCodeSheet(
          code: code,
          expiresAt: invite?.expiresAt,
          usesLeft: invite?.usesLeft,
        ),
      );
    } else {
      _show(outcome.message);
    }
  }

  Future<void> _revoke(HouseholdInvite invite) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Poništiti pozivnicu?'),
        content: const Text('Kod više neće moći da se iskoristi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Otkaži'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Poništi'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final outcome = await ref
        .read(householdActionsProvider)
        .revokeInvite(invite);
    await _reload();
    _show(outcome.message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            onPressed: _creating ? null : _create,
            icon: _creating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Pozovi člana'),
          ),
        ),
        const SizedBox(height: 16),
        Text('Aktivne pozivnice', style: theme.textTheme.titleMedium),
        if (_invites.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nema aktivnih pozivnica.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          for (final invite in _invites)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(formatInviteCode(invite.code)),
              subtitle: Text(
                'Važi do ${inviteDate(invite.expiresAt)} · '
                '${usesLeftText(invite.usesLeft)}',
              ),
              trailing: TextButton(
                onPressed: () => _revoke(invite),
                child: const Text('Poništi'),
              ),
            ),
      ],
    );
  }
}
