import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/account_service.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/sync/downloader.dart';
import 'package:tavli/sync/sync_engine.dart';
import 'package:tavli/sync/sync_epoch.dart';
import 'package:tavli/sync/sync_remote.dart';
import 'package:tavli/sync/synced_writer.dart';
import 'package:tavli/sync/uploader.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_photo_store.dart';

/// Posle pridruživanja zajednički podaci mogu biti stariji od pozicije
/// preuzimanja; osvežavanje naloga mora da vrati preuzimanje na početak.
/// Lažni server sa kukom pre svakog čitanja (za preplitanje u testu).
class _HookRemote implements SyncRemote {
  _HookRemote(this._inner, this.beforeFetch);

  final SyncRemote _inner;
  final Future<void> Function(String table) beforeFetch;

  @override
  Future<void> upsert(
    String table,
    List<Map<String, Object?>> rows, {
    String onConflict = 'id',
  }) => _inner.upsert(table, rows, onConflict: onConflict);

  @override
  Future<void> delete(
    String table,
    List<String> ids, {
    String idColumn = 'id',
  }) => _inner.delete(table, ids, idColumn: idColumn);

  @override
  Future<void> updateProfileName(String userId, String name) =>
      _inner.updateProfileName(userId, name);

  @override
  Future<List<Map<String, Object?>>> fetchSince(
    String table, {
    required int limit,
    String? since,
    String? afterId,
    String timeColumn = 'updated_at',
    String idColumn = 'id',
  }) async {
    await beforeFetch(table);
    return _inner.fetchSince(
      table,
      limit: limit,
      since: since,
      afterId: afterId,
      timeColumn: timeColumn,
      idColumn: idColumn,
    );
  }
}

void main() {
  late AppDatabase db;
  late FakeBackend backend;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Map<String, Object?> recipe(String id, String householdId) => {
    'id': id,
    'household_id': householdId,
    'title': id,
    'servings': 4,
    'prep_minutes': null,
    'source': 'manual',
    'ingredients': <Object>[],
    'steps': ['Kuvati.'],
    'image_path': null,
    'answered_by': null,
    'created_at': '2026-10-30T10:00:00.000Z',
  };

  Future<List<String>> localRecipes() async => [
    for (final r in await db.select(db.recipes).get()) r.id,
  ];

  test('pridruženi vidi zajednički recept stariji od svoje pozicije', () async {
    backend = FakeBackend();
    final ana = await backend.auth.verifyCode('ana@mail.com', FakeServer.code);
    final anaHome = backend.server.households[ana.userId]!;
    // Anin recept nastaje prvi (ranije vreme na serveru).
    backend.server.upsert('recipes', [recipe('anin', anaHome)], 'id');

    final marko = await backend.auth.verifyCode(
      'marko@mail.com',
      FakeServer.code,
    );
    final markoHome = backend.server.households[marko.userId]!;
    backend.server.upsert('recipes', [recipe('markov', markoHome)], 'id');

    final service = AccountService(db, backend.accounts);
    await service.loadOrFetch(marko);
    Downloader pull(String householdId) => Downloader(
      db: db,
      remote: backend.sync,
      scope: AccountScope(userId: marko.userId, householdId: householdId),
      // Na lažnom serveru upisi su sekundu jedan od drugog; u stvarnosti su
      // zajednički podaci stari danima, daleko van preklapanja od 60 s.
      overlap: Duration.zero,
    );
    await pull(markoHome).run();
    expect(await localRecipes(), ['markov']);

    // Marko se pridružuje Aninom domaćinstvu.
    backend.server.addMember(anaHome, marko.userId);

    // Bez osvežavanja naloga pozicija ostaje posle Aninog recepta.
    await pull(anaHome).run();
    expect(await localRecipes(), ['markov']);

    final fresh = await service.refresh();
    expect(fresh.householdId, anaHome);
    await pull(anaHome).run();
    expect((await localRecipes())..sort(), ['anin', 'markov']);
  });

  test('izmena napravljena pre prebacivanja ide u svoje domaćinstvo', () async {
    backend = FakeBackend();
    final ana = await backend.auth.verifyCode('ana@mail.com', FakeServer.code);
    final own = backend.server.households[ana.userId]!;
    final owner = backend.server.userFor('vlasnik@mail.com');
    final shared = backend.server.households[owner]!;
    backend.server.addMember(shared, ana.userId);
    final service = AccountService(db, backend.accounts);
    await service.loadOrFetch(ana);
    await service.setPreferredHousehold(ana.userId, own);
    await service.refresh();

    // Recept u ličnom domaćinstvu čeka slanje (npr. napravljen offline).
    await db
        .into(db.recipes)
        .insert(
          RecipesCompanion.insert(
            id: 'licni',
            title: 'Lični',
            servings: 1,
            source: 'manual',
            ingredientsJson: '[]',
            stepsJson: '[]',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            householdId: Value(own),
          ),
        );
    await SyncedWriter(db, accountId: ana.userId).upsert('recipe', 'licni');

    // Prebacivanje na zajedničko domaćinstvo pre slanja.
    await service.setPreferredHousehold(ana.userId, shared);
    final fresh = await service.refresh();
    expect(fresh.householdId, shared);

    await Uploader(
      db: db,
      remote: backend.sync,
      photos: backend.photos,
      photoStore: FakePhotoStore(),
      scope: AccountScope(userId: ana.userId, householdId: shared),
      refreshSession: () async => true,
    ).run();

    expect(backend.server.rows('recipes').single['household_id'], own);
  });

  test('osvežavanje usred preuzimanja ne vraća stari kursor', () async {
    backend = FakeBackend();
    final ana = await backend.auth.verifyCode('ana@mail.com', FakeServer.code);
    final own = backend.server.households[ana.userId]!;
    backend.server.upsert('recipes', [recipe('r1', own)], 'id');
    backend.server.upsert('recipes', [recipe('r2', own)], 'id');
    final owner = backend.server.userFor('vlasnik@mail.com');
    final epoch = SyncEpoch();
    final service = AccountService(db, backend.accounts, epoch: epoch);
    await service.loadOrFetch(ana);

    var recipeFetches = 0;
    final remote = _HookRemote(backend.sync, (table) async {
      // Posle prve stranice recepata stiže novo članstvo (drugi uređaj).
      if (table == 'recipes' && ++recipeFetches == 2) {
        backend.server.addMember(backend.server.households[owner]!, ana.userId);
        await service.refresh();
      }
    });
    final pull = Downloader(
      db: db,
      remote: remote,
      scope: AccountScope(userId: ana.userId, householdId: own),
      pageSize: 1,
      epoch: epoch,
    );

    await expectLater(pull.run(), throwsA(isA<CancelledSyncError>()));
    expect(await db.select(db.syncCursors).get(), isEmpty);
  });

  test('promena članstava pokreće preuzimanje, i dok jedno traje', () async {
    backend = FakeBackend();
    final ana = await backend.auth.verifyCode('ana@mail.com', FakeServer.code);
    final own = backend.server.households[ana.userId]!;
    final scope = AccountScope(userId: ana.userId, householdId: own);
    var profileFetches = 0;
    final gate = Completer<void>();
    final remote = _HookRemote(backend.sync, (table) async {
      if (table == 'profiles' && ++profileFetches == 1) await gate.future;
    });
    final engine = SyncEngine(
      db: db,
      scope: scope,
      uploader: Uploader(
        db: db,
        remote: backend.sync,
        photos: backend.photos,
        photoStore: FakePhotoStore(),
        scope: scope,
        refreshSession: () async => true,
      ),
      downloader: Downloader(db: db, remote: remote, scope: scope),
    );
    addTearDown(engine.stop);
    var changes = 0;
    final service = AccountService(
      db,
      backend.accounts,
      onMembershipsChanged: () {
        changes++;
        unawaited(engine.pull());
      },
    );
    await service.loadOrFetch(ana);
    changes = 0;

    final first = engine.pull();
    await pumpEventQueue();
    backend.server.addMember('drugi-dom', ana.userId);
    await service.refresh();
    await service.refresh();
    expect(changes, 1);
    gate.complete();
    await first;
    await pumpEventQueue();

    expect(profileFetches, 2);
  });
}
