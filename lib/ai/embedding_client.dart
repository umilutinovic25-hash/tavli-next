import 'gateway_chat_client.dart';

/// Pinned model and vector size: every cached document vector must use the
/// same representation as its search query.
const recipeEmbeddingModel = 'text-embedding-3-small';
const recipeEmbeddingDimensions = 768;
const maxEmbeddingInputs = 32;
const maxEmbeddingInputLength = 8_000;
const maxEmbeddingTotalLength = 40_000;

enum EmbeddingTaskType { retrievalQuery, retrievalDocument }

extension on EmbeddingTaskType {
  String get wireName => switch (this) {
    EmbeddingTaskType.retrievalQuery => 'RETRIEVAL_QUERY',
    EmbeddingTaskType.retrievalDocument => 'RETRIEVAL_DOCUMENT',
  };
}

class EmbeddingInput {
  const EmbeddingInput({required this.text, required this.taskType});

  final String text;
  final EmbeddingTaskType taskType;

  Map<String, Object?> toJson() => {
    'text': text,
    'taskType': taskType.wireName,
  };
}

class EmbeddingRequestException implements Exception {
  const EmbeddingRequestException(this.message);

  final String message;

  @override
  String toString() => 'EmbeddingRequestException: $message';
}

/// Authenticated transport through the existing AI gateway; no provider key
/// leaves Supabase and calls count against the gateway's text quota.
class OpenAIEmbeddingClient {
  const OpenAIEmbeddingClient(this._gateway);

  final GatewayChatClient _gateway;

  Future<List<List<double>>> embed(List<EmbeddingInput> inputs) async {
    if (inputs.isEmpty) return const [];
    if (inputs.length > maxEmbeddingInputs ||
        inputs.any(
          (input) =>
              input.text.trim().isEmpty ||
              input.text.length > maxEmbeddingInputLength,
        ) ||
        inputs.fold<int>(0, (total, input) => total + input.text.length) >
            maxEmbeddingTotalLength ||
        inputs
                .where(
                  (input) => input.taskType == EmbeddingTaskType.retrievalQuery,
                )
                .length >
            1) {
      throw const EmbeddingRequestException('Zahtev za pretragu je prevelik.');
    }
    final result = await _gateway.embed([
      for (final input in inputs) input.toJson(),
    ]);
    if (result['model'] != recipeEmbeddingModel) {
      throw const EmbeddingRequestException('Nepoznat embedding model.');
    }
    final rawVectors = result['embeddings'];
    if (rawVectors is! List || rawVectors.length != inputs.length) {
      throw const EmbeddingRequestException('Neispravan odgovor za pretragu.');
    }
    final vectors = <List<double>>[];
    for (final raw in rawVectors) {
      if (raw is! List || raw.length != recipeEmbeddingDimensions) {
        throw const EmbeddingRequestException('Neispravan vektor za pretragu.');
      }
      final vector = <double>[];
      for (final value in raw) {
        if (value is! num || !value.toDouble().isFinite) {
          throw const EmbeddingRequestException(
            'Neispravan vektor za pretragu.',
          );
        }
        vector.add(value.toDouble());
      }
      vectors.add(vector);
    }
    return vectors;
  }
}
