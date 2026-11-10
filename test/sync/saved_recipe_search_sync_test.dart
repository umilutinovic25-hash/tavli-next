import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/recipe_repository.dart';
import 'package:tavli/domain/saved_recipe_search.dart';
import 'package:tavli/sync/downloader.dart';
import 'package:tavli/sync/synced_writer.dart';
import 'package:tavli/sync/uploader.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_photo_store.dart';

void main() {
  test(
    'offline upis se šalje, preuzima na drugom uređaju i brisanje prati',
    () async {
      final backend = FakeBackend();
      final session = await backend.auth.verifyCode(
        'ana@test.local',
        FakeServer.code,
      );
      final scope = AccountScope(
        userId: session.userId,
        householdId: backend.server.households[session.userId]!,
      );
      final first = AppDatabase(NativeDatabase.memory());
      final second = AppDatabase(NativeDatabase.memory());
      addTearDown(first.close);
      addTearDown(second.close);
      final photos = FakePhotoStore();
      RecipeRepository repo(AppDatabase db) => RecipeRepository(
        db,
        photos,
        writer: SyncedWriter(db, accountId: scope.userId),
        scope: scope,
      );
      final upload = Uploader(
        db: first,
        remote: backend.sync,
        photos: backend.photos,
        photoStore: photos,
        scope: scope,
        refreshSession: () async => true,
      );
      final download = Downloader(
        db: second,
        remote: backend.sync,
        scope: scope,
      );
      backend.server.offline = true;
      await repo(first).saveSearch(
        'Brzo',
        const RecipeSearchFilter(
          maxMinutes: 30,
          includeIngredient: 'piletina',
          excludeIngredient: 'orah',
        ),
      );
      await upload.run();
      expect(await first.select(first.syncOutbox).get(), hasLength(1));
      backend.server.offline = false;
      await upload.run();
      await download.run();
      final saved = (await repo(second).watchSavedSearches().first).single;
      expect(saved.filter.maxMinutes, 30);
      expect(saved.filter.excludeIngredient, 'orah');
      await repo(first).deleteSearch(saved.id);
      await upload.run();
      await download.run();
      expect(await repo(second).watchSavedSearches().first, isEmpty);
    },
  );
}
