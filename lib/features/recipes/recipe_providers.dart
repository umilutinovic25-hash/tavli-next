import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../account/auth_controller.dart';
import '../../data/photo_resize.dart';
import '../../data/recipe_photo_store.dart';
import '../../data/recipe_repository.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_version.dart';
import '../../providers.dart';
import 'photo_picker.dart';
import 'recipe_files.dart';

final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final recipePhotoStoreProvider = Provider<RecipePhotoStore>(
  (ref) => FileRecipePhotoStore(getApplicationDocumentsDirectory),
);

/// Recepti prijavljenog naloga. Bez naloga (ne bi trebalo da se desi iza
/// prijave) repozitorijum ne vidi ništa.
final recipeRepositoryProvider = Provider<RecipeRepository>(
  (ref) => RecipeRepository(
    ref.watch(databaseProvider),
    ref.watch(recipePhotoStoreProvider),
    writer: ref.watch(syncedWriterProvider),
    scope: ref.watch(accountScopeProvider) ?? noAccountScope,
    clock: ref.watch(clockProvider),
  ),
);

final photoPickerProvider = Provider<PhotoPicker>((ref) => ImagePhotoPicker());

final recipeFilesProvider = Provider<RecipeFiles>((ref) => SystemRecipeFiles());

/// Smanjuje sliku van glavnog thread-a.
final photoResizerProvider = Provider<Future<Uint8List> Function(Uint8List)>(
  (ref) =>
      (bytes) => compute(downscaleToJpeg, bytes),
);

final recipesProvider = StreamProvider.autoDispose<List<Recipe>>(
  (ref) => ref.watch(recipeRepositoryProvider).watchAll(),
);

final recipeProvider = StreamProvider.autoDispose.family<Recipe?, String>(
  (ref, id) => ref.watch(recipeRepositoryProvider).watch(id),
);

final recipeVersionsProvider = StreamProvider.autoDispose
    .family<List<RecipeVersion>, String>(
      (ref, id) => ref.watch(recipeRepositoryProvider).watchVersions(id),
    );

final recipePhotoFileProvider = FutureProvider.autoDispose
    .family<File?, String>(
      (ref, path) => ref.watch(recipePhotoStoreProvider).file(path),
    );

/// Upit za pretragu; deli se između liste i podeljenog prikaza.
class RecipeSearch extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final recipeSearchProvider = NotifierProvider<RecipeSearch, String>(
  RecipeSearch.new,
);
