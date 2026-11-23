import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:tavli/ai/embedding_client.dart';
import 'package:tavli/ai/gateway_chat_client.dart';
import 'package:tavli/ai/recipe_semantic_search.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/recipe_embedding_repository.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/recipe_search.dart';

Recipe _recipe(String id, String title) => Recipe(
  id: id,
  title: title,
  servings: 2,
  ingredients: const [Ingredient(name: 'namirnica')],
  source: RecipeSource.manual,
  createdAt: DateTime.utc(2026),
);

void main() {
  test(
    'batches changed recipe vectors, caches them, and embeds each query',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final List<List<Map<String, Object?>>> calls = [];
      final gateway = GatewayChatClient(
        accountId: () => 'account',
        refresh: () async => false,
        invoke: (_, body) async {
          final inputs = (body!['inputs'] as List).cast<Map<String, Object?>>();
          calls.add(inputs);
          final vectors = [
            for (final input in inputs)
              List<double>.filled(
                recipeEmbeddingDimensions,
                input['taskType'] == 'RETRIEVAL_QUERY'
                    ? 1
                    : input['text'].toString().contains('Pasulj')
                    ? 0.8
                    : 0.1,
              ),
          ];
          return FunctionResponse(
            status: 200,
            data: {'model': recipeEmbeddingModel, 'embeddings': vectors},
          );
        },
      );
      final service = RecipeSemanticSearchService(
        client: OpenAIEmbeddingClient(gateway),
        embeddings: RecipeEmbeddingRepository(db, 'household'),
      );
      final recipes = [
        _recipe('beans', 'Pasulj'),
        _recipe('salad', 'Zelena salata'),
      ];

      final first = await service.search(
        query: 'topli obrok',
        recipes: recipes,
        filter: const RecipeFilter(query: 'topli obrok'),
      );
      final second = await service.search(
        query: 'brza vecera',
        recipes: recipes,
        filter: const RecipeFilter(query: 'brza vecera'),
      );

      expect(first.first.id, 'beans');
      expect(second.first.id, 'beans');
      expect(calls.map((inputs) => inputs.length), [3, 1]);
      expect(calls.last.single['taskType'], 'RETRIEVAL_QUERY');
    },
  );
}
