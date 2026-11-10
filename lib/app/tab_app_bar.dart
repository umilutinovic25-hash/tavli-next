import 'package:flutter/material.dart';

import '../features/account/account_header.dart';
import 'tavli_brand.dart';

/// Gornja traka glavnih ekrana tabova: naziv aplikacije i avatar. Koji je
/// tab izabran vidi se u donjim tabovima, odnosno u bočnom meniju.
class TabAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TabAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    title: const TavliBrand(),
    automaticallyImplyLeading: false,
    actions: const [ProfileButton()],
  );
}
