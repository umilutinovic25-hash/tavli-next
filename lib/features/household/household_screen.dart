import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/auth_controller.dart';
import '../../domain/account.dart';
import 'invites_section.dart';

/// Profil → Domaćinstvo: naziv, uloga, članovi, pozivnice i radnje.
class HouseholdScreen extends ConsumerWidget {
  const HouseholdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = switch (ref.watch(authControllerProvider)) {
      SignedIn(:final account) => account,
      _ => null,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Domaćinstvo')),
      body: account == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _Header(account: account),
                const SizedBox(height: 8),
                if (account.role == 'owner') ...[
                  const InvitesSection(),
                  const SizedBox(height: 16),
                ],
              ],
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
