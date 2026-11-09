import 'package:flutter/material.dart';

import 'animations/content_reveal.dart';
import 'tab_app_bar.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return EmptyStateScreen(
      art: Icon(icon, size: 56, color: colors.primary),
      title: 'Uskoro',
    );
  }
}

/// Tab bez sadržaja: animacija (ili ikona), naslov i objašnjenje.
class EmptyStateScreen extends StatelessWidget {
  const EmptyStateScreen({
    super.key,
    required this.art,
    required this.title,
    this.body,
    this.action,
  });

  final Widget art;
  final String title;
  final String? body;

  /// Glavna sledeća akcija (npr. "Napravi plan").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const TabAppBar(),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ContentReveal(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: art,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  if (body case final body?) ...[
                    const SizedBox(height: 8),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (action case final action?) ...[
                    const SizedBox(height: 24),
                    action,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
