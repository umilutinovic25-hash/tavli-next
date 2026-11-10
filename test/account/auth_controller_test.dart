import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/account/auth_gateway.dart';
import 'package:tavli/account/session_store.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/providers.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_secret_storage.dart';

void main() {
  late AppDatabase db;
  late FakeBackend backend;
  late MapSecretStorage secrets;
  late ProviderContainer c;
  var now = DateTime(2026, 10, 30, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    backend = FakeBackend();
    secrets = MapSecretStorage();
    now = DateTime(2026, 10, 30, 12);
    c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sessionStoreProvider.overrideWithValue(SessionStore(secrets)),
        authGatewayProvider.overrideWithValue(backend.auth),
        accountApiProvider.overrideWithValue(backend.accounts),
        authClockProvider.overrideWithValue(() => now),
      ],
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  AuthState state() => c.read(authControllerProvider);
  AuthController ctrl() => c.read(authControllerProvider.notifier);

  Future<void> cacheAccount(AuthSession s, {String? name}) => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          userId: s.userId,
          email: s.email,
          displayName: Value(name),
          householdId: backend.server.households[s.userId]!,
          householdName: 'Moje domaćinstvo',
          role: 'owner',
          createdAt: now,
        ),
      );

  test('bez sačuvane sesije: odjavljen', () async {
    expect(state(), isA<Starting>());
    await ctrl().start();
    expect(state(), isA<SignedOut>());
    expect((state() as SignedOut).reason, isNull);
  });

  test('sačuvana sesija i keširan nalog: prijavljen bez mreže', () async {
    final s = backend.auth.sessionFor('ana@mail.com');
    secrets.values[SessionStore.key] = s.json;
    await cacheAccount(s, name: 'Ana');
    backend.server.offline = true;

    await ctrl().start();
    final st = state();
    expect(st, isA<SignedIn>());
    expect((st as SignedIn).account.displayName, 'Ana');
    expect(c.read(accountScopeProvider)?.userId, s.userId);
    await pumpEventQueue();
    // Obnova bez mreže ne odjavljuje.
    expect(state(), isA<SignedIn>());
    expect(secrets.values[SessionStore.key], s.json);
  });

  test('keširan nalog bez imena: korak sa imenom', () async {
    final s = backend.auth.sessionFor('ana@mail.com');
    secrets.values[SessionStore.key] = s.json;
    await cacheAccount(s);
    await ctrl().start();
    expect(state(), isA<NeedsName>());
    expect(c.read(accountScopeProvider), isNull);
  });

  test('slanje koda: CodeSent sa sređenom adresom, ništa se ne čuva', () async {
    await ctrl().start();
    await ctrl().sendCode(' Ana@Mail.com ');
    final st = state() as CodeSent;
    expect(st.email, 'ana@mail.com');
    expect(st.sentAt, now);
    expect(secrets.values, isEmpty);
    expect(backend.auth.sentCodes, ['ana@mail.com']);
  });

  test('ispravan kod: čuva sesiju, nov nalog traži ime', () async {
    await ctrl().start();
    await ctrl().sendCode('ana@mail.com');
    await ctrl().verify(FakeServer.code);
    final st = state() as NeedsName;
    expect(st.account.email, 'ana@mail.com');
    expect(st.account.householdName, 'Moje domaćinstvo');
    expect(st.account.roleLabel, 'Vlasnik');
    expect(secrets.values[SessionStore.key], isNotNull);
    expect(await db.select(db.accounts).get(), hasLength(1));
  });

  test('postojeći nalog sa imenom: odmah prijavljen', () async {
    final uid = backend.server.userFor('ana@mail.com');
    backend.server.profiles[uid]!['display_name'] = 'Ana Petrović';
    await ctrl().start();
    await ctrl().sendCode('ana@mail.com');
    await ctrl().verify('123 456');
    expect(state(), isA<SignedIn>());
  });

  test('promena e-pošte vraća na prvi korak', () async {
    await ctrl().start();
    await ctrl().sendCode('ana@mail.com');
    ctrl().changeEmail();
    expect(state(), isA<SignedOut>());
  });

  test('greške ostavljaju stanje i prenose razlog', () async {
    await ctrl().start();
    backend.auth.failNext = const RateLimited();
    await expectLater(
      ctrl().sendCode('ana@mail.com'),
      throwsA(isA<RateLimited>()),
    );
    expect(state(), isA<SignedOut>());

    await ctrl().sendCode('ana@mail.com');
    await expectLater(ctrl().verify('000000'), throwsA(isA<WrongCode>()));
    expect(state(), isA<CodeSent>());
    expect(secrets.values, isEmpty);

    backend.server.offline = true;
    await expectLater(ctrl().verify(FakeServer.code), throwsA(isA<Offline>()));
    expect(state(), isA<CodeSent>());
  });

  group('refreshAccount', () {
    Future<AuthSession> signedIn() async {
      final s = backend.auth.sessionFor('ana@mail.com');
      secrets.values[SessionStore.key] = s.json;
      await cacheAccount(s, name: 'Ana');
      await ctrl().start();
      await pumpEventQueue();
      return s;
    }

    test('prijavljen: novo članstvo postaje aktivno domaćinstvo', () async {
      final s = await signedIn();
      backend.server.addMember('home-9', s.userId);

      expect(await ctrl().refreshAccount(), isTrue);

      final st = state() as SignedIn;
      expect(st.account.householdId, 'home-9');
      expect(c.read(accountScopeProvider)?.householdId, 'home-9');
    });

    test('bez mreže vraća false i stanje ostaje', () async {
      final s = await signedIn();
      backend.server.addMember('home-9', s.userId);
      backend.server.offline = true;

      expect(await ctrl().refreshAccount(), isFalse);

      final st = state() as SignedIn;
      expect(st.account.householdId, backend.server.households[s.userId]);
    });

    test('pokretanje sa keširanim nalogom osvežava ga u pozadini', () async {
      final s = backend.auth.sessionFor('ana@mail.com');
      secrets.values[SessionStore.key] = s.json;
      await cacheAccount(s, name: 'Ana');
      backend.server.addMember('home-9', s.userId);

      await ctrl().start();
      expect((state() as SignedIn).account.householdId, isNot('home-9'));
      await pumpEventQueue();

      expect((state() as SignedIn).account.householdId, 'home-9');
    });

    test('odjavljen: ništa ne radi', () async {
      await ctrl().start();
      expect(await ctrl().refreshAccount(), isFalse);
      expect(state(), isA<SignedOut>());
    });
  });
}
