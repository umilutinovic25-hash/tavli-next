import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/account/auth_gateway.dart';
import 'package:tavli/account/session_store.dart';
import 'package:tavli/ai/ai_models.dart';
import 'package:tavli/ai/chat_client.dart';
import 'package:tavli/ai/key_store.dart';
import 'package:tavli/app/app.dart';
import 'package:tavli/app/router.dart' show tabs;
import 'package:tavli/data/database.dart';
import 'package:tavli/data/recipe_repository.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/features/recipes/keep_screen_on.dart';
import 'package:tavli/features/recipes/photo_picker.dart';
import 'package:tavli/features/recipes/recipe_providers.dart';
import 'package:tavli/providers.dart';
import 'package:tavli/sync/synced_writer.dart';

import 'fake_adapter.dart';
import 'fake_backend.dart';
import 'fake_photo_store.dart';
import 'fake_secret_storage.dart';

/// Naziv izabranog taba (gornja traka pokazuje samo naziv aplikacije).
String currentTab(WidgetTester tester) =>
    tabs[tester
            .widget<StatefulNavigationShell>(
              find.byType(StatefulNavigationShell),
            )
            .currentIndex]
        .label;

/// E-pošta naloga pod kojim testovi rade (prijavljen po difoltu).
const testEmail = 'ana@tavli.test';

const phone = Size(400, 800);
const wide = Size(1200, 800);

/// Mala prava slika (PNG); smanjivanje je u testovima isključeno.
final fakePhoto = img.encodePng(img.Image(width: 4, height: 4));

class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker({this.canUseCamera = true});

  @override
  final bool canUseCamera;

  /// Šta sledeći izbor vraća (null = korisnik je odustao).
  Uint8List? next;
  final calls = <bool>[];

  @override
  Future<Uint8List?> pick({required bool camera}) async {
    calls.add(camera);
    return next;
  }
}

/// Odgovor AI-ja (OpenAI oblik) sa datim JSON-om.
(int, String, Map<String, List<String>>) aiAnswer(Map<String, dynamic> json) =>
    (
      200,
      jsonEncode({
        'choices': [
          {
            'message': {'content': jsonEncode(json)},
          },
        ],
      }),
      {},
    );

Map<String, dynamic> recipeJson(String title, {int servings = 2}) => {
  'title': title,
  'servings': servings,
  'prepMinutes': 30,
  'ingredients': [
    {
      'name': 'crni luk',
      'quantity': 0.5,
      'unit': 'kg',
      'category': 'voće i povrće',
    },
    {'name': 'biber', 'category': 'začini i sosovi'},
  ],
  'steps': ['Iseckati luk.', 'Kuvati.'],
};

Recipe sampleRecipe(
  String id,
  String title, {
  DateTime? createdAt,
  RecipeSource source = RecipeSource.manual,
}) => Recipe(
  id: id,
  title: title,
  servings: 4,
  prepMinutes: 45,
  ingredients: const [
    Ingredient(name: 'biber', category: 'začini i sosovi'),
    Ingredient(
      name: 'kupus',
      quantity: 0.5,
      unit: 'kg',
      category: 'voće i povrće',
    ),
  ],
  steps: const ['Umotati.', 'Kuvati.'],
  source: source,
  createdAt: createdAt ?? DateTime.utc(2026),
);

/// Pamti da li je ekran trenutno zadržan upaljen.
class FakeWakeLock implements ScreenWakeLock {
  bool on = false;
  bool fail = false;

  @override
  Future<void> enable() async {
    if (fail) throw Exception('nije podržano');
    on = true;
  }

  @override
  Future<void> disable() async => on = false;
}

class TestApp {
  TestApp(this.db, this.photos, this.picker, this.adapter, this.backend)
    : session = backend.auth.sessionFor(testEmail);

  final wakeLock = FakeWakeLock();

  final AppDatabase db;
  final FakePhotoStore photos;
  final FakePhotoPicker picker;
  final FakeAdapter adapter;
  final FakeBackend backend;
  final secrets = MapSecretStorage();
  final keys = InMemoryKeyStore();

  /// Sat za prijavu (odbrojavanje "Pošalji ponovo"); test ga pomera.
  DateTime now = DateTime(2026, 10, 30, 12);

  /// Sesija test naloga (na serveru postoji od početka).
  final AuthSession session;

  AccountScope get scope => AccountScope(
    userId: session.userId,
    householdId: backend.server.households[session.userId]!,
  );

  RecipeRepository get repo => RecipeRepository(
    db,
    photos,
    writer: SyncedWriter(db, accountId: scope.userId),
    scope: scope,
  );

  /// Nalog kao da je već bio prijavljen na uređaju (sesija + keš).
  Future<void> signIn({String? name = 'Ana Petrović'}) async {
    secrets.values[SessionStore.key] = session.json;
    // Server ima isto ime kao uređaj (preuzimanje profila ga ne briše).
    backend.server.profiles[scope.userId]!['display_name'] = name;
    await db
        .into(db.accounts)
        .insertOnConflictUpdate(
          AccountsCompanion.insert(
            userId: scope.userId,
            email: testEmail,
            displayName: Value(name),
            householdId: scope.householdId,
            householdName: 'Moje domaćinstvo',
            role: 'owner',
            createdAt: DateTime.utc(2026),
          ),
        );
  }

  /// Naslovi sačuvanih recepata. Bez drift tokova: njihovi tajmeri ne
  /// rade dok se test ne pumpa.
  Future<List<String>> titles() async => [
    for (final r in await db.select(db.recipes).get()) r.title,
  ];
}

/// Cela aplikacija sa bazom u memoriji, lažnim AI-jem (ugrađeni test ključ)
/// i lažnim izborom slike.
Future<TestApp> pumpTavli(
  WidgetTester tester, {
  Size size = phone,
  String location = '/recipes',
  List<Recipe> recipes = const [],
  List<(int, String, Map<String, List<String>>)> ai = const [],
  bool canUseCamera = true,
  bool signedIn = true,
  bool intro = false,
  bool settle = true,
  String? name = 'Ana Petrović',
  FakeBackend? backend,
  List<Override> overrides = const [],
  Future<void> Function(AppDatabase db)? setup,
  Map<String, String> settings = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = AppDatabase(NativeDatabase.memory());
  final app = TestApp(
    db,
    FakePhotoStore(),
    FakePhotoPicker(canUseCamera: canUseCamera),
    FakeAdapter([...ai]),
    backend ?? FakeBackend(),
  );
  if (signedIn) await app.signIn(name: name);
  for (final r in recipes) {
    await app.repo.create(r);
  }
  await setup?.call(db);
  for (final MapEntry(:key, :value) in settings.entries) {
    await db
        .into(db.appSettings)
        .insert(AppSettingsCompanion.insert(key: key, value: value));
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sessionStoreProvider.overrideWithValue(SessionStore(app.secrets)),
        authGatewayProvider.overrideWithValue(app.backend.auth),
        accountApiProvider.overrideWithValue(app.backend.accounts),
        authClockProvider.overrideWithValue(() => app.now),
        syncRemoteProvider.overrideWithValue(app.backend.sync),
        photoRemoteProvider.overrideWithValue(app.backend.photos),
        householdInviteRemoteProvider.overrideWithValue(app.backend.invites),
        householdMembershipRemoteProvider.overrideWithValue(
          app.backend.membership,
        ),
        keyStoreProvider.overrideWithValue(app.keys),
        builtInKeysProvider.overrideWithValue(
          const BuiltInKeys({AIProvider.gemini: 'fake-test-key'}),
        ),
        chatClientProvider.overrideWithValue(
          OpenAICompatibleClient(
            dio: Dio()..httpClientAdapter = app.adapter,
            transientRetryDelay: Duration.zero,
          ),
        ),
        recipePhotoStoreProvider.overrideWithValue(app.photos),
        photoPickerProvider.overrideWithValue(app.picker),
        photoResizerProvider.overrideWithValue((bytes) async => bytes),
        ...overrides,
        screenWakeLockProvider.overrideWithValue(app.wakeLock),
      ],
      child: TavliApp(initialLocation: location, intro: intro),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  _current = app;
  return app;
}

TestApp? _current;

/// Skroluje do dugmeta pa ga pritiska.
Future<void> tapButton(WidgetTester tester, String text) async {
  await tester.ensureVisible(button(text));
  await tester.pumpAndSettle();
  await tester.tap(button(text));
  await tester.pumpAndSettle();
}

/// Dugme (bilo koje Material dugme) sa datim tekstom.
Finder button(String text) => find.ancestor(
  of: find.text(text),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

/// testWidgets koji na kraju skida aplikaciju, da drift tokovi i
/// riverpod zatvore tajmere pre provere na kraju testa.
void testTavli(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await _current?.db.close();
    _current = null;
  });
}

/// testWidgets za samostalan widget nad drift bazom (bez cele aplikacije):
/// na kraju skida stablo i pušta tajmere, da drift tokovi i riverpod
/// `autoDispose` ne ostave tajmer posle testa. Bazu zatvara `tearDown`
/// pozivaoca.
void testDbWidgets(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
