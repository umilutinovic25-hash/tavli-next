import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:tavli/ai/embedding_client.dart';
import 'package:tavli/ai/gateway_chat_client.dart';

GatewayChatClient gatewayFor(
  Map<String, Object?> Function(Map<String, Object?> body) response,
  List<Map<String, Object?>> bodies,
) => GatewayChatClient(
  accountId: () => 'account',
  refresh: () async => false,
  invoke: (method, body) async {
    expect(method, HttpMethod.post);
    final request = body!;
    bodies.add(request);
    return FunctionResponse(status: 200, data: response(request));
  },
);

void main() {
  group('OpenAIEmbeddingClient', () {
    test(
      'sends document and query tasks through the authenticated gateway',
      () async {
        final bodies = <Map<String, Object?>>[];
        final client = OpenAIEmbeddingClient(
          gatewayFor(
            (_) => {
              'model': recipeEmbeddingModel,
              'embeddings': [
                List<double>.filled(recipeEmbeddingDimensions, 0.2),
                List<double>.filled(recipeEmbeddingDimensions, 0.8),
              ],
            },
            bodies,
          ),
        );

        final vectors = await client.embed([
          const EmbeddingInput(
            text: 'Recept i sastojci',
            taskType: EmbeddingTaskType.retrievalDocument,
          ),
          const EmbeddingInput(
            text: 'Nešto sa povrćem',
            taskType: EmbeddingTaskType.retrievalQuery,
          ),
        ]);

        expect(vectors, hasLength(2));
        expect(vectors.last, hasLength(768));
        expect(bodies.single['task'], 'recipe_embeddings');
        expect(bodies.single['inputs'], [
          {'text': 'Recept i sastojci', 'taskType': 'RETRIEVAL_DOCUMENT'},
          {'text': 'Nešto sa povrćem', 'taskType': 'RETRIEVAL_QUERY'},
        ]);
      },
    );

    test('rejects unexpected models and malformed vectors', () async {
      final bodies = <Map<String, Object?>>[];
      final wrongModel = OpenAIEmbeddingClient(
        gatewayFor((_) => {'model': 'other', 'embeddings': []}, bodies),
      );
      await expectLater(
        wrongModel.embed([
          const EmbeddingInput(
            text: 'query',
            taskType: EmbeddingTaskType.retrievalQuery,
          ),
        ]),
        throwsA(isA<EmbeddingRequestException>()),
      );

      final badVector = OpenAIEmbeddingClient(
        gatewayFor(
          (_) => {
            'model': recipeEmbeddingModel,
            'embeddings': [
              <double>[1, 2],
            ],
          },
          bodies,
        ),
      );
      await expectLater(
        badVector.embed([
          const EmbeddingInput(
            text: 'query',
            taskType: EmbeddingTaskType.retrievalQuery,
          ),
        ]),
        throwsA(isA<EmbeddingRequestException>()),
      );
    });
  });
}
