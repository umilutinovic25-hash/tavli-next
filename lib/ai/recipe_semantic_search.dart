import '../data/recipe_embedding_repository.dart';
import '../domain/recipe.dart';
import '../domain/recipe_search.dart';
import 'embedding_client.dart';

class EmbeddingServiceUnavailableException implements Exception {
  const EmbeddingServiceUnavailableException();
}

/// Embeds a query and any changed recipe documents, retaining document vectors
/// in the account-scoped local cache for later searches.
class RecipeSemanticSearchService {
  const RecipeSemanticSearchService({
    required this._client,
    required this._embeddings,
  });

  final OpenAIEmbeddingClient _client;
  final RecipeEmbeddingRepository _embeddings;

  Future<List<Recipe>> search({
    required String query,
    required List<Recipe> recipes,
    required RecipeFilter filter,
  }) async {
    if (query.trim().isEmpty) return const [];
    final candidates = searchRecipes(recipes, filter.copyWith(query: ''));
    final vectors = <String, List<double>>{};
    final uncached = <Recipe>[];
    for (final recipe in candidates) {
      final cached = await _embeddings.getFor(recipe);
      if (cached == null) {
        uncached.add(recipe);
      } else {
        vectors[recipe.id] = cached;
      }
    }
    final batches = _documentBatches(uncached, query.length);
    List<double>? queryVector;
    for (var batchIndex = 0; batchIndex < batches.length; batchIndex++) {
      final batch = batches[batchIndex];
      final isLastBatch = batchIndex == batches.length - 1;
      final input = [
        for (final recipe in batch)
          EmbeddingInput(
            text: _boundedRecipeText(recipe),
            taskType: EmbeddingTaskType.retrievalDocument,
          ),
        if (isLastBatch)
          EmbeddingInput(
            text: query,
            taskType: EmbeddingTaskType.retrievalQuery,
          ),
      ];
      final embedded = await _client.embed(input);
      for (var index = 0; index < batch.length; index++) {
        final recipe = batch[index];
        final vector = embedded[index];
        vectors[recipe.id] = vector;
        await _embeddings.save(recipe, vector);
      }
      if (isLastBatch) queryVector = embedded.last;
    }
    queryVector ??= (await _client.embed([
      EmbeddingInput(text: query, taskType: EmbeddingTaskType.retrievalQuery),
    ])).single;
    return searchSemantically(recipes, filter, queryVector, vectors);
  }

  List<List<Recipe>> _documentBatches(List<Recipe> recipes, int queryLength) {
    if (recipes.isEmpty) return const [];
    final maxDocumentChars = maxEmbeddingTotalLength - queryLength;
    final batches = <List<Recipe>>[];
    var current = <Recipe>[];
    var currentLength = 0;
    for (final recipe in recipes) {
      final text = _boundedRecipeText(recipe);
      if (current.isNotEmpty &&
          (current.length >= maxEmbeddingInputs - 1 ||
              currentLength + text.length > maxDocumentChars)) {
        batches.add(current);
        current = <Recipe>[];
        currentLength = 0;
      }
      current.add(recipe);
      currentLength += text.length;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  String _boundedRecipeText(Recipe recipe) {
    final text = recipeEmbeddingText(recipe);
    return text.length <= maxEmbeddingInputLength
        ? text
        : text.substring(0, maxEmbeddingInputLength);
  }
}
