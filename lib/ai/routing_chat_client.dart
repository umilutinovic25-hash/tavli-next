import 'ai_models.dart';
import 'chat_client.dart';
import 'key_store.dart';

/// Marker [gatewayCredentialValue] ide na Tavli gateway, svaki drugi ključ
/// (sopstveni, ili iz `secrets.json` u razvoju) direktno provajderu.
class RoutingChatClient implements ChatClient {
  const RoutingChatClient({required this.direct, required this.gateway});

  final ChatClient direct;
  final ChatClient gateway;

  @override
  Future<String> complete(
    ModelSpec model,
    AIRequest request, {
    required String apiKey,
  }) => (apiKey == gatewayCredentialValue ? gateway : direct).complete(
    model,
    request,
    apiKey: apiKey,
  );
}
