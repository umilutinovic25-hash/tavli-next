import 'dart:convert';

import 'package:supabase/supabase.dart';

import 'ai_errors.dart';
import 'ai_models.dart';
import 'chat_client.dart';

typedef GatewayInvoker = Future<FunctionResponse> Function(
  String name,
  Map<String, dynamic> body,
);

/// Ugrađeni Tavli AI: zahtev ide edge funkciji `ai-complete`, koja drži
/// provajder ključeve. Ključ iz [complete] se ignoriše (marker, ne ključ).
class GatewayChatClient implements ChatClient {
  GatewayChatClient(SupabaseClient? client)
    : _invoke = client == null
          ? null
          : ((name, body) => client.functions.invoke(name, body: body));

  GatewayChatClient.withInvoker(GatewayInvoker invoker) : _invoke = invoker;

  final GatewayInvoker? _invoke;

  @override
  Future<String> complete(
    ModelSpec model,
    AIRequest request, {
    required String apiKey,
  }) async {
    final invoke = _invoke;
    if (invoke == null) throw const TransientError('Nije prijavljen');
    final FunctionResponse response;
    try {
      response = await invoke('ai-complete', {
        'provider': model.provider.name,
        'model': model.model,
        'system': request.system,
        'prompt': request.prompt,
        'temperature': request.temperature,
        'images': [
          for (final image in request.images)
            {'mime': image.mimeType, 'base64': base64Encode(image.bytes)},
        ],
      });
    } on FunctionException catch (e) {
      throw _map(e);
    }
    final data = response.data;
    final text = data is Map ? data['text'] : null;
    if (text is! String || text.trim().isEmpty) {
      throw const InvalidOutputError('Prazan odgovor modela');
    }
    return text;
  }

  static AIError _map(FunctionException e) {
    final details = e.details;
    final body = details is Map ? details : const <Object?, Object?>{};
    final message = 'HTTP ${e.status}: ${body['error'] ?? e.reasonPhrase}';
    return switch (e.status) {
      429 => RateLimitError(
        message,
        retryAfter: body['retry_after'] is num
            ? Duration(seconds: (body['retry_after'] as num).ceil())
            : null,
        isDaily: body['daily'] == true,
      ),
      // Istekla sesija: privremeno, da router ne isključi gateway do restarta.
      401 => const TransientError('Sesija je istekla'),
      404 => ModelNotFoundError(message),
      400 || 413 => BadRequestError(message),
      _ => TransientError(message),
    };
  }
}
