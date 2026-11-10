import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/animations/photo_scan.dart';
import '../../domain/quantity_review.dart';
import '../../domain/recipe.dart';
import 'recipe_view.dart';

/// Poredi isti dokument koji je AI pročitao i otvoreni, još nesačuvani recept.
class PhotoRecipeComparison extends StatelessWidget {
  const PhotoRecipeComparison({
    super.key,
    required this.recipe,
    required this.photo,
    this.onEditIngredient,
  });

  final Recipe recipe;
  final Uint8List photo;
  final ValueChanged<int>? onEditIngredient;

  Widget _original(BuildContext context, {required double height}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Originalna fotografija',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      PhotoScan(
        scanning: false,
        height: height,
        ingredients: [for (final i in recipe.ingredients) i.name],
        photo: Image.memory(
          photo,
          fit: BoxFit.contain,
          semanticLabel: 'Originalna fotografija recepta',
          errorBuilder: (_, _, _) =>
              const Center(child: Text('Fotografija nije dostupna.')),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.zoom_in),
        label: const Text('Uvećaj fotografiju'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _OriginalPhotoViewer(photo: photo),
        ),
      ),
    ],
  );

  Widget _recognized(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Prepoznati recept', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
        'Uporedi sastojke i korake sa fotografijom. Nejasne količine ostaju za proveru.',
      ),
      if (recipe.ingredients.any(
        (i) => quantityReviewIssue(i) == QuantityReviewIssue.invalid,
      )) ...[
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            'Ispravi neispravne količine ili ih ostavi praznim pre čuvanja.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
      const SizedBox(height: 16),
      RecipeView(
        recipe,
        showTitle: true,
        reviewQuantities: true,
        onEditIngredient: onEditIngredient,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 900) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Row(
              key: const ValueKey('photo-comparison-wide'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ReadableScroll(
                    children: [_original(context, height: 420)],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: ReadableScroll(children: [_recognized(context)]),
                ),
              ],
            ),
          ),
        );
      }
      return ReadableScroll(
        key: const ValueKey('photo-comparison-stacked'),
        children: [
          _original(context, height: 260),
          const SizedBox(height: 24),
          _recognized(context),
        ],
      );
    },
  );
}

class _OriginalPhotoViewer extends StatefulWidget {
  const _OriginalPhotoViewer({required this.photo});
  final Uint8List photo;
  @override
  State<_OriginalPhotoViewer> createState() => _OriginalPhotoViewerState();
}

class _OriginalPhotoViewerState extends State<_OriginalPhotoViewer> {
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom() {
    final scale = (_transform.value.getMaxScaleOnAxis() * 1.5).clamp(1.0, 8.0);
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Originalna fotografija'),
        leading: CloseButton(onPressed: () => Navigator.pop(context)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 1,
                maxScale: 8,
                trackpadScrollCausesScale: true,
                child: SizedBox.expand(
                  child: Image.memory(
                    widget.photo,
                    fit: BoxFit.contain,
                    semanticLabel: 'Originalna fotografija recepta',
                    errorBuilder: (_, _, _) =>
                        const Center(child: Text('Fotografija nije dostupna.')),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _zoom,
                    icon: const Icon(Icons.zoom_in),
                    label: const Text('Uvećaj'),
                  ),
                  TextButton(
                    onPressed: () => _transform.value = Matrix4.identity(),
                    child: const Text('Cela fotografija'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
