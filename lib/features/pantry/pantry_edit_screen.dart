import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pantry_form_screen.dart';
import 'pantry_providers.dart';

class PantryEditScreen extends ConsumerWidget {
  const PantryEditScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(pantryItemsProvider)
      .when(
        loading: () => Scaffold(
          appBar: AppBar(title: const Text('Izmeni namirnicu')),
          body: const Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => Scaffold(
          appBar: AppBar(title: const Text('Izmeni namirnicu')),
          body: Center(
            child: OutlinedButton(
              onPressed: () => ref.invalidate(pantryItemsProvider),
              child: const Text('Pokušaj ponovo'),
            ),
          ),
        ),
        data: (items) {
          for (final item in items) {
            if (item.id == id) {
              return PantryFormScreen(key: ValueKey(id), item: item);
            }
          }
          return Scaffold(
            appBar: AppBar(title: const Text('Izmeni namirnicu')),
            body: const Center(child: Text('Namirnica nije pronađena.')),
          );
        },
      );
}
