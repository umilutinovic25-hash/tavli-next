import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/ai/ai_models.dart';
import 'package:tavli/ai/key_store.dart';

const withKeys = BuiltInKeys({AIProvider.groq: 'gsk-test'});

void main() {
  test('gateway ima marker za sva tri provajdera', () {
    final keys = BuiltInKeys.gateway();
    for (final p in AIProvider.values) {
      expect(keys[p], gatewayCredentialValue);
    }
  });

  test('izdanje nikad ne vraća ključeve iz okruženja, ni kad postoje', () {
    final keys = builtInKeysFor(
      release: true,
      signedIn: true,
      fromEnvironment: withKeys,
    );
    expect(keys.contains('gsk-test'), false);
    expect(keys[AIProvider.groq], gatewayCredentialValue);
  });

  test('izdanje bez prijave nema ugrađenih ključeva', () {
    final keys = builtInKeysFor(
      release: true,
      signedIn: false,
      fromEnvironment: withKeys,
    );
    for (final p in AIProvider.values) {
      expect(keys.has(p), false);
    }
  });

  test('razvoj sa ključevima iz okruženja koristi njih direktno', () {
    final keys = builtInKeysFor(
      release: false,
      signedIn: true,
      fromEnvironment: withKeys,
    );
    expect(keys[AIProvider.groq], 'gsk-test');
  });

  test('razvoj bez ključeva i prijavljen koristi gateway', () {
    final keys = builtInKeysFor(
      release: false,
      signedIn: true,
      fromEnvironment: const BuiltInKeys(),
    );
    expect(keys[AIProvider.gemini], gatewayCredentialValue);
  });

  test('LayeredKeySource daje gateway marker kao ugrađeni ključ', () async {
    final source = LayeredKeySource(InMemoryKeyStore(), BuiltInKeys.gateway());
    final creds = await source.credentialsFor(AIProvider.groq);
    expect(creds.single.origin, KeyOrigin.builtIn);
    expect(creds.single.value, gatewayCredentialValue);
  });
}
