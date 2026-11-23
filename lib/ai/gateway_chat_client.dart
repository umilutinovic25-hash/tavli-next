import 'dart:async';

import 'package:supabase/supabase.dart';

import 'ai_errors.dart';
import 'ai_models.dart';
import 'chain_config.dart';

typedef GatewayInvoke = Future<FunctionResponse> Function(
  HttpMethod method,
  Map<String, Object?>? body,
);

class GatewayChatClient {
  GatewayChatClient({
    required this.invoke,
    required this.accountId,
    required this.refresh,
  });

  factory GatewayChatClient.supabase(
    SupabaseClient client, {
    required Future<bool> Function() refresh,
  }) => GatewayChatClient(
    accountId: () => client.auth.currentSession?.user.id,
    refresh: refresh,
    invoke: (method, body) {
      final token = client.auth.currentSession?.accessToken;
      if (token == null) throw const GatewayAuthError();
      return client.functions.invoke(
        'ai-gateway',
        method: method,
        body: body,
        headers: {'Authorization': 'Bearer $token'},
      );
    },
  );

  final GatewayInvoke invoke;
  final String? Function() accountId;
  final Future<bool> Function() refresh;

  Future<List<ModelSpec>> models(TaskKind kind) async {
    final data = await _request(HttpMethod.get, const Duration(seconds: 15));
    final ids = data[kind.name];
    if (ids is! List<Object?>) throw const GatewayUnavailableError();
    final known = ChainConfig.gatewayModels(kind);
    return [for (final id in ids.whereType<String>().toSet()) ?known[id]];
  }

  Future<String> complete(ModelSpec model, AIRequest request) async {
    final task = request.task;
    if (task == null) throw const GatewayRequestRejected();
    final id = '${model.provider.name.toLowerCase()}/${model.model}';
    final data = await _request(
      HttpMethod.post,
      model.timeout + const Duration(seconds: 15),
      body: {
        'task': task.wireName,
        'model': id,
        'system': request.system,
        'prompt': request.prompt,
        'temperature': request.temperature,
        if (request.images.isNotEmpty)
          'images': [for (final image in request.images) image.toDataUrl()],
      },
    );
    final content = data['content'];
    if (data['model'] != id || content is! String || content.trim().isEmpty) {
      throw const TransientError('Neispravan odgovor gateway-a.');
    }
    return content;
  }

  /// Embedding requests share the gateway's authenticated text quota and keep
  /// the OpenAI key on the server.
  Future<Map<String, Object?>> embed(List<Map<String, Object?>> inputs) =>
      _request(
        HttpMethod.post,
        const Duration(seconds: 45),
        body: {'task': 'recipe_embeddings', 'inputs': inputs},
      );

  Future<Map<String, Object?>> _request(
    HttpMethod method,
    Duration timeout, {
    Map<String, Object?>? body,
  }) async {
    try {
      final response = await invoke(method, body).timeout(timeout);
      final Object? data = response.data;
      if (response.status != 200) throw _error(response.status, data);
      if (data is Map<String, Object?>) return data;
      throw const TransientError('Neispravan odgovor gateway-a.');
    } on FunctionException catch (e) {
      throw _error(e.status, e.details);
    } on TimeoutException {
      throw const TransientError(
        'Gateway nije odgovorio na vreme.',
        isTimeout: true,
      );
    } on FormatException {
      throw const TransientError('Neispravan odgovor gateway-a.');
    }
  }

  static AIError _error(int status, Object? details) {
    final data = details is Map<String, Object?>
        ? details
        : const <String, Object?>{};
    final seconds = data['retryAfterSeconds'];
    final retry = seconds is int && seconds >= 0 && seconds <= 86400
        ? Duration(seconds: seconds)
        : null;
    return switch ((status, data['error'])) {
      (401, _) => const GatewayAuthError(),
      (400, 'bad_request') => const BadRequestError('Zahtev je odbijen.'),
      (413, 'too_large') => const GatewayRequestRejected(),
      (429, 'quota_exceeded' || 'busy') => GatewayQuotaError(
        retry ?? const Duration(minutes: 1),
        kind: data['limit'] == 'daily'
            ? switch (data['kind']) {
                'text' => TaskKind.text,
                'vision' => TaskKind.vision,
                _ => null,
              }
            : null,
      ),
      (429, 'provider_rate_limited') => RateLimitError(
        'Limit provajdera.',
        retryAfter: retry,
      ),
      (503, 'model_unavailable') => const ModelNotFoundError(
        'Model nije dostupan.',
      ),
      (503, 'gateway_unavailable') => const GatewayUnavailableError(),
      (504, _) => const TransientError(
        'Gateway nije odgovorio na vreme.',
        isTimeout: true,
      ),
      _ => const TransientError('Zahtev nije uspeo. Pokušaj ponovo.'),
    };
  }
}
