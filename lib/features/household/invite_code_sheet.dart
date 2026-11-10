import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;

import '../../domain/household.dart';

/// Sistemski meni za deljenje teksta; u testovima se zamenjuje.
typedef ShareText = Future<void> Function(String text, {Rect? origin});

final shareTextProvider = Provider<ShareText>(
  (ref) =>
      (text, {origin}) async => SharePlus.instance.share(
        ShareParams(text: text, sharePositionOrigin: origin),
      ),
);

/// Kod nove pozivnice: krupno, sa rokom i brojem upotreba; kopiraj i podeli.
class InviteCodeSheet extends ConsumerWidget {
  const InviteCodeSheet({
    super.key,
    required this.code,
    required this.expiresAt,
    required this.usesLeft,
  });

  final String code;
  final DateTime? expiresAt;
  final int? usesLeft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Kod za pozivanje', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                formatInviteCode(code),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (expiresAt case final at?)
              Text(
                'Važi do ${inviteDate(at)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            if (usesLeft case final n?)
              Text(
                usesLeftText(n),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Kopiraj kod'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Kod je kopiran.')),
                    );
                  },
                ),
                Builder(
                  builder: (button) => FilledButton.icon(
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Podeli'),
                    onPressed: () async {
                      final box = button.findRenderObject() as RenderBox?;
                      final origin = box == null
                          ? null
                          : box.localToGlobal(Offset.zero) & box.size;
                      await ref.read(shareTextProvider)(
                        inviteShareText(code),
                        origin: origin,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
