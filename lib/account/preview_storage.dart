import '../ai/key_store.dart';
import 'supabase_config.dart';

/// Preview koristi isto sigurno skladište uz zasebne ključeve. Default ne
/// menja postojeće stavke; nikad ne pokušava da migrira tuđe/stare vrednosti.
SecretStorage storageForEnvironment(
  SecretStorage storage,
  SupabaseConfig config, {
  bool preview = false,
}) {
  if (!preview) return storage;
  final uri = Uri.tryParse(config.url);
  if (!config.isConfigured ||
      uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      !{'localhost', '127.0.0.1', '::1', '[::1]'}.contains(uri.host)) {
    throw StateError('Lokalni pregled zahteva loopback Supabase.');
  }
  return _PreviewStorage(storage);
}

class _PreviewStorage implements SecretStorage {
  const _PreviewStorage(this._storage);
  final SecretStorage _storage;
  String _key(String key) => 'tavli.local-preview.v1/$key';

  @override
  Future<String?> read(String key) => _storage.read(_key(key));
  @override
  Future<void> write(String key, String value) =>
      _storage.write(_key(key), value);
  @override
  Future<void> delete(String key) => _storage.delete(_key(key));
}
