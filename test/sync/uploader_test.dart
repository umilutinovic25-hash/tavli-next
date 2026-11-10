import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/sync/sync_remote.dart';
import 'package:tavli/sync/synced_writer.dart';
import 'package:tavli/sync/uploader.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_photo_store.dart';

void main() {
  late AppDatabase db;
  late FakeBackend backend;
  late FakePhotoStore photoStore;
  late AccountScope scope;
  late SyncedWriter writer;
  late Uploader uploader;
  var now = DateTime.utc(2026, 11, 1, 12);
  var refreshes = 0;
  var refreshOk = true;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    backend = FakeBackend();
    photoStore = FakePhotoStore();
    now = DateTime.utc(2026, 11, 1, 12);
    refreshes = 0;
    refreshOk = true;
    final s = await backend.auth.verifyCode('ana@mail.com', FakeServer.code);
    scope = AccountScope(
      userId: s.userId,
      householdId: backend.server.households[s.userId]!,
    );
    writer = SyncedWriter(db, accountId: scope.userId, clock: () => now);
    uploader = Uploader(
      db: db,
      remote: backend.sync,
      photos: backend.photos,
      photoStore: photoStore,
      scope: scope,
      refreshSession: () async {
        refreshes++;
        return refreshOk;
      },
      clock: () => now,
    );
  });
  tearDown(() => db.close());

  Future<void> addRecipe(String id, {String? image}) async {
    await db
        .into(db.recipes)
        .insertOnConflictUpdate(
          RecipesCompanion.insert(
            id: id,
            title: 'Recept $id',
            servings: 2,
            source: 'manual',
            ingredientsJson: '[]',
            stepsJson: '[]',
            createdAt: now,
            updatedAt: now,
            imagePath: Value(image),
            householdId: Value(scope.householdId),
          ),
        );
    await writer.upsert('recipe', id);
  }

  Future<void> addVersion(String id, String recipeId) async {
    await db
        .into(db.recipeVersions)
        .insert(
          RecipeVersionsCompanion.insert(
            id: id,
            recipeId: recipeId,
            recipeJson: '{}',
            createdAt: now,
            householdId: Value(scope.householdId),
          ),
        );
    await writer.upsert('recipe_version', id);
  }

  Future<List<OutboxRow>> outbox() => (db.select(
    db.syncOutbox,
  )..orderBy([(t) => OrderingTerm.asc(t.seq)])).get();

  Map<String, Map<String, Object?>> server(String table) =>
      backend.server.table(table);

  test('šalje redom, grupe do 100 istog entiteta i vrste', () async {
    for (var i = 0; i < 150; i++) {
      await addRecipe('r$i');
    }
    await addVersion('v1', 'r0');
    await addRecipe('r150');
    final res = await uploader.run();
    expect(res.sent, 152);
    expect(res.stoppedBy, isNull);
    expect(backend.server.calls, [
      'upsert:recipes:100',
      'upsert:recipes:50',
      'upsert:recipe_versions:1',
      'upsert:recipes:1',
    ]);
    expect(server('recipes'), hasLength(151));
    expect(server('recipes')['r0']!['household_id'], scope.householdId);
    expect(await outbox(), isEmpty);
  });

  test('brisanja idu kao id=in(…); posle upsert-a istog zapisa', () async {
    await addRecipe('a');
    await addRecipe('b');
    await uploader.run();
    await (db.delete(db.recipes)..where((t) => t.id.isIn(['a', 'b']))).go();
    await writer.delete('recipe', 'a');
    await writer.delete('recipe', 'b');
    backend.server.calls.clear();
    await uploader.run();
    expect(backend.server.calls, ['delete:recipes:2']);
    expect(server('recipes'), isEmpty);
    expect(server('deletions'), hasLength(2));
  });

  test('loš red u grupi: ostali se šalju, on se odlaže', () async {
    await addRecipe('a');
    await addRecipe('los');
    await addRecipe('c');
    backend.server.rejectIds.add('los');
    final res = await uploader.run();
    expect(res.rejected, 1);
    expect(res.stoppedBy, isNull);
    expect(server('recipes').keys, unorderedEquals(['a', 'c']));
    final left = (await outbox()).single;
    expect(left.recordId, 'los');
    expect(left.state, OutboxState.rejected);
    expect(left.lastError, '23514');
  });

  test('trajno odbijena izmena ne blokira kasnije', () async {
    await addRecipe('los');
    await addVersion('v1', 'los');
    backend.server.rejectIds.add('los');
    await uploader.run();
    expect(server('recipe_versions').keys, ['v1']);
    expect((await outbox()).single.state, OutboxState.rejected);
    // Odbijena se ne šalje ponovo.
    backend.server.calls.clear();
    await uploader.run();
    expect(backend.server.calls, isEmpty);
  });

  test('privremena greška zaustavlja slanje i čuva redosled', () async {
    await addRecipe('a');
    await addVersion('v1', 'a');
    backend.server.offline = true;
    final res = await uploader.run();
    expect(res.offline, isTrue);
    final rows = await outbox();
    expect(rows.map((r) => r.recordId), ['a', 'v1']);
    expect(rows.first.attempts, 1);
    expect(rows.first.lastError, 'offline');
    expect(rows.every((r) => r.state == OutboxState.pending), isTrue);

    backend.server.offline = false;
    expect((await uploader.run()).sent, 2);
    expect(await outbox(), isEmpty);
  });

  test('401: jedna obnova sesije pa ponovo', () async {
    await addRecipe('a');
    backend.server.failures.add(const UnauthorizedSyncError());
    final res = await uploader.run();
    expect(refreshes, 1);
    expect(res.stoppedBy, isNull);
    expect(server('recipes').keys, ['a']);
  });

  test('401 i odbijena obnova: zaustavlja, ništa se ne gubi', () async {
    await addRecipe('a');
    refreshOk = false;
    backend.server.failures.add(const UnauthorizedSyncError());
    final res = await uploader.run();
    expect(res.unauthorized, isTrue);
    expect(refreshes, 1);
    expect((await outbox()).single.state, OutboxState.pending);
  });

  test('upsert obrisanog zapisa se izbacuje', () async {
    await addRecipe('a');
    await (db.delete(db.recipes)..where((t) => t.id.equals('a'))).go();
    final res = await uploader.run();
    expect(res.sent, 0);
    expect(server('recipes'), isEmpty);
    expect(await outbox(), isEmpty);
  });

  test('slike posle podataka; neuspela slika ne zadržava recept', () async {
    final path = await photoStore.save(Uint8List.fromList([1, 2]));
    await writer.photoUpload(path);
    await addRecipe('a', image: path);
    backend.server.photoUploadFails = true;

    final res = await uploader.run();
    expect(res.stoppedBy, isNull);
    expect(server('recipes').keys, ['a']);
    expect(server('recipes')['a']!['image_path'], 'p0.jpg');
    final photo = (await outbox()).single;
    expect(photo.op, OutboxOp.photoUpload);
    expect(photo.attempts, 1);
    expect(photo.nextAttemptAt, isNotNull);

    // Sledeće slanje, posle pauze.
    backend.server.photoUploadFails = false;
    await uploader.run();
    expect(await outbox(), hasLength(1));
    now = now.add(const Duration(seconds: 6));
    await uploader.run();
    expect(await outbox(), isEmpty);
    expect(backend.server.photos.keys, ['${scope.householdId}/p0.jpg']);
  });

  test('odbijena stavka odlaže brisanje stare slike', () async {
    backend.server.photos['${scope.householdId}/old.jpg'] = Uint8List(1);
    await db
        .into(db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            accountId: scope.userId,
            entity: 'shopping_item',
            recordId: 'i',
            op: OutboxOp.upsert,
            state: const Value(OutboxState.rejected),
            createdAt: now,
          ),
        );
    await writer.photoDelete('recipe_photos/old.jpg');
    await uploader.run();
    expect(
      backend.server.photos.keys,
      contains('${scope.householdId}/old.jpg'),
    );
    expect((await outbox()).any((e) => e.op == OutboxOp.photoDelete), isTrue);
  });

  test('brisanje slike briše objekat', () async {
    backend.server.photos['${scope.householdId}/x.jpg'] = Uint8List(1);
    await writer.photoDelete('recipe_photos/x.jpg');
    await uploader.run();
    expect(backend.server.photos, isEmpty);
  });

  test('prekinuto slanje pa ponovo: bez duplikata i bez gubitka', () async {
    for (var i = 0; i < 10; i++) {
      await addRecipe('r$i');
    }
    backend.server.interruptAfterRows = 4;
    expect((await uploader.run()).offline, isTrue);
    expect(server('recipes'), hasLength(4));
    await uploader.run();
    expect(
      server('recipes').keys,
      unorderedEquals([for (var i = 0; i < 10; i++) 'r$i']),
    );
    expect(await outbox(), isEmpty);
  });

  test('izmena tokom slanja dobija nov red i šalje se posle', () async {
    await addRecipe('a');
    // Upravo se šalje…
    await db
        .update(db.syncOutbox)
        .write(const SyncOutboxCompanion(state: Value(OutboxState.sending)));
    // …a korisnik ponovo menja isti recept.
    await writer.upsert('recipe', 'a');
    final rows = await outbox();
    expect(rows, hasLength(2));
    expect(rows.last.state, OutboxState.pending);
  });

  test('ime u profilu se šalje kao izmena imena', () async {
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            userId: scope.userId,
            email: 'ana@mail.com',
            displayName: const Value('Ana'),
            householdId: scope.householdId,
            householdName: 'Moje domaćinstvo',
            role: 'owner',
            createdAt: now,
          ),
        );
    await writer.upsert('profile', scope.userId);
    await uploader.run();
    expect(backend.server.profiles[scope.userId]!['display_name'], 'Ana');
  });
}
