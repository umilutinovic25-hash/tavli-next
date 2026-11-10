import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ids.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_schema_org.dart';
import 'recipe_files.dart' show recipeFileName;
import 'recipe_providers.dart';

void _snack(ScaffoldMessengerState messenger, String text) => messenger
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

/// Izvozi recept kao schema.org/Recipe JSON.
Future<void> exportRecipeJson(
  BuildContext context,
  WidgetRef ref,
  Recipe recipe,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  try {
    final saved = await ref
        .read(recipeFilesProvider)
        .saveJson(
          recipeFileName(recipe.title),
          encodeSchemaOrgRecipes([recipe]),
          origin: origin,
        );
    if (saved) _snack(messenger, 'Recept je izvezen.');
  } on Object {
    _snack(messenger, 'Izvoz nije uspeo. Pokušaj ponovo.');
  }
}

/// Uvozi recepte iz schema.org JSON fajla i prikazuje izveštaj.
Future<void> importRecipeJson(
  BuildContext context,
  ProviderContainer container,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final SchemaOrgImport result;
  try {
    final text = await container.read(recipeFilesProvider).pickJson();
    if (text == null) return;
    final repo = container.read(recipeRepositoryProvider);
    result = parseSchemaOrgRecipes(
      text,
      existing: await repo.getAll(),
      newId: newId,
      now: container.read(clockProvider)(),
    );
    for (final r in result.recipes) {
      await repo.create(r);
    }
  } on FormatException {
    _snack(messenger, 'Fajl nije ispravan JSON recepta.');
    return;
  } on Object {
    _snack(messenger, 'Uvoz nije uspeo. Pokušaj ponovo.');
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _ImportReport(result),
  );
}

class _ImportReport extends StatelessWidget {
  const _ImportReport(this.result);

  final SchemaOrgImport result;

  @override
  Widget build(BuildContext context) {
    final count = result.recipes.length;
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Uvoz recepata'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count == 0
                  ? 'Nijedan recept nije uvezen.'
                  : 'Uvezeno recepata: $count',
            ),
            for (final r in result.recipes) Text('• ${r.title}'),
            if (result.skipped.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Preskočeno', style: theme.textTheme.titleSmall),
              for (final s in result.skipped)
                Text('• ${s.title ?? 'Recept bez naziva'} — ${s.reason}'),
            ],
            if (result.ignoredFields.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Nije preneto', style: theme.textTheme.titleSmall),
              Text(result.ignoredFields.join(', ')),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('U redu'),
        ),
      ],
    );
  }
}
