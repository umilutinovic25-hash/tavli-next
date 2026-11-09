import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/account/account_header.dart';
import 'tavli_brand.dart';

/// Telefon prikazuje brend, a širi ekran naziv otvorene sekcije.
/// Avatar i postojeće akcije ostaju na istom mestu.
class TabAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TabAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final path =
        GoRouter.maybeOf(context)?.routeInformationProvider.value.uri.path ??
        '';
    final title = switch (path) {
      final p when p.startsWith('/plan') => 'Plan',
      final p when p.startsWith('/shopping') => 'Nabavka',
      final p when p.startsWith('/recipes') => 'Recepti',
      final p when p.startsWith('/pantry') => 'Ostava',
      _ => 'Tavli',
    };
    return AppBar(
      title: wide
          ? Text(title)
          : const FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: TavliBrand(),
            ),
      actionsPadding: const EdgeInsets.only(right: 12),
      automaticallyImplyLeading: false,
      actions: const [ProfileButton()],
    );
  }
}
