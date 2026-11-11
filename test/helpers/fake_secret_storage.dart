import 'package:tavli/ai/key_store.dart';

/// Keychain u memoriji.
class MapSecretStorage implements SecretStorage {
  final values = <String, String>{};

  /// Kad je true, čitanje i upis bacaju kao Keychain koji ne odgovara.
  bool failing = false;

  @override
  Future<String?> read(String key) async {
    if (failing) throw const SecretStorageException('locked');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failing) throw const SecretStorageException('locked');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}
