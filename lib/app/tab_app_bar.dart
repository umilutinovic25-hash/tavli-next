import 'package:flutter/material.dart';

import '../features/account/account_header.dart';
import '../features/use_first/use_first_screen.dart';

/// Gornja traka glavnih ekrana tabova: naziv aplikacije i avatar. Koji je
/// tab izabran vidi se u donjim tabovima, odnosno u bočnom meniju.
class TabAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TabAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    title: const FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text('Tavli'),
    ),
    automaticallyImplyLeading: false,
    actions: const [UseFirstButton(), ProfileButton()],
  );
}
