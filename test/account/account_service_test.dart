import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:tavli/account/account_api.dart';
import 'package:tavli/account/account_service.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/account/auth_gateway.dart';
import 'package:tavli/account/supabase_client.dart';
import 'package:tavli/account/supabase_config.dart';
import 'package:tavli/ai/ai_models.dart';
import 'package:tavli/ai/key_store.dart';
import 'package:tavli/data/allergen_repository.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/taste_profile_repository.dart';
import 'package:tavli/domain/account.dart';
import 'package:tavli/domain/allergen_group.dart';
import 'package:tavli/domain/cuisine_preferences.dart';
import 'package:tavli/domain/dish_kind_preferences.dart';
import 'package:tavli/domain/recipe_labels.dart';
import 'package:tavli/sync/synced_writer.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_photo_store.dart';
import '../helpers/fake_secret_storage.dart';
import '../helpers/fake_supabase.dart';

void main() {
  group('SupabaseAccountApi.fetch', () {
    late SupabaseClient client;
    late List<http.Request> requests;
    late http.Response Function(http.Request) handler;

    setUp(() async {
      requests = [];
      client = createSupabaseClient(
        const SupabaseConfig(url: fakeUrl, anonKey: fakeAnonKey),
        secrets: MapSecretStorage(),
        httpClient: mockHttp((r) {
          requests.add(r);
          return handler(r);
        }),
      );
      // Važeća sesija se vraća bez mreže.
      handler = (_) => throw StateError('nema mreže u testu');
      await client.auth.recoverSession(jsonEncode(sessionBody()));
    });
    tearDown(() => client.dispose());

    SupabaseAccountApi api() =>
        SupabaseAccountApi(client, retryDelay: Duration.zero);

    final profile = {
      'id': 'u1',
      'email': 'ana@mail.com',
      'display_name': 'Ana Petrović',
    };
    final membership = {
      'household_id': 'h1',
      'role': 'owner',
      'households': {'name': 'Moje domaćinstvo'},
    };

    test('čita svoj profil, članstvo i domaćinstvo', () async {
      handler = (r) => jsonResponse(
        r.url.path.endsWith('/profiles') ? [profile] : [membership],
      );
      final a = await api().fetch();
      expect(a.userId, 'u1');
      expect(a.displayName, 'Ana Petrović');
      expect(a.householdId, 'h1');
      expect(a.householdName, 'Moje domaćinstvo');
      expect(a.role, 'owner');
      final p = requests.firstWhere((r) => r.url.path.endsWith('/profiles'));
      expect(p.url.queryParameters['id'], 'eq.u1');
      final m = requests.firstWhere(
        (r) => r.url.path.endsWith('/household_members'),
      );
      expect(m.url.queryParameters['user_id'], 'eq.u1');
    });

    test('ponavlja dok red iz okidača ne postane vidljiv', () async {
      var calls = 0;
      handler = (r) {
        if (r.url.path.endsWith('/household_members')) {
          return jsonResponse(++calls < 3 ? <Object>[] : [membership]);
        }
        return jsonResponse([profile]);
      };
      final a = await api().fetch();
      expect(a.householdId, 'h1');
      expect(calls, 3);
    });

    test('posle tri pokušaja bez reda: nedostupno', () async {
      handler = (r) => jsonResponse(<Object>[]);
      await expectLater(api().fetch(), throwsA(isA<Unavailable>()));
    });

    test('bez mreže i 401', () async {
      handler = (_) => throw const SocketException('nema mreže');
      await expectLater(api().fetch(), throwsA(isA<Offline>()));
      handler = (_) =>
          jsonResponse({'code': 'PGRST301', 'message': 'JWT expired'}, 401);
      await expectLater(api().fetch(), throwsA(isA<SessionRevoked>()));
    });
  });

  group('SupabaseAccountApi.removeHouseholdMember', () {
    late SupabaseClient client;
    late List<http.Request> requests;

    setUp(() async {
      requests = [];
      client = createSupabaseClient(
        const SupabaseConfig(url: fakeUrl, anonKey: fakeAnonKey),
        secrets: MapSecretStorage(),
        httpClient: mockHttp((r) {
          requests.add(r);
          return jsonResponse({'status': 'removed'});
        }),
      );
      await client.auth.recoverSession(jsonEncode(sessionBody()));
    });
    tearDown(() => client.dispose());

    test('šalje ID člana i vraća status servera', () async {
      final api = SupabaseAccountApi(client, retryDelay: Duration.zero);
      expect(await api.removeHouseholdMember('u2'), 'removed');
      final r = requests.single;
      expect(r.url.path, endsWith('/rpc/remove_household_member'));
      expect(jsonDecode(r.body), {'member_id': 'u2'});
    });
  });

  group('AccountService', () {
    late AppDatabase db;
    late FakeBackend backend;
    late AccountService service;
    var kicks = 0;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      backend = FakeBackend();
      kicks = 0;
      service = AccountService(
        db,
        backend.accounts,
        clock: () => DateTime.utc(2026),
        onChange: () => kicks++,
      );
    });
    tearDown(() => db.close());

    Future<AuthSession> signIn() =>
        backend.auth.verifyCode('ana@mail.com', FakeServer.code);

    test('loadOrFetch upisuje nalog na uređaj, pa radi bez mreže', () async {
      final s = await signIn();
      final a = await service.loadOrFetch(s);
      expect(a.householdName, 'Moje domaćinstvo');
      expect(a.displayName, isNull);
      final row = (await db.select(db.accounts).get()).single;
      expect(row.userId, s.userId);
      expect(row.email, 'ana@mail.com');

      backend.server.offline = true;
      expect((await service.loadOrFetch(s)).userId, s.userId);
      expect(await service.cached('nema'), isNull);
    });

    test('saveName skida razmake, čuva lokalno i šalje profil', () async {
      final a = await service.loadOrFetch(await signIn());
      final named = await service.saveName(a, '  Ana Petrović ');
      expect(named.displayName, 'Ana Petrović');
      expect((await service.cached(a.userId))!.displayName, 'Ana Petrović');
      final e = (await db.select(db.syncOutbox).get()).single;
      expect('${e.entity}:${e.recordId}:${e.op}', 'profile:${a.userId}:upsert');
      expect(e.accountId, a.userId);
      expect(kicks, 1);
    });

    test('promena opsega čuva profil i izdvaja stare izmene', () async {
      final account = await service.loadOrFetch(await signIn());
      await service.saveName(account, 'Ana');
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              accountId: account.userId,
              entity: 'photo',
              recordId: 'old.jpg',
              op: 'photoDelete',
              createdAt: DateTime.utc(2026),
            ),
          );
      await db
          .into(db.syncCursors)
          .insert(
            SyncCursorsCompanion.insert(
              accountId: account.userId,
              entity: 'recipe',
              updatedAt: DateTime.utc(2026),
              lastId: 'old',
            ),
          );
      backend.server.households[account.userId] = 'new-home';

      final updated = await service.refreshMembership(account);

      expect(updated.householdId, 'new-home');
      expect(updated.displayName, 'Ana');
      expect(await db.select(db.syncCursors).get(), isEmpty);
      final outbox = await db.select(db.syncOutbox).get();
      expect(
        outbox.firstWhere((row) => row.entity == 'photo').state,
        OutboxState.quarantined,
      );
      expect(
        outbox.firstWhere((row) => row.entity == 'profile').state,
        'pending',
      );
      expect((await service.cached(account.userId))?.householdId, 'new-home');
    });

    test('promena domaćinstva čuva lične preference i alergene', () async {
      final account = await service.loadOrFetch(await signIn());
      final scope = AccountScope(
        userId: account.userId,
        householdId: account.householdId,
      );
      final writer = SyncedWriter(db, accountId: account.userId);
      final taste = TasteProfileRepository(db, scope: scope, writer: writer);
      await taste.saveDishPreferences(
        DishKindPreferences(liked: {DishKind.soup}),
      );
      await taste.saveCuisinePreferences(
        CuisinePreferences(disliked: {Cuisine.italian}),
      );
      await AllergenRepository(
        db,
        scope: scope,
        writer: writer,
      ).saveSelection({AllergenGroup.milk});
      await writer.upsert('favorite', '${account.userId}:old-recipe');
      backend.server.households[account.userId] = 'new-home';

      final updated = await service.refreshMembership(account);

      final moved = AccountScope(
        userId: account.userId,
        householdId: updated.householdId,
      );
      final movedTaste = TasteProfileRepository(
        db,
        scope: moved,
        writer: writer,
      );
      expect((await movedTaste.getDishPreferences()).liked, {DishKind.soup});
      expect((await movedTaste.getCuisinePreferences()).disliked, {
        Cuisine.italian,
      });
      expect(
        await AllergenRepository(
          db,
          scope: moved,
          writer: writer,
        ).getSelection(),
        {AllergenGroup.milk},
      );
      final states = {
        for (final row in await db.select(db.syncOutbox).get())
          row.entity: row.state,
      };
      // Unsent preference changes still upload; an old-recipe favorite does not.
      expect(states['taste_profile'], OutboxState.pending);
      expect(states['allergen_selection'], OutboxState.pending);
      expect(states['favorite'], OutboxState.quarantined);
    });

    test(
      'uklonjeni član dobija novo domaćinstvo i izdvaja stare izmene',
      () async {
        final owner = await service.loadOrFetch(await signIn());
        final memberId = backend.server.userFor('ivan@mail.com');
        backend.server.households[memberId] = owner.householdId;

        expect(
          await service.removeHouseholdMember(owner.userId),
          'invalid_request',
        );
        expect(await service.removeHouseholdMember('nepoznat'), 'not_allowed');
        expect(await service.removeHouseholdMember(memberId), 'removed');
        expect(await service.removeHouseholdMember(memberId), 'not_allowed');
        expect(backend.server.households[owner.userId], owner.householdId);

        await backend.auth.signOutLocal();
        final member = await service.loadOrFetch(
          await backend.auth.verifyCode('ivan@mail.com', FakeServer.code),
        );
        expect(member.householdId, isNot(owner.householdId));

        // Uređaj člana još misli da je u starom domaćinstvu i ima izmene.
        await (db.update(db.accounts)..where((t) => t.userId.equals(memberId)))
            .write(AccountsCompanion(householdId: Value(owner.householdId)));
        final stale = (await service.cached(memberId))!;
        await db
            .into(db.syncOutbox)
            .insert(
              SyncOutboxCompanion.insert(
                accountId: memberId,
                entity: 'recipe',
                recordId: 'queued',
                op: 'upsert',
                createdAt: DateTime.utc(2026),
              ),
            );

        final updated = await service.refreshMembership(stale);

        expect(updated.householdId, 'home-$memberId');
        final row = await (db.select(
          db.syncOutbox,
        )..where((t) => t.accountId.equals(memberId))).getSingle();
        expect(row.state, OutboxState.quarantined);
        expect(row.lastError, 'household_changed');
      },
    );

    group('red za slanje pre prelaska', () {
      Future<void> queue(Account account, String state) => db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              accountId: account.userId,
              entity: 'recipe',
              recordId: state,
              op: 'upsert',
              createdAt: DateTime.utc(2026),
              state: Value(state),
              lastError: Value(state == OutboxState.rejected ? '42501' : null),
            ),
          );

      Future<HouseholdJoinResult> confirm(
        Account account, {
        bool skip = false,
      }) => service.confirmHouseholdJoin(
        account: account,
        token: 'test-token',
        recipeChoice: JoinRecipeChoice.leaveRecipes,
        acknowledgeSourceDeletion: true,
        operationId: 'test-operation',
        proceedWithoutPendingWrites: skip,
      );

      test('čeka upise na redu i one čije slanje već traje', () async {
        final account = await service.loadOrFetch(await signIn());
        for (final state in [OutboxState.pending, OutboxState.sending]) {
          await queue(account, state);
          expect((await confirm(account)).status, 'pending_sync');
          expect(backend.accounts.joinCalls, 0);
          await db.delete(db.syncOutbox).go();
        }
      });

      test('odbijen upis čuva razlog i ne blokira prelazak', () async {
        final account = await service.loadOrFetch(await signIn());
        backend.accounts.joinTargetHousehold = 'new-home';
        await queue(account, OutboxState.rejected);

        expect((await confirm(account)).status, 'joined');
        final row = await db.select(db.syncOutbox).getSingle();
        expect(row.state, OutboxState.quarantined);
        expect(row.lastError, '42501');
      });

      test(
        'preskakanje čuva izmene do potvrde i ostavlja lične upise na redu',
        () async {
          final account = await service.loadOrFetch(await signIn());
          backend.accounts.joinTargetHousehold = 'new-home';
          backend.accounts.joinFailureStatus = 'unavailable';
          await queue(account, OutboxState.pending);
          await service.saveName(account, 'Ana');

          expect((await confirm(account, skip: true)).status, 'unavailable');
          expect(
            (await service.cached(account.userId))?.householdId,
            account.householdId,
          );
          expect(
            (await db.select(db.syncOutbox).get()).map((row) => row.state),
            everyElement(OutboxState.pending),
          );

          backend.accounts.joinFailureStatus = null;
          expect((await confirm(account, skip: true)).status, 'joined');
          final entries = await db.select(db.syncOutbox).get();
          final recipe = entries.firstWhere((row) => row.entity == 'recipe');
          expect(recipe.state, OutboxState.quarantined);
          expect(recipe.lastError, 'household_changed');
          expect(
            entries.firstWhere((row) => row.entity == 'profile').state,
            OutboxState.pending,
          );
        },
      );
    });

    test('prazno i predugo ime se odbija', () async {
      final a = await service.loadOrFetch(await signIn());
      expect(() => service.saveName(a, '   '), throwsArgumentError);
      expect(
        () => service.saveName(a, 'a' * (maxNameLength + 1)),
        throwsArgumentError,
      );
      expect(await db.select(db.syncOutbox).get(), isEmpty);
    });

    test('postojeći nalog sa imenom ne traži ime', () async {
      final uid = backend.server.userFor('ana@mail.com');
      backend.server.profiles[uid]!['display_name'] = 'Ana';
      final a = await service.loadOrFetch(await signIn());
      expect(a.hasName, isTrue);
      expect(a.displayName, 'Ana');
    });
  });

  group('brisanje naloga', () {
    late AppDatabase db;
    late FakeBackend backend;
    late FakePhotoStore photos;
    late InMemoryKeyStore keys;
    late AccountService service;
    late Account a;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      backend = FakeBackend();
      photos = FakePhotoStore();
      keys = InMemoryKeyStore({AIProvider.groq: 'gsk_fake'});
      service = AccountService(
        db,
        backend.accounts,
        photos: photos,
        keys: keys,
      );
      a = await service.loadOrFetch(
        await backend.auth.verifyCode('ana@mail.com', FakeServer.code),
      );
      final t = DateTime.utc(2026);
      Future<void> recipe(String id, String home, String? image) => db
          .into(db.recipes)
          .insert(
            RecipesCompanion.insert(
              id: id,
              title: id,
              servings: 1,
              source: 'manual',
              ingredientsJson: '[]',
              stepsJson: '[]',
              createdAt: t,
              updatedAt: t,
              imagePath: Value(image),
              householdId: Value(home),
            ),
          );
      photos.saved['recipe_photos/moja.jpg'] = Uint8List(1);
      photos.saved['recipe_photos/stara.jpg'] = Uint8List(1);
      photos.saved['recipe_photos/tudja.jpg'] = Uint8List(1);
      await recipe('moj', a.householdId, 'recipe_photos/moja.jpg');
      await recipe('tudji', 'drugi-dom', 'recipe_photos/tudja.jpg');
      await db
          .into(db.recipeVersions)
          .insert(
            RecipeVersionsCompanion.insert(
              id: 'v1',
              recipeId: 'moj',
              recipeJson: '{"imagePath":"recipe_photos/stara.jpg"}',
              createdAt: t,
              householdId: Value(a.householdId),
            ),
          );
      await db
          .into(db.ratings)
          .insert(
            RatingsCompanion.insert(
              id: 'g1',
              recipeId: 'moj',
              stars: 5,
              cookedAt: t,
              userId: Value(a.userId),
            ),
          );
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              accountId: a.userId,
              entity: 'recipe',
              recordId: 'moj',
              op: 'upsert',
              createdAt: t,
            ),
          );
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              accountId: 'drugi',
              entity: 'recipe',
              recordId: 'tudji',
              op: 'upsert',
              createdAt: t,
            ),
          );
      await db
          .into(db.syncCursors)
          .insert(
            SyncCursorsCompanion.insert(
              accountId: a.userId,
              entity: 'recipe',
              updatedAt: t,
              lastId: 'moj',
            ),
          );
      // Nabavka: izvor, doprinos i raspodela u oba domaćinstva.
      for (final (suffix, home) in [
        ('moj', a.householdId),
        ('tudj', 'drugi-dom'),
      ]) {
        await db
            .into(db.shoppingSources)
            .insert(
              ShoppingSourcesCompanion.insert(
                id: 's-$suffix',
                listId: 'l-$suffix',
                kind: 'recipePreparation',
                recipeSnapshotJson: const Value('{}'),
                servings: const Value(2),
                createdAt: t,
                householdId: Value(home),
              ),
            );
        await db
            .into(db.shoppingContributions)
            .insert(
              ShoppingContributionsCompanion.insert(
                id: 'c-$suffix',
                sourceId: 's-$suffix',
                ingredientKey: 'luk',
                unitGroup: 'mass',
                baseUnit: 'g',
                micros: const Value(1),
                name: 'luk',
                category: 'ostalo',
                householdId: Value(home),
              ),
            );
        await db
            .into(db.supplyAllocations)
            .insert(
              SupplyAllocationsCompanion.insert(
                id: 'a-$suffix',
                contributionId: 'c-$suffix',
                pantryItemId: Value('o-$suffix'),
                micros: const Value(1),
                createdAt: t,
                householdId: Value(home),
              ),
            );
      }
      await db
          .into(db.appSettings)
          .insert(AppSettingsCompanion.insert(key: 'theme', value: 'dark'));
      await db
          .into(db.modelStatuses)
          .insert(
            ModelStatusesCompanion.insert(provider: 'gemini', model: 'm'),
          );
    });
    tearDown(() => db.close());

    test('brisanje naloga briše kućni katalog, deljeni ostaje', () async {
      final t = DateTime.utc(2026);
      Future<void> food(String id, String? home) => db
          .into(db.foods)
          .insert(
            FoodsCompanion.insert(
              id: id,
              householdId: Value(home),
              slug: id,
              name: id,
              category: 'Ostalo',
              baseUnit: 'gram',
              createdAt: t,
              updatedAt: t,
            ),
          );
      Future<void> alias(String id, String foodId, String? home) => db
          .into(db.foodAliases)
          .insert(
            FoodAliasesCompanion.insert(
              id: id,
              foodId: foodId,
              householdId: Value(home),
              alias: id,
              aliasNormalized: id,
              createdAt: t,
              updatedAt: t,
            ),
          );
      await food('deljena', null);
      await alias('deljeni', 'deljena', null);
      await food('moja', a.householdId);
      await alias('moj-alias', 'deljena', a.householdId);
      await food('tudja', 'drugi-dom');

      await service.wipeLocal(a.userId);
      expect([
        for (final r in await db.select(db.foods).get()) r.id,
      ], unorderedEquals(['deljena', 'tudja']));
      expect(
        [for (final r in await db.select(db.foodAliases).get()) r.id],
        ['deljeni'],
      );
    });

    test('posle uspeha na serveru briše sve od naloga na uređaju', () async {
      await db
          .into(db.recipeEmbeddings)
          .insert(
            RecipeEmbeddingsCompanion.insert(
              recipeId: 'r-a',
              householdId: a.householdId,
              contentHash: 'hash-a',
              model: 'text-embedding-3-small',
              vectorJson: '[0.1]',
              createdAt: DateTime.utc(2026),
            ),
          );
      await db
          .into(db.recipeEmbeddings)
          .insert(
            RecipeEmbeddingsCompanion.insert(
              recipeId: 'r-other',
              householdId: 'drugi-dom',
              contentHash: 'hash-other',
              model: 'text-embedding-3-small',
              vectorJson: '[0.2]',
              createdAt: DateTime.utc(2026),
            ),
          );
      await service.deleteAccount(a);

      expect(backend.server.profiles.containsKey(a.userId), isFalse);
      expect(
        [for (final r in await db.select(db.recipes).get()) r.id],
        ['tudji'],
      );
      expect(await db.select(db.recipeVersions).get(), isEmpty);
      expect(
        [
          for (final row in await db.select(db.recipeEmbeddings).get())
            row.recipeId,
        ],
        ['r-other'],
      );
      expect(await db.select(db.ratings).get(), isEmpty);
      // Nabavka drugog domaćinstva ostaje.
      expect(
        [for (final r in await db.select(db.shoppingSources).get()) r.id],
        ['s-tudj'],
      );
      expect(
        [for (final r in await db.select(db.shoppingContributions).get()) r.id],
        ['c-tudj'],
      );
      expect(
        [for (final r in await db.select(db.supplyAllocations).get()) r.id],
        ['a-tudj'],
      );
      expect(
        [for (final e in await db.select(db.syncOutbox).get()) e.accountId],
        ['drugi'],
      );
      expect(await db.select(db.syncCursors).get(), isEmpty);
      expect(await db.select(db.accounts).get(), isEmpty);
      expect(photos.saved.keys, ['recipe_photos/tudja.jpg']);
      expect(await keys.list(), isEmpty);
      // Tema i pauze modela ostaju.
      expect(await db.select(db.appSettings).get(), hasLength(1));
      expect(await db.select(db.modelStatuses).get(), hasLength(1));
    });

    for (final (failure, name) in [
      (const DeleteOffline(), 'bez mreže'),
      (const DeleteServerError(), 'greška servera'),
    ]) {
      test('$name: ništa se ne briše', () async {
        if (failure is DeleteOffline) {
          backend.server.offline = true;
        } else {
          backend.accounts.deleteFails = failure;
        }
        await expectLater(
          service.deleteAccount(a),
          throwsA(isA<DeleteFailure>()),
        );
        expect(await db.select(db.recipes).get(), hasLength(2));
        expect(await db.select(db.accounts).get(), hasLength(1));
        expect(await db.select(db.syncOutbox).get(), hasLength(2));
        expect(photos.saved, hasLength(3));
        expect(await keys.list(), hasLength(1));
      });
    }
  });
}
