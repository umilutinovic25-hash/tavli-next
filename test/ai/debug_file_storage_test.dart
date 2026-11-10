import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/ai/debug_file_storage.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tavli-debug-secrets-');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  DebugFileSecretStorage storage() =>
      DebugFileSecretStorage(directory: () async => dir);

  test('upis, čitanje i brisanje prolaze kroz fajl', () async {
    final s = storage();
    expect(await s.read('session'), isNull);

    await s.write('session', '{"token":"x"}');
    await s.write('api_keys', '[]');
    expect(await s.read('session'), '{"token":"x"}');

    // Novi objekat čita iz istog fajla (nije samo memorija).
    expect(await storage().read('api_keys'), '[]');

    await s.delete('session');
    expect(await s.read('session'), isNull);
    expect(await s.read('api_keys'), '[]');
  });

  test('pokvaren fajl se tretira kao prazan, ne ruši aplikaciju', () async {
    File('${dir.path}/tavli-debug-secrets.json')
        .writeAsStringSync('{nije json');
    expect(await storage().read('session'), isNull);
  });

  test('fajl se piše samo za vlasnika (600)', () async {
    await storage().write('session', 'v');
    final file = File('${dir.path}/tavli-debug-secrets.json');
    final mode = (await file.stat()).mode & 0x1FF;
    expect(mode, 0x180); // 0600
  });

  group('debugFileSecretsAllowed', () {
    test('samo debug, macOS i van flutter test', () {
      expect(
        debugFileSecretsAllowed(
          debugMode: true,
          isMacOS: true,
          environment: const {},
        ),
        isTrue,
      );
    });

    test('release, druge platforme i testovi koriste keychain', () {
      expect(
        debugFileSecretsAllowed(
          debugMode: false,
          isMacOS: true,
          environment: const {},
        ),
        isFalse,
      );
      expect(
        debugFileSecretsAllowed(
          debugMode: true,
          isMacOS: false,
          environment: const {},
        ),
        isFalse,
      );
      expect(
        debugFileSecretsAllowed(
          debugMode: true,
          isMacOS: true,
          environment: const {'FLUTTER_TEST': 'true'},
        ),
        isFalse,
      );
    });
  });
}
