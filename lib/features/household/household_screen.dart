import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../account/auth_controller.dart';
import '../../domain/account.dart';
import '../../domain/household.dart';
import '../../providers.dart';
import 'household_actions.dart';
import 'invites_section.dart';
import 'member_tile.dart';

/// Profil → Domaćinstvo: naziv, uloga, članovi, pozivnice i radnje.
class HouseholdScreen extends ConsumerStatefulWidget {
  const HouseholdScreen({super.key});

  @override
  ConsumerState<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends ConsumerState<HouseholdScreen> {
  var _stale = false;

  @override
  void initState() {
    super.initState();
    // Lista iz keša se vidi odmah; server osvežava u pozadini.
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    await ref.read(authControllerProvider.notifier).refreshAccount();
    final ok = await ref.read(householdActionsProvider).reloadMembers();
    if (mounted) setState(() => _stale = !ok);
  }

  void _show(String message) {
    if (message.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onMemberAction(HouseholdMember m, MemberAction action) async {
    final name = memberName(m);
    switch (action) {
      case MemberAction.remove:
        final ok = await _confirm(
          title: 'Ukloniti $name iz domaćinstva?',
          body: 'Više neće videti podatke ovog domaćinstva.',
          action: 'Ukloni iz domaćinstva',
        );
        if (!ok) return;
        await _finish(await ref.read(householdActionsProvider).removeMember(m));
      case MemberAction.transfer:
        final ok = await _confirm(
          title: 'Preneti vlasništvo na $name?',
          body:
              'Ti postaješ član i više ne možeš da pozivaš ni uklanjaš '
              'članove.',
          action: 'Prenesi vlasništvo',
        );
        if (!ok) return;
        await _finish(
          await ref.read(householdActionsProvider).transferOwnership(m),
        );
    }
  }

  Future<void> _leave() async {
    final ok = await _confirm(
      title: 'Napustiti domaćinstvo?',
      body: 'Vratićeš se u svoje domaćinstvo i više nećeš videti ove podatke.',
      action: 'Napusti domaćinstvo',
    );
    if (!ok) return;
    await _finish(await ref.read(householdActionsProvider).leave());
  }

  /// Poruka ishoda; posle odbijanja lista se usklađuje sa serverom.
  Future<void> _finish(HouseholdOutcome outcome) async {
    _show(outcome.message);
    if (outcome is HouseholdFailed) await _refresh();
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Otkaži'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final account = switch (ref.watch(authControllerProvider)) {
      SignedIn(:final account) => account,
      _ => null,
    };
    final members = ref.watch(householdMembersProvider).value ?? const [];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Domaćinstvo')),
      body: account == null
          ? const SizedBox.shrink()
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                children: [
                  _Header(account: account),
                  const SizedBox(height: 8),
                  Text('Članovi', style: theme.textTheme.titleMedium),
                  if (_stale)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Prikazano je poslednje poznato stanje.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  for (final m in members)
                    MemberTile(
                      member: m,
                      isSelf: m.userId == account.userId,
                      canManage: account.role == 'owner',
                      onAction: (action) => _onMemberAction(m, action),
                    ),
                  const SizedBox(height: 16),
                  if (account.role == 'owner') ...[
                    const InvitesSection(),
                    const SizedBox(height: 16),
                  ],
                  if (account.role != 'owner')
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        onPressed: _leave,
                        icon: const Icon(Icons.logout),
                        label: const Text('Napusti domaćinstvo'),
                      ),
                    )
                  else if (members.length > 1)
                    Text(
                      'Pre napuštanja prenesi vlasništvo drugom članu.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/profile/household/join'),
                      icon: const Icon(Icons.vpn_key_outlined),
                      label: const Text('Pridruži se kodom'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.home_outlined),
      title: Text(account.householdName, style: theme.textTheme.titleLarge),
      subtitle: Text(roleLabel(account.role)),
    );
  }
}

/// "Vlasnik" ili "Član" za vrednost uloge iz baze.
String roleLabel(String role) => role == 'owner' ? 'Vlasnik' : 'Član';
