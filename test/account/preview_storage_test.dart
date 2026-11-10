import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/preview_storage.dart';
import 'package:tavli/account/session_store.dart';
import 'package:tavli/account/supabase_config.dart';
import 'package:tavli/ai/key_store.dart';
import 'package:tavli/providers.dart';

class FakeStorage implements SecretStorage {
  final data = <String, String>{
    'auth_session': 'original-session',
    'api_keys': 'original-keys',
  };
  final reads = <String>[];
  @override
  Future<String?> read(String key) async {
    reads.add(key);
    if (key == 'auth_session' ||
        key == 'api_keys' ||
        key.startsWith('api_key_')) {
      throw const SecretStorageException('denied');
    }
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  const local = SupabaseConfig(url: 'http://127.0.0.1:55321', anonKey: 'fake');
  test('default vraća isto skladište i za udaljeni backend', () {
    final base = FakeStorage();
    expect(
      storageForEnvironment(
        base,
        const SupabaseConfig(url: 'https://example.com', anonKey: 'fake'),
      ),
      same(base),
    );
  });
  test('session i AI migracija ne čitaju ili menjaju stare stavke', () async {
    final base = FakeStorage();
    final storage = storageForEnvironment(base, local, preview: true);
    final session = SessionStore(storage);
    expect(await session.read(), isNull);
    await session.write('fake-preview-session');
    expect(await session.read(), 'fake-preview-session');
    final keys = SecureKeyStore(storage: storage);
    expect(await keys.list(), isEmpty);
    expect(base.reads, everyElement(startsWith('tavli.local-preview.v1/')));
    await session.clear();
    expect(await session.read(), isNull);
    expect(base.data['auth_session'], 'original-session');
    expect(base.data['api_keys'], 'original-keys');
  });
  test(
    'oba postojeća store provider-a koriste isti izdvojeni adapter',
    () async {
      final base = FakeStorage();
      final container = ProviderContainer(
        overrides: [
          secretStorageProvider.overrideWithValue(
            storageForEnvironment(base, local, preview: true),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(sessionStoreProvider).read(), isNull);
      expect(await container.read(keyStoreProvider).list(), isEmpty);
      expect(base.reads, everyElement(startsWith('tavli.local-preview.v1/')));
    },
  );
  for (final host in ['localhost', '127.0.0.1', '[::1]']) {
    test('lokalni host $host', () {
      expect(
        storageForEnvironment(
          FakeStorage(),
          SupabaseConfig(url: 'http://$host:55321', anonKey: 'fake'),
          preview: true,
        ),
        isA<SecretStorage>(),
      );
    });
  }
  for (final url in [
    'https://example.com',
    'http://localhost.example.com',
    'http://127.0.0.1.example.com',
    'file:///localhost',
    '',
  ]) {
    test('preview odbija $url', () {
      expect(
        () => storageForEnvironment(
          FakeStorage(),
          SupabaseConfig(url: url, anonKey: 'fake'),
          preview: true,
        ),
        throwsStateError,
      );
    });
  }
}
