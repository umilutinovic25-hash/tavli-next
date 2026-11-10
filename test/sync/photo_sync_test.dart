import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/sync/photo_sync.dart';
import 'package:tavli/sync/sync_remote.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_photo_store.dart';

/// Broji koliko preuzimanja traje u isto vreme.
class CountingPhotos implements PhotoRemote {
  CountingPhotos(this.inner);

  final PhotoRemote inner;
  int active = 0;
  int maxActive = 0;

  @override
  Future<Uint8List> download(String objectKey) async {
    active++;
    maxActive = active > maxActive ? active : maxActive;
    await Future<void>.delayed(Duration.zero);
    try {
      return await inner.download(objectKey);
    } finally {
      active--;
    }
  }

  @override
  Future<void> upload(String objectKey, Uint8List jpeg) =>
      inner.upload(objectKey, jpeg);

  @override
  Future<void> remove(List<String> objectKeys) => inner.remove(objectKeys);
}

void main() {
  late AppDatabase db;
  late FakeBackend backend;
  late FakePhotoStore store;
  const scope = AccountScope(userId: 'u1', householdId: 'h1');

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    backend = FakeBackend();
    store = FakePhotoStore();
  });
  tearDown(() => db.close());

  Future<void> recipe(String id, String? image, {String home = 'h1'}) => db
      .into(db.recipes)
      .insert(
        RecipesCompanion.insert(
          id: id,
          title: id,
          servings: 1,
          source: 'manual',
          ingredientsJson: '[]',
          stepsJson: '[]',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          imagePath: Value(image),
          householdId: Value(home),
        ),
      );

  test(
    'preuzima samo slike stavki svog domaćinstva i osvežava prikaz',
    () async {
      for (final (id, home) in [('a', 'h1'), ('b', 'h2')]) {
        await db
            .into(db.shoppingLists)
            .insert(
              ShoppingListsCompanion.insert(
                id: 'l$id',
                name: 'Lista',
                createdAt: DateTime.utc(2026),
                householdId: Value(home),
              ),
            );
        await db
            .into(db.shoppingItems)
            .insert(
              ShoppingItemsCompanion.insert(
                id: id,
                listId: 'l$id',
                name: id,
                category: 'ostalo',
                householdId: Value(home),
                photoPath: Value('recipe_photos/$id.jpg'),
              ),
            );
        backend.server.photos['$home/$id.jpg'] = Uint8List.fromList([1]);
      }
      final notified = <String>[];
      expect(
        await PhotoSync(
          db: db,
          remote: backend.photos,
          store: store,
          scope: scope,
          onFetched: notified.add,
        ).fetchMissing(),
        1,
      );
      expect(store.saved.keys, ['recipe_photos/a.jpg']);
      expect(notified, ['recipe_photos/a.jpg']);
    },
  );

  test(
    'preuzima slike recepata i verzija kojih nema, najviše 4 odjednom',
    () async {
      for (var i = 0; i < 9; i++) {
        await recipe('r$i', 'recipe_photos/r$i.jpg');
        backend.server.photos['h1/r$i.jpg'] = Uint8List.fromList([i]);
      }
      await db
          .into(db.recipeVersions)
          .insert(
            RecipeVersionsCompanion.insert(
              id: 'v1',
              recipeId: 'r0',
              recipeJson: '{"imagePath":"recipe_photos/stara.jpg"}',
              createdAt: DateTime.utc(2026),
              householdId: const Value('h1'),
            ),
          );
      backend.server.photos['h1/stara.jpg'] = Uint8List.fromList([42]);
      store.saved['recipe_photos/r0.jpg'] = Uint8List.fromList([0]);
      await recipe('tudji', 'recipe_photos/x.jpg', home: 'h2');

      final photos = CountingPhotos(backend.photos);
      final n = await PhotoSync(
        db: db,
        remote: photos,
        store: store,
        scope: scope,
      ).fetchMissing();

      expect(n, 9); // 8 recepata (r0 već postoji) + verzija
      expect(store.saved['recipe_photos/stara.jpg'], [42]);
      expect(store.saved.containsKey('recipe_photos/x.jpg'), isFalse);
      expect(photos.maxActive, lessThanOrEqualTo(4));
    },
  );

  test('neuspela slika ostaje za sledeći put', () async {
    await recipe('a', 'recipe_photos/a.jpg');
    await recipe('b', 'recipe_photos/b.jpg');
    backend.server.photos['h1/a.jpg'] = Uint8List.fromList([1]);
    backend.server.photos['h1/b.jpg'] = Uint8List.fromList([2]);
    backend.photos.missing.add('h1/b.jpg');
    final sync = PhotoSync(
      db: db,
      remote: backend.photos,
      store: store,
      scope: scope,
    );
    expect(await sync.fetchMissing(), 1);
    expect(store.saved.keys, ['recipe_photos/a.jpg']);

    backend.photos.missing.clear();
    expect(await sync.fetchMissing(), 1);
    expect(store.saved, hasLength(2));
  });
}
