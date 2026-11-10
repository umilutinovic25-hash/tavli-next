import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'recipe_json_actions.dart';

/// Izbor načina dodavanja recepta.
Future<void> showAddRecipeSheet(BuildContext context) {
  void open(BuildContext sheetContext, String path) {
    Navigator.of(sheetContext).pop();
    context.go(path);
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Iz slike'),
              subtitle: const Text('Slikaj ili izaberi sliku recepta'),
              onTap: () => open(sheetContext, '/recipes/new/photo'),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Po nazivu jela'),
              subtitle: const Text('AI pravi recept za jelo koje upišeš'),
              onTap: () => open(sheetContext, '/recipes/new/name'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Ručno'),
              subtitle: const Text('Upiši recept sam'),
              onTap: () => open(sheetContext, '/recipes/new/manual'),
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('Iz JSON fajla'),
              subtitle: const Text(
                'Uvezi schema.org recepte iz druge aplikacije',
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(
                  importRecipeJson(
                    context,
                    ProviderScope.containerOf(context, listen: false),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
