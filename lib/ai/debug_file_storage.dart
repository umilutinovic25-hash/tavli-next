import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'key_store.dart';

/// SAMO za debug build na macOS-u: čuva tajne u JSON fajlu u Application
/// Support direktorijumu da bi ad-hoc potpisan build preskočio keychain
/// dijalog. Release i ostale platforme i dalje koriste keychain.
class DebugFileSecretStorage implements SecretStorage {
  DebugFileSecretStorage({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file() async {
    final dir = await _directory();
    await dir.create(recursive: true);
    return File('${dir.path}/tavli-debug-secrets.json');
  }

  Future<Map<String, String>> _load() async {
    final file = await _file();
    if (!await file.exists()) return {};
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return {};
      return {
        for (final e in raw.entries)
          if (e.value is String) e.key as String: e.value as String,
      };
    } on FormatException {
      return {};
    }
  }

  Future<void> _save(Map<String, String> values) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(values), flush: true);
    // Samo vlasnik može da čita i menja fajl.
    await Process.run('chmod', ['600', tmp.path]);
    await tmp.rename(file.path);
  }

  @override
  Future<String?> read(String key) async => (await _load())[key];

  @override
  Future<void> write(String key, String value) async {
    final values = await _load();
    values[key] = value;
    await _save(values);
  }

  @override
  Future<void> delete(String key) async {
    final values = await _load();
    if (values.remove(key) != null) await _save(values);
  }
}

/// Da li se u ovom procesu sme koristiti debug fajl umesto keychain-a.
bool debugFileSecretsAllowed({
  required bool debugMode,
  required bool isMacOS,
  required Map<String, String> environment,
}) => debugMode && isMacOS && !environment.containsKey('FLUTTER_TEST');
