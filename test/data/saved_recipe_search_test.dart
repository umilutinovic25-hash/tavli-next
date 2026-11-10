import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/recipe_repository.dart';
import 'package:tavli/domain/saved_recipe_search.dart';
import 'package:tavli/sync/synced_writer.dart';

import '../helpers/fake_photo_store.dart';

void main() {
  test(
    'pretraga i outbox opstaju po ponovnom otvaranju i izolovani su po nalogu',
    () async {
      final dir = await Directory.systemTemp.createTemp('saved-search-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/data.sqlite');
      RecipeRepository repository(AppDatabase db, String user) =>
          RecipeRepository(
            db,
            FakePhotoStore(),
            writer: SyncedWriter(db, accountId: user),
            scope: AccountScope(userId: user, householdId: 'h'),
          );
      var db = AppDatabase(NativeDatabase(file));
      await repository(db, 'a').saveSearch(
        'Brzo',
        const RecipeSearchFilter(
          query: 'jelo',
          maxMinutes: 30,
          includeIngredient: 'piletina',
          excludeIngredient: 'orah',
        ),
      );
      final id = (await repository(
        db,
        'a',
      ).watchSavedSearches().first).single.id;
      expect((await db.select(db.syncOutbox).get()).single.op, 'upsert');
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      final a = repository(db, 'a');
      final b = repository(db, 'b');
      final saved = (await a.watchSavedSearches().first).single;
      expect(saved.name, 'Brzo');
      expect(saved.filter.query, 'jelo');
      expect(saved.filter.maxMinutes, 30);
      expect(saved.filter.includeIngredient, 'piletina');
      expect(saved.filter.excludeIngredient, 'orah');
      expect(await b.watchSavedSearches().first, isEmpty);
      await b.deleteSearch(id);
      expect(await a.watchSavedSearches().first, hasLength(1));
      await a.deleteSearch(id);
      expect(await a.watchSavedSearches().first, isEmpty);
      final changes = await db.select(db.syncOutbox).get();
      expect(changes.single.op, 'delete');
      await db.close();
    },
  );
}
