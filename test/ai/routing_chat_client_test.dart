import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/ai/ai_models.dart';
import 'package:tavli/ai/chat_client.dart';
import 'package:tavli/ai/key_store.dart';
import 'package:tavli/ai/routing_chat_client.dart';

const model = ModelSpec(
  provider: AIProvider.groq,
  model: 'test-model',
  label: 'Test',
);
const request = AIRequest(system: 's', prompt: 'p');

class _Recording implements ChatClient {
  _Recording(this.name, this.calls);
  final String name;
  final List<String> calls;

  @override
  Future<String> complete(
    ModelSpec model,
    AIRequest request, {
    required String apiKey,
  }) async {
    calls.add('$name:$apiKey');
    return name;
  }
}

void main() {
  test('marker ugrađenog ključa ide na gateway', () async {
    final calls = <String>[];
    final client = RoutingChatClient(
      direct: _Recording('direct', calls),
      gateway: _Recording('gateway', calls),
    );
    final text = await client.complete(
      model,
      request,
      apiKey: gatewayCredentialValue,
    );
    expect(text, 'gateway');
    expect(calls, ['gateway:$gatewayCredentialValue']);
  });

  test('sopstveni ključ ide direktno provajderu', () async {
    final calls = <String>[];
    final client = RoutingChatClient(
      direct: _Recording('direct', calls),
      gateway: _Recording('gateway', calls),
    );
    await client.complete(model, request, apiKey: 'moj-kljuc');
    expect(calls, ['direct:moj-kljuc']);
  });
}
