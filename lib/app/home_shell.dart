import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/account/sync_banner.dart';
import 'router.dart';
import 'tavli_brand.dart';

/// Donji tabovi na telefonu, bočni meni na širem ekranu (macOS, tablet).
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  void _select(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 20;
    if (width >= 720) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: width >= 1000,
              labelType: width >= 1000
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _select,
              leading: Padding(
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 32),
                child: TavliBrand(compact: width < 1000),
              ),
              groupAlignment: -0.8,
              destinations: [
                for (final t in tabs)
                  NavigationRailDestination(
                    icon: Icon(t.icon),
                    selectedIcon: Icon(t.selectedIcon),
                    label: Text(t.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  const SyncBanner(),
                  Expanded(child: shell),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final navigation = NavigationBar(
      height: largeText ? 64 : 80,
      labelBehavior: largeText
          ? NavigationDestinationLabelBehavior.alwaysHide
          : NavigationDestinationLabelBehavior.alwaysShow,
      selectedIndex: shell.currentIndex,
      onDestinationSelected: _select,
      destinations: [
        for (final t in tabs)
          NavigationDestination(
            icon: Icon(t.icon),
            selectedIcon: Icon(t.selectedIcon),
            label: t.label,
          ),
      ],
    );
    return Scaffold(
      body: Column(
        children: [
          const SyncBanner(),
          Expanded(child: shell),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: largeText
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MediaQuery.removePadding(
                        context: context,
                        removeBottom: true,
                        child: navigation,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: ExcludeSemantics(
                          child: Text(
                            tabs[shell.currentIndex].label,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : navigation,
      ),
    );
  }
}
