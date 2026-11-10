import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../account/account_header.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        // Otvoren direktnom adresom nema kuda nazad, pa vodi na Plan.
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/plan'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          const AccountHeader(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Izgled'),
            subtitle: const Text('Boje, tema i svetli ili tamni režim'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/profile/appearance'),
          ),
          ListTile(
            leading: const Icon(Icons.restaurant_menu_outlined),
            title: const Text('Preferencije'),
            subtitle: const Text('Ishrana, namirnice koje ne volimo, alergije'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/profile/preferences'),
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('AI ključevi'),
            subtitle: const Text('Gemini, Groq, OpenRouter'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/profile/ai-keys'),
          ),
          if (kDebugMode)
            ListTile(
              leading: const Icon(Icons.animation),
              title: const Text('Animacije'),
              subtitle: const Text('Pregled animacija (samo za razvoj)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/profile/animations'),
            ),
        ],
      ),
    );
  }
}
