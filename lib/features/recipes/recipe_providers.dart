import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../account/auth_controller.dart';
import '../../ai/embedding_client.dart';
import '../../ai/recipe_semantic_search.dart';
import '../../data/photo_resize.dart';
import '../../data/recipe_embedding_repository.dart';
import '../../data/recipe_photo_store.dart';
import '../../data/recipe_rating_repository.dart';
import '../../data/recipe_repository.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_rating.dart';
import '../../domain/recipe_search.dart';
import '../../domain/recipe_version.dart';
import '../../providers.dart';
import 'photo_picker.dart';

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

final recipeEmbeddingRepositoryProvider = Provider<RecipeEmbeddingRepository>(
  (ref) => RecipeEmbeddingRepository(
    ref.watch(databaseProvider),
    (ref.watch(accountScopeProvider) ?? noAccountScope).householdId,
  ),
);

final recipeSemanticSearchServiceProvider =
    Provider<RecipeSemanticSearchService?>((ref) {
      final gateway = ref.watch(gatewayChatClientProvider);
      if (gateway == null) return null;
      return RecipeSemanticSearchService(
        client: OpenAIEmbeddingClient(gateway),
        embeddings: ref.watch(recipeEmbeddingRepositoryProvider),
      );
    });

final recipeRatingRepositoryProvider = Provider<RecipeRatingRepository>(
  (ref) => RecipeRatingRepository(
    ref.watch(databaseProvider),
    writer: ref.watch(syncedWriterProvider),
    scope: ref.watch(accountScopeProvider) ?? noAccountScope,
    clock: ref.watch(clockProvider),
  ),
);

final photoPickerProvider = Provider<PhotoPicker>((ref) => ImagePhotoPicker());

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

final recipeMyRatingProvider = StreamProvider.autoDispose
    .family<RecipeRating?, String>(
      (ref, recipeId) =>
          ref.watch(recipeRatingRepositoryProvider).watchMyRating(recipeId),
    );

final recipeRatingSummaryProvider = StreamProvider.autoDispose
    .family<RecipeRatingSummary?, String>(
      (ref, recipeId) => ref
          .watch(recipeRatingRepositoryProvider)
          .watchHouseholdSummary(recipeId),
    );

final recipePhotoFileProvider = FutureProvider.autoDispose
    .family<File?, String>(
      (ref, path) => ref.watch(recipePhotoStoreProvider).file(path),
    );

/// Naziv i filteri za listu recepata; ostaju i kad se prozor raširi.
class RecipeSearch extends Notifier<RecipeFilter> {
  @override
  RecipeFilter build() => RecipeFilter.none;

  void setQuery(String query) => state = state.copyWith(query: query);

  void set(RecipeFilter filter) => state = filter;

  void clearFilters() => state = state.cleared();
}

final recipeSearchProvider = NotifierProvider<RecipeSearch, RecipeFilter>(
  RecipeSearch.new,
);
