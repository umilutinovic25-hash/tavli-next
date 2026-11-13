import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_models.dart';

/// Servis po početku ključa; null kad format nije poznat.
AIProvider? detectProvider(String key) {
  final k = key.trim();
  if (k.startsWith('AIza')) return AIProvider.gemini;
  if (k.startsWith('gsk_')) return AIProvider.groq;
  if (k.startsWith('sk-or-')) return AIProvider.openRouter;
  return null;
}

/// Ključ koji je korisnik dodao.
class StoredKey {
  const StoredKey({
    required this.id,
    required this.provider,
    required this.value,
    required this.addedAt,
  });

  final String id;
  final AIProvider provider;
  final String value;
  final DateTime addedAt;

  /// Jedino što se prikazuje posle čuvanja.
  String get masked =>
      '••••${value.length <= 4 ? value : value.substring(value.length - 4)}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'provider': provider.name,
    'value': value,
    'addedAt': addedAt.toUtc().toIso8601String(),
  };

  static StoredKey? fromJson(Object? json) {
    if (json is! Map) return null;
    final provider = AIProvider.values.asNameMap()[json['provider']];
    final id = json['id'];
    final value = json['value'];
    final addedAt = DateTime.tryParse(json['addedAt']?.toString() ?? '');
    if (provider == null || id is! String || value is! String) return null;
    return StoredKey(
      id: id,
      provider: provider,
      value: value,
      addedAt: addedAt ?? DateTime.utc(2026),
    );
  }

  /// Bez vrednosti ključa, da ne završi u logu.
  @override
  String toString() => 'StoredKey($id, ${provider.name})';
}

class DuplicateKeyException implements Exception {
  const DuplicateKeyException();
}

/// Ključevi koje je korisnik dodao, redom dodavanja.
abstract interface class KeyStore {
  Future<List<StoredKey>> list();

  /// Baca [DuplicateKeyException] ako je isti ključ već dodat.
  Future<StoredKey> add(AIProvider provider, String value);
  Future<void> remove(String id);

  /// Briše sve sopstvene ključeve (brisanje naloga, FR-025).
  Future<void> clear();
}

/// Greška sistemskog skladišta (Keychain/Keystore). [code] je sistemski kod
/// (npr. -25293 kad je pristup odbijen), bez sadržaja zapisa.
class SecretStorageException implements Exception {
  const SecretStorageException(this.code);

  final String code;

  @override
  String toString() => 'SecretStorageException($code)';
}

/// Minimalni interfejs sigurnog skladišta (lakše se zameni u testu).
abstract interface class SecretStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Keychain (iOS, macOS) i Keystore (Android).
class KeychainSecretStorage implements SecretStorage {
  const KeychainSecretStorage();

  static const _storage = FlutterSecureStorage(
    // Klasičan keychain ne traži posebna prava (entitlements)
    // pa radi i u nepotpisanom debug build-u na macOS-u.
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<String?> read(String key) => _guard(() => _storage.read(key: key));

  @override
  Future<void> write(String key, String value) =>
      _guard(() => _storage.write(key: key, value: value));

  @override
  Future<void> delete(String key) => _guard(() => _storage.delete(key: key));

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (e) {
      throw SecretStorageException(e.code);
    }
  }
}

/// Ključevi u Keychain-u (iOS, macOS) i Keystore-u (Android), kao jedna
/// JSON lista. Stari zapisi `api_key_<servis>` prelaze u listu pri čitanju.
class SecureKeyStore implements KeyStore {
  SecureKeyStore({
    SecretStorage? storage,
    DateTime Function()? clock,
    String Function()? newId,
  }) : _storage = storage ?? const KeychainSecretStorage(),
       _clock = clock ?? DateTime.now,
       _newId = newId ?? _randomId;

  final SecretStorage _storage;
  final DateTime Function() _clock;
  final String Function() _newId;

  static const _listKey = 'api_keys';
  static String _legacyKey(AIProvider p) => 'api_key_${p.name}';

  static String _randomId() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  @override
  Future<List<StoredKey>> list() async {
    final raw = await _storage.read(_listKey);
    // Kad lista postoji, stari zapisi su već prebačeni: jedno čitanje
    // Keychain-a umesto četiri (svako može da traži lozinku na macOS-u).
    if (raw != null) return _decode(raw);
    final keys = <StoredKey>[];
    for (final p in AIProvider.values) {
      // Stari zapis je napravio prethodni build; macOS može da odbije
      // pristup. Tada ga preskačemo: korisnik ključ može ponovo da doda.
      final String? legacy;
      try {
        legacy = (await _storage.read(_legacyKey(p)))?.trim();
      } on SecretStorageException {
        continue;
      }
      if (legacy == null) continue;
      if (legacy.isNotEmpty && !keys.any((k) => k.value == legacy)) {
        keys.add(
          StoredKey(
            id: _newId(),
            provider: p,
            value: legacy,
            addedAt: _clock(),
          ),
        );
      }
      try {
        await _storage.delete(_legacyKey(p));
      } on SecretStorageException {
        // Ostaje u Keychain-u, ali se više ne čita (lista sada postoji).
      }
    }
    await _save(keys);
    return keys;
  }

  static List<StoredKey> _decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    return [for (final k in decoded) ?StoredKey.fromJson(k)];
  }

  @override
  Future<StoredKey> add(AIProvider provider, String value) async {
    final keys = await list();
    final v = value.trim();
    if (keys.any((k) => k.value == v)) throw const DuplicateKeyException();
    final key = StoredKey(
      id: _newId(),
      provider: provider,
      value: v,
      addedAt: _clock(),
    );
    await _save([...keys, key]);
    return key;
  }

  @override
  Future<void> remove(String id) async {
    final keys = await list();
    await _save([
      for (final k in keys)
        if (k.id != id) k,
    ]);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(_listKey);
    for (final p in AIProvider.values) {
      await _storage.delete(_legacyKey(p));
    }
  }

  Future<void> _save(List<StoredKey> keys) =>
      _storage.write(_listKey, jsonEncode([for (final k in keys) k.toJson()]));
}

/// Za testove. Početni ključevi dobijaju id = naziv servisa.
class InMemoryKeyStore implements KeyStore {
  InMemoryKeyStore([Map<AIProvider, String>? keys])
    : _keys = [
        for (final MapEntry(:key, :value) in {...?keys}.entries)
          StoredKey(
            id: key.name,
            provider: key,
            value: value,
            addedAt: DateTime.utc(2026),
          ),
      ];

  final List<StoredKey> _keys;
  var _n = 0;

  @override
  Future<List<StoredKey>> list() async => List.unmodifiable(_keys);

  @override
  Future<StoredKey> add(AIProvider provider, String value) async {
    final v = value.trim();
    if (_keys.any((k) => k.value == v)) throw const DuplicateKeyException();
    final key = StoredKey(
      id: '${provider.name}-${++_n}',
      provider: provider,
      value: v,
      addedAt: DateTime.utc(2026),
    );
    _keys.add(key);
    return key;
  }

  @override
  Future<void> remove(String id) async => _keys.removeWhere((k) => k.id == id);

  @override
  Future<void> clear() async => _keys.clear();
}

/// Odakle je ključ: korisnikov (Keychain/Keystore) ili ugrađen u Tavli.
enum KeyOrigin { user, builtIn }

class ApiCredential {
  const ApiCredential(this.provider, this.value, this.origin, {this.keyId});

  final AIProvider provider;
  final String value;
  final KeyOrigin origin;

  /// Id sačuvanog ključa (samo za sopstvene ključeve).
  final String? keyId;

  /// Oznaka ključa za pauze i odbijene ključeve.
  String get slot => keyId == null ? origin.name : '${origin.name}:$keyId';

  /// Bez vrednosti ključa, da ne završi u logu.
  @override
  String toString() => 'ApiCredential(${provider.name}, ${origin.name})';
}

/// Ključevi koje router proba za provajdera, redom. Ugrađeni ključ
/// je marker gatewaya ([gatewayCredentialValue]), pa router ostaje isti.
abstract interface class KeySource {
  Future<List<ApiCredential>> credentialsFor(AIProvider provider);
}

/// Vrednost „ključa“ koja znači: zahtev ide preko Tavli gatewaya
/// (edge funkcija `ai-complete`), a pravi ključ drži server.
const gatewayCredentialValue = 'tavli-gateway';

/// Ugrađeni ključevi iz `secrets.json` preko `--dart-define-from-file`
/// (samo za razvoj) ili marker gatewaya ([BuiltInKeys.gateway]).
class BuiltInKeys {
  const BuiltInKeys([this._keys = const {}]);

  factory BuiltInKeys.gateway() => BuiltInKeys({
    for (final p in AIProvider.values) p: gatewayCredentialValue,
  });

  factory BuiltInKeys.fromEnvironment() => const BuiltInKeys({
    AIProvider.gemini: String.fromEnvironment('GEMINI_API_KEY'),
    AIProvider.groq: String.fromEnvironment('GROQ_API_KEY'),
    AIProvider.openRouter: String.fromEnvironment('OPENROUTER_API_KEY'),
  });

  final Map<AIProvider, String> _keys;

  String? operator [](AIProvider provider) {
    final key = _keys[provider]?.trim();
    return key == null || key.isEmpty ? null : key;
  }

  bool has(AIProvider provider) => this[provider] != null;

  /// Da li je vrednost neki od ugrađenih ključeva (tada nije korisnička).
  bool contains(String value) {
    final v = value.trim();
    return v.isNotEmpty && AIProvider.values.any((p) => this[p] == v);
  }
}

/// Koji ugrađeni ključevi važe: izdanje nikad ne koristi ključeve iz
/// okruženja, već gateway (samo prijavljen nalog); razvoj koristi ključeve iz
/// `secrets.json` ako ih ima, inače gateway.
BuiltInKeys builtInKeysFor({
  required bool release,
  required bool signedIn,
  required BuiltInKeys fromEnvironment,
}) {
  if (!release && AIProvider.values.any(fromEnvironment.has)) {
    return fromEnvironment;
  }
  return signedIn ? BuiltInKeys.gateway() : const BuiltInKeys();
}

/// Prvo korisnikovi ključevi (redom dodavanja), pa ugrađeni. Sačuvan ključ
/// koji je isti kao ugrađeni (npr. unet ranije ručno) računa se kao ugrađeni.
class LayeredKeySource implements KeySource {
  LayeredKeySource(this._own, this._builtIn);

  final KeyStore _own;
  final BuiltInKeys _builtIn;

  @override
  Future<List<ApiCredential>> credentialsFor(AIProvider provider) async {
    final builtIn = _builtIn[provider];
    return [
      for (final k in await _own.list())
        if (k.provider == provider &&
            k.value.trim().isNotEmpty &&
            !_builtIn.contains(k.value))
          ApiCredential(provider, k.value.trim(), KeyOrigin.user, keyId: k.id),
      if (builtIn != null) ApiCredential(provider, builtIn, KeyOrigin.builtIn),
    ];
  }
}
