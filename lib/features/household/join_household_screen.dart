import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/household_invite.dart';
import 'household_actions.dart';

/// Profil → Domaćinstvo → Pridruži se kodom.
class JoinHouseholdScreen extends ConsumerStatefulWidget {
  const JoinHouseholdScreen({super.key});

  @override
  ConsumerState<JoinHouseholdScreen> createState() =>
      _JoinHouseholdScreenState();
}

class _JoinHouseholdScreenState extends ConsumerState<JoinHouseholdScreen> {
  final _code = TextEditingController();
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _ready => normalizeInviteCode(_code.text).length == 8 && !_busy;

  Future<void> _join() async {
    if (!_ready) return;
    setState(() => _busy = true);
    final outcome = await ref.read(householdActionsProvider).join(_code.text);
    if (!mounted) return;
    setState(() => _busy = false);
    final messenger = ScaffoldMessenger.of(context);
    if (outcome is HouseholdDone) {
      // Ruter se upravo osvežio zbog novog naloga; ide se na tačnu adresu.
      context.go('/profile/household');
    }
    if (outcome.message.isNotEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(outcome.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pridruži se kodom')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _code,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Unesi kod od 8 znakova',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _join(),
          ),
          const SizedBox(height: 16),
          Text(
            'Posle pridruživanja vidiš plan, nabavku, recepte i ostavu ovog '
            'domaćinstva. Tvoji dosadašnji podaci ostaju sačuvani u tvom '
            'domaćinstvu.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: _ready ? _join : null,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.group_add_outlined),
              label: const Text('Pridruži se'),
            ),
          ),
        ],
      ),
    );
  }
}
