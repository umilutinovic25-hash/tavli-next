import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart';

import 'account/account_api.dart';
import 'account/account_service.dart';
import 'account/auth_controller.dart';
import 'account/auth_gateway.dart';
import 'account/preview_storage.dart';
import 'account/session_store.dart';
import 'account/supabase_client.dart';
import 'account/supabase_config.dart';
import 'ai/ai_router.dart';
import 'ai/chain_config.dart';
import 'ai/chat_client.dart';
import 'ai/key_store.dart';
import 'ai/meal_plan_ai.dart';
import 'ai/recipe_ai.dart';
import 'data/database.dart';
import 'data/drift_model_status_store.dart';
import 'data/shopping_repository.dart';
import 'features/recipes/recipe_providers.dart';
import 'sync/downloader.dart';
import 'sync/legacy_mover.dart';
import 'sync/photo_sync.dart';
import 'sync/sync_engine.dart';
import 'sync/sync_remote.dart';
import 'sync/synced_writer.dart';
import 'sync/uploader.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final localPreviewProvider = Provider<bool>(
  (ref) => const bool.fromEnvironment('TAVLI_LOCAL_PREVIEW'),
);

final secretStorageProvider = Provider<SecretStorage>(
  (ref) => storageForEnvironment(
    const KeychainSecretStorage(),
    ref.watch(supabaseConfigProvider),
    preview: ref.watch(localPreviewProvider),
  ),
);

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SessionStore(ref.watch(secretStorageProvider)),
);

/// Adresa i anon ključ iz `--dart-define-from-file=secrets.json`.
final supabaseConfigProvider = Provider<SupabaseConfig>(
  (ref) => SupabaseConfig.fromEnvironment(),
);

/// null kad build nema Supabase podešavanja (prijava tada nije dostupna).
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  final config = ref.watch(supabaseConfigProvider);
  if (!config.isConfigured) return null;
  final client = createSupabaseClient(config);
  ref.onDispose(client.dispose);
  return client;
});

final authGatewayProvider = Provider<AuthGateway>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? const UnconfiguredAuthGateway()
      : SupabaseAuthGateway(client);
});

/// Vreme za prijavu (kada je poslat kod); menja se u testovima.
final authClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final accountApiProvider = Provider<AccountApi>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? const UnconfiguredAccountApi()
      : SupabaseAccountApi(client);
});

/// Nalog na uređaju: keš profila i domaćinstva, ime, brisanje.
final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(
    ref.watch(databaseProvider),
    ref.watch(accountApiProvider),
    photos: ref.watch(recipePhotoStoreProvider),
    keys: ref.watch(keyStoreProvider),
    onChange: () => ref.read(syncEngineProvider)?.kick(),
  ),
);

/// Upisuje izmene prijavljenog naloga u red za slanje i budi slanje.
final syncedWriterProvider = Provider<SyncedWriter>(
  (ref) => SyncedWriter(
    ref.watch(databaseProvider),
    accountId: (ref.watch(accountScopeProvider) ?? noAccountScope).userId,
    onChange: () => ref.read(syncEngineProvider)?.kick(),
  ),
);

final syncRemoteProvider = Provider<SyncRemote?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseSyncRemote(client);
});

final photoRemoteProvider = Provider<PhotoRemote?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabasePhotoRemote(client);
});

/// Obnavlja sesiju posle odgovora 401; false kad je obnova odbijena.
Future<bool> _refreshSession(Ref ref) async {
  final gateway = ref.read(authGatewayProvider);
  final store = ref.read(sessionStoreProvider);
  try {
    final session = await gateway.refresh();
    await store.write(session.json);
    return true;
  } on Offline {
    return true; // sledeće slanje će naići na mrežu i sačekati
  } on Unavailable {
    return true;
  } on AccountGone {
    // Nalog obrisan na drugom uređaju: i njegov keš ovde se briše.
    await ref
        .read(authControllerProvider.notifier)
        .sessionExpired(accountGone: true);
    return false;
  } on AuthFailure {
    return false;
  }
}

/// Slanje i preuzimanje za prijavljen nalog; null bez naloga ili servera.
/// Nov nalog → nov engine (stari se zaustavlja).
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final scope = ref.watch(accountScopeProvider);
  final remote = ref.watch(syncRemoteProvider);
  final photos = ref.watch(photoRemoteProvider);
  if (scope == null || remote == null || photos == null) return null;
  final db = ref.watch(databaseProvider);
  final engine = SyncEngine(
    db: db,
    scope: scope,
    uploader: Uploader(
      db: db,
      remote: remote,
      photos: photos,
      photoStore: ref.watch(recipePhotoStoreProvider),
      scope: scope,
      refreshSession: () => _refreshSession(ref),
    ),
    downloader: Downloader(db: db, remote: remote, scope: scope),
    photoSync: PhotoSync(
      db: db,
      remote: photos,
      store: ref.watch(recipePhotoStoreProvider),
      scope: scope,
    ),
    legacyMover: LegacyMover(db),
    refreshSession: () => _refreshSession(ref),
    onUnauthorized: () =>
        ref.read(authControllerProvider.notifier).sessionExpired(),
  );
  ref.onDispose(engine.stop);
  unawaited(engine.onStart());
  return engine;
});

/// Stanje čuvanja u nalogu za "Profil".
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine == null ? Stream.value(const AllSaved()) : engine.watchStatus();
});

/// Broj prebačenih starih zapisa, kad stignu na server.
final movedSavedProvider = StreamProvider<int>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine == null ? const Stream.empty() : engine.watchMovedSaved();
});

final syncPhaseProvider = StreamProvider<SyncPhase?>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine == null ? Stream.value(null) : engine.watchPhase();
});

final keyStoreProvider = Provider<KeyStore>(
  (ref) => SecureKeyStore(storage: ref.watch(secretStorageProvider)),
);

/// Ugrađeni ključevi iz `--dart-define-from-file=secrets.json`.
final builtInKeysProvider = Provider<BuiltInKeys>(
  (ref) => BuiltInKeys.fromEnvironment(),
);

/// Sopstveni ključ pa ugrađeni. Kasnije ga menja Cloudflare proxy.
final keySourceProvider = Provider<KeySource>(
  (ref) => LayeredKeySource(
    ref.watch(keyStoreProvider),
    ref.watch(builtInKeysProvider),
  ),
);

class ChainConfigNotifier extends Notifier<ChainConfig> {
  @override
  ChainConfig build() => ChainConfig.defaults;

  // Čuvanje u bazi dolazi sa ekranom "AI modeli" (Faza 7).
  void set(ChainConfig config) => state = config;
}

final chainConfigProvider = NotifierProvider<ChainConfigNotifier, ChainConfig>(
  ChainConfigNotifier.new,
);

final chatClientProvider = Provider<OpenAICompatibleClient>(
  (ref) => OpenAICompatibleClient(),
);

final aiRouterProvider = Provider<AIRouter>(
  (ref) => AIRouter(
    config: () => ref.read(chainConfigProvider),
    client: ref.watch(chatClientProvider),
    keys: ref.watch(keySourceProvider),
    status: DriftModelStatusStore(ref.watch(databaseProvider)),
  ),
);

final recipeAIProvider = Provider<RecipeAI>(
  (ref) => RecipeAI(ref.watch(aiRouterProvider)),
);

final mealPlanAIProvider = Provider<MealPlanAI>(
  (ref) => MealPlanAI(ref.watch(aiRouterProvider)),
);

/// Lista prijavljenog domaćinstva; demo koristi zasebnu bazu u memoriji.
final shoppingRepositoryProvider = Provider<ShoppingRepository>(
  (ref) => ShoppingRepository(
    ref.watch(databaseProvider),
    scope: ref.watch(accountScopeProvider) ?? noAccountScope,
    writer: ref.watch(syncedWriterProvider),
    clock: ref.watch(clockProvider),
  ),
);
