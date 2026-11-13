import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:tavli/ai/ai_errors.dart';
import 'package:tavli/ai/ai_models.dart';
import 'package:tavli/ai/gateway_chat_client.dart';

const model = ModelSpec(
  provider: AIProvider.groq,
  model: 'openai/gpt-oss-120b',
  label: 'Test',
);
const request = AIRequest(system: 's', prompt: 'p', temperature: 0.2);

GatewayChatClient clientThrowing(int status, [Object? details]) =>
    GatewayChatClient.withInvoker(
      (name, body) async =>
          throw FunctionException(status: status, details: details),
    );

void main() {
  test('šalje zahtev funkciji ai-complete i vraća tekst', () async {
    String? calledName;
    Map<String, dynamic>? calledBody;
    final client = GatewayChatClient.withInvoker((name, body) async {
      calledName = name;
      calledBody = body;
      return const FunctionResponse(data: {'text': '{"a":1}'}, status: 200);
    });
    final text = await client.complete(
      model,
      AIRequest(
        system: 's',
        prompt: 'p',
        temperature: 0.2,
        images: [
          AIImage(Uint8List.fromList([1, 2, 3])),
        ],
      ),
      apiKey: 'ignorisan',
    );
    expect(text, '{"a":1}');
    expect(calledName, 'ai-complete');
    expect(calledBody!['provider'], 'groq');
    expect(calledBody!['model'], 'openai/gpt-oss-120b');
    expect(calledBody!['temperature'], 0.2);
    expect(calledBody!['images'], [
      {'mime': 'image/jpeg', 'base64': 'AQID'},
    ]);
  });

  test('429 sa retry_after i daily postaje RateLimitError', () async {
    final client = clientThrowing(429, {
      'error': 'rate_limited',
      'retry_after': 12,
      'daily': true,
    });
    await expectLater(
      client.complete(model, request, apiKey: 'x'),
      throwsA(
        isA<RateLimitError>()
            .having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 12),
            )
            .having((e) => e.isDaily, 'isDaily', true),
      ),
    );
  });

  test('429 bez retry_after i daily nije dnevni i nema pauzu', () async {
    final client = clientThrowing(429, {'error': 'rate_limited'});
    await expectLater(
      client.complete(model, request, apiKey: 'x'),
      throwsA(
        isA<RateLimitError>()
            .having((e) => e.retryAfter, 'retryAfter', null)
            .having((e) => e.isDaily, 'isDaily', false),
      ),
    );
  });

  test('401 (istekla sesija) je TransientError, ne AuthError', () async {
    await expectLater(
      clientThrowing(401, {
        'error': 'unauthorized',
      }).complete(model, request, apiKey: 'x'),
      throwsA(isA<TransientError>()),
    );
  });

  test('404 je ModelNotFoundError', () async {
    await expectLater(
      clientThrowing(404, {
        'error': 'model_not_found',
      }).complete(model, request, apiKey: 'x'),
      throwsA(isA<ModelNotFoundError>()),
    );
  });

  test('400 i 413 su BadRequestError', () async {
    for (final status in [400, 413]) {
      await expectLater(
        clientThrowing(status).complete(model, request, apiKey: 'x'),
        throwsA(isA<BadRequestError>()),
      );
    }
  });

  test('502, 503 i ostalo su TransientError', () async {
    for (final status in [502, 503, 500]) {
      await expectLater(
        clientThrowing(status).complete(model, request, apiKey: 'x'),
        throwsA(isA<TransientError>()),
      );
    }
  });

  test('bez klijenta (nije prijavljen) je TransientError', () async {
    await expectLater(
      GatewayChatClient(null).complete(model, request, apiKey: 'x'),
      throwsA(isA<TransientError>()),
    );
  });

  test('prazan tekst u odgovoru je InvalidOutputError', () async {
    final client = GatewayChatClient.withInvoker(
      (name, body) async =>
          const FunctionResponse(data: {'text': ''}, status: 200),
    );
    await expectLater(
      client.complete(model, request, apiKey: 'x'),
      throwsA(isA<InvalidOutputError>()),
    );
  });
}
