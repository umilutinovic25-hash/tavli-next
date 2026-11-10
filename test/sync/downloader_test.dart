import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/sync/downloader.dart';
import 'package:tavli/sync/sync_remote.dart';
import 'package:tavli/sync/synced_writer.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_photo_store.dart';

void main() {
  late AppDatabase db;
  late FakeBackend backend;
  late AccountScope scope;
  late String hid;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    backend = FakeBackend();
    final s = await backend.auth.verifyCode('ana@mail.com', FakeServer.code);
    hid = backend.server.households[s.userId]!;
    scope = AccountScope(userId: s.userId, householdId: hid);
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            userId: s.userId,
            email: 'ana@mail.com',
            householdId: hid,
            householdName: 'Moje domaćinstvo',
            role: 'owner',
            createdAt: DateTime.utc(2026),
          ),
        );
  });
  tearDown(() => db.close());

  Downloader downloader({int pageSize = 500, Duration? overlap}) => Downloader(
    db: db,
    remote: backend.sync,
    scope: scope,
    pageSize: pageSize,
    overlap: overlap ?? const Duration(seconds: 60),
  );

  void serverRecipe(String id, {String title = 'Sarma'}) =>
      backend.server.upsert('recipes', [
        {
          'id': id,
          'household_id': hid,
          'title': title,
          'servings': 4,
          'prep_minutes': null,
          'source': 'manual',
          'ingredients': <Object>[],
          'steps': ['Kuvati.'],
          'image_path': 'slika-$id.jpg',
          'answered_by': null,
          'created_at': '2026-10-30T10:00:00.000Z',
        },
      ], 'id');

  void seedAll() {
    serverRecipe('r1');
    final s = backend.server;
    s.upsert('recipe_versions', [
      {
        'id': 'v1',
        'household_id': hid,
        'recipe_id': 'r1',
        'recipe_json': {'title': 'Stara sarma'},
        'instruction': null,
        'change_kind': 'manual',
        'changed_by': null,
        'created_at': '2026-10-30T10:00:00.000Z',
      },
    ], 'id');
    s.upsert('meal_plans', [
      {
        'id': 'p1',
        'household_id': hid,
        'start_date': '2026-11-02T00:00:00.000Z',
        'end_date': '2026-11-08T00:00:00.000Z',
        'meal_types': ['lunch'],
        'use_pantry': true,
        'created_at': '2026-10-30T10:00:00.000Z',
      },
    ], 'id');
    s.upsert('shopping_lists', [
      {
        'id': 'l1',
        'household_id': hid,
        'name': 'Lista',
        'meal_plan_id': 'p1',
        'week': 1,
        'created_at': '2026-10-30T10:00:00.000Z',
      },
    ], 'id');
    s.upsert('shopping_items', [
      for (final n in ['mleko', 'hleb'])
        {
          'id': 'i-$n',
          'household_id': hid,
          'list_id': 'l1',
          'name': n,
          'quantity': null,
          'unit': null,
          'category': 'ostalo',
          'is_bought': false,
          'is_manual': true,
          'from_recipe_ids': <Object>[],
        },
    ], 'id');
    s.upsert('pantry_items', [
      {
        'id': 'o1',
        'household_id': hid,
        'name': 'so',
        'quantity': 1,
        'unit': 'kg',
        'category': 'ostalo',
        'added_at': '2026-10-30T10:00:00.000Z',
        'expires_at': null,
      },
    ], 'id');
    s.upsert('meal_plan_entries', [
      {
        'id': 'e1',
        'household_id': hid,
        'plan_id': 'p1',
        'date': '2026-11-02T00:00:00.000Z',
        'meal_type': 'lunch',
        'recipe_id': 'r1',
        'is_locked': false,
        'is_cooked': false,
      },
    ], 'id');
    s.upsert('shopping_sources', [
      {
        'id': 's1',
        'household_id': hid,
        'list_id': 'l1',
        'kind': 'planEntry',
        'plan_entry_id': 'e1',
        'recipe_snapshot': null,
        'servings': null,
        'recipe_id': null,
        'origin_key': null,
        'superseded_at': null,
        'closed_at': null,
        'created_at': '2026-10-30T10:00:00.000Z',
      },
    ], 'id');
    s.upsert('shopping_contributions', [
      {
        'id': 'c1',
        'household_id': hid,
        'shopping_item_id': 'i-mleko',
        'source_id': 's1',
        'ingredient_key': 'mleko',
        'unit_group': 'volume',
        'base_unit': 'ml',
        'micros': 500000000,
        'name': 'mleko',
        'category': 'ostalo',
        'notes': <Object>[],
      },
    ], 'id');
    s.upsert('supply_allocations', [
      {
        'id': 'a1',
        'household_id': hid,
        'contribution_id': 'c1',
        'pantry_item_id': 'o1',
        'purchased_shopping_item_id': null,
        'supply_id': 'o1',
        'micros': 200000000,
        'covers_whole_unknown': false,
        'created_at': '2026-10-30T10:00:00.000Z',
      },
    ], 'id');
    s.upsert('ratings', [
      {
        'id': 'g1',
        'user_id': scope.userId,
        'recipe_id': 'r1',
        'stars': 5,
        'is_comfort_food': true,
        'comment': null,
        'cooked_at': '2026-10-31T10:00:00.000Z',
      },
    ], 'id');
    s.upsert('taste_profiles', [
      {
        'user_id': scope.userId,
        'profile': {'ljuto': true},
      },
    ], 'user_id');
    s.profiles[scope.userId]!['display_name'] = 'Ana Petrović';
  }

  test('prvo preuzimanje: svi entiteti, roditelj pre deteta', () async {
    seedAll();
    backend.server.calls.clear();
    await downloader().run();

    expect(backend.server.calls, [
      'fetch:profiles',
      'fetch:recipes',
      'fetch:recipe_versions',
      'fetch:day_time_budgets',
      'fetch:household_preferences',
      'fetch:meal_plans',
      'fetch:week_templates',
      'fetch:meal_plan_entries',
      'fetch:cook_soon_items',
      'fetch:day_rules',
      'fetch:shopping_lists',
      'fetch:shopping_items',
      'fetch:pantry_items',
      'fetch:shopping_sources',
      'fetch:shopping_contributions',
      'fetch:supply_allocations',
      'fetch:ratings',
      'fetch:taste_profiles',
      'fetch:saved_recipe_searches',
      'fetch:deletions',
    ]);
    final recipe = (await db.select(db.recipes).get()).single;
    expect(recipe.householdId, hid);
    expect(recipe.imagePath, 'recipe_photos/slika-r1.jpg');
    expect((await db.select(db.recipeVersions).get()).single.householdId, hid);
    expect(await db.select(db.shoppingItems).get(), hasLength(2));
    expect((await db.select(db.shoppingLists).get()).single.mealPlanId, 'p1');
    expect((await db.select(db.pantryItems).get()).single.quantity, 1.0);
    expect((await db.select(db.mealPlanEntries).get()).single.recipeId, 'r1');
    expect(
      (await db.select(db.shoppingSources).get()).single.planEntryId,
      'e1',
    );
    final contribution =
        (await db.select(db.shoppingContributions).get()).single;
    expect(contribution.micros, 500000000);
    expect(contribution.householdId, hid);
    final allocation = (await db.select(db.supplyAllocations).get()).single;
    expect(allocation.supplyId, 'o1');
    expect(allocation.micros, 200000000);
    expect((await db.select(db.ratings).get()).single.userId, scope.userId);
    expect((await db.select(db.userProfiles).get()).single.id, scope.userId);
    expect(
      (await db.select(db.accounts).get()).single.displayName,
      'Ana Petrović',
    );
    expect(await db.select(db.syncOutbox).get(), isEmpty);
  });

  test('strane od 500 sa sačuvanom pozicijom posle svake', () async {
    for (var i = 0; i < 1200; i++) {
      serverRecipe('r${i.toString().padLeft(4, '0')}');
    }
    backend.server.calls.clear();
    await downloader().run();
    expect(
      backend.server.calls.where((c) => c == 'fetch:recipes'),
      hasLength(3),
    );
    expect(await db.select(db.recipes).get(), hasLength(1200));
    final cursor = await (db.select(
      db.syncCursors,
    )..where((t) => t.entity.equals('recipe'))).getSingle();
    expect(cursor.lastId, 'r1199');
  });

  test('prekinuto preuzimanje se nastavlja, bez duplikata', () async {
    for (var i = 0; i < 7; i++) {
      serverRecipe('r$i');
    }
    // profil + prva strana recepata uspeju, druga strana pukne
    backend.server.fetchesBeforeFailure = 2;
    await expectLater(
      downloader(pageSize: 3).run(),
      throwsA(isA<TransientSyncError>()),
    );
    expect(await db.select(db.recipes).get(), hasLength(3));

    await downloader(pageSize: 3).run();
    final ids = [for (final r in await db.select(db.recipes).get()) r.id];
    expect(ids, unorderedEquals([for (var i = 0; i < 7; i++) 'r$i']));
  });

  test('preklapanje od 60 s ponovo upisuje iste redove bez štete', () async {
    seedAll();
    await downloader().run();
    await downloader().run();
    expect(await db.select(db.recipes).get(), hasLength(1));
    expect(await db.select(db.shoppingItems).get(), hasLength(2));
  });

  test('drugi put se preuzimaju samo novije izmene', () async {
    serverRecipe('a');
    serverRecipe('b');
    await downloader(overlap: Duration.zero).run();
    serverRecipe('c');
    serverRecipe('a', title: 'Nova');
    backend.server.calls.clear();
    final before = backend.server.table('recipes').length;
    expect(before, 3);
    await downloader(overlap: Duration.zero).run();
    final rows = await db.select(db.recipes).get();
    expect(rows, hasLength(3));
    expect(rows.firstWhere((r) => r.id == 'a').title, 'Nova');
  });

  test('lokalna izmena koja čeka ili je odbijena se ne prepisuje', () async {
    serverRecipe('a', title: 'Sa servera');
    serverRecipe('b', title: 'Sa servera');
    for (final (id, state) in [
      ('a', OutboxState.pending),
      ('b', OutboxState.rejected),
    ]) {
      await db
          .into(db.recipes)
          .insert(
            RecipesCompanion.insert(
              id: id,
              title: 'Lokalno',
              servings: 1,
              source: 'manual',
              ingredientsJson: '[]',
              stepsJson: '[]',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
              householdId: Value(hid),
            ),
          );
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              accountId: scope.userId,
              entity: 'recipe',
              recordId: id,
              op: OutboxOp.upsert,
              state: Value(state),
              createdAt: DateTime.utc(2026),
            ),
          );
    }
    await downloader().run();
    final rows = await db.select(db.recipes).get();
    expect(rows.map((r) => r.title), ['Lokalno', 'Lokalno']);
  });

  test('udaljena zamena i brisanje čiste lokalnu fotografiju stavke', () async {
    seedAll();
    backend.server.upsert('shopping_items', [
      {'id': 'i-mleko', 'household_id': hid, 'photo_path': 'old.jpg'},
    ], 'id');
    final photos = FakePhotoStore();
    final pull = Downloader(
      db: db,
      remote: backend.sync,
      scope: scope,
      photoStore: photos,
    );
    await pull.run();
    await photos.write('recipe_photos/old.jpg', Uint8List(1));
    backend.server.upsert('shopping_items', [
      {'id': 'i-mleko', 'household_id': hid, 'photo_path': 'new.jpg'},
    ], 'id');
    await pull.run();
    expect(await photos.exists('recipe_photos/old.jpg'), isFalse);
    expect(
      (await (db.select(
        db.shoppingItems,
      )..where((t) => t.id.equals('i-mleko'))).getSingle()).photoPath,
      'recipe_photos/new.jpg',
    );
    await photos.write('recipe_photos/new.jpg', Uint8List(1));
    await SyncedWriter(
      db,
      accountId: scope.userId,
    ).photoUpload('recipe_photos/new.jpg');
    backend.server.delete('shopping_items', ['i-mleko'], 'id');
    await pull.run();
    expect(await photos.exists('recipe_photos/new.jpg'), isFalse);
    final outbox = await db.select(db.syncOutbox).get();
    expect(
      outbox.any(
        (e) =>
            e.recordId == 'recipe_photos/new.jpg' &&
            e.op == OutboxOp.photoDelete,
      ),
      isTrue,
    );
    expect(
      outbox.any(
        (e) =>
            e.recordId == 'recipe_photos/new.jpg' &&
            e.op == OutboxOp.photoUpload,
      ),
      isFalse,
    );
  });

  test('trag brisanja briše lokalni red i izmene koje čekaju', () async {
    seedAll();
    await downloader().run();
    await SyncedWriter(db, accountId: scope.userId).upsert('pantry_item', 'o1');
    backend.server.delete('pantry_items', ['o1'], 'id');
    backend.server.delete('recipes', ['r1'], 'id');

    await downloader().run();
    expect(await db.select(db.pantryItems).get(), isEmpty);
    expect(await db.select(db.recipes).get(), isEmpty);
    expect(await db.select(db.recipeVersions).get(), isEmpty);
    expect(await db.select(db.ratings).get(), isEmpty);
    // Stavka plana ostaje, bez recepta.
    expect((await db.select(db.mealPlanEntries).get()).single.recipeId, isNull);
    expect(await db.select(db.syncOutbox).get(), isEmpty);
  });

  test('ne preuzima tuđe podatke', () async {
    final other = await backend.auth.verifyCode('b@mail.com', FakeServer.code);
    backend.server.upsert('pantry_items', [
      {
        'id': 'tudje',
        'household_id': backend.server.households[other.userId],
        'name': 'x',
        'category': 'ostalo',
        'added_at': '2026-10-30T10:00:00.000Z',
      },
    ], 'id');
    await backend.auth.verifyCode('ana@mail.com', FakeServer.code);
    await downloader().run();
    expect(await db.select(db.pantryItems).get(), isEmpty);
  });
}
