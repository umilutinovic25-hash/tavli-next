import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/recipe_repository.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/recipe_version.dart';
import 'package:tavli/domain/step_links.dart';
import 'package:tavli/sync/synced_writer.dart';

import '../helpers/fake_photo_store.dart';

Recipe recipe(String id, {String title = 'Sarma', DateTime? createdAt}) =>
    Recipe(
      id: id,
      title: title,
      servings: 4,
      ingredients: const [Ingredient(name: 'kupus')],
      steps: const ['Kuvati.'],
      source: RecipeSource.manual,
      createdAt: createdAt ?? DateTime.utc(2026),
    );

void main() {
  late AppDatabase db;
  late FakePhotoStore photos;
  late RecipeRepository repo;
  var now = DateTime.utc(2026, 10, 30, 12);
  const scope = AccountScope(userId: 'u1', householdId: 'h1');

  RecipeRepository repoFor(AccountScope s) => RecipeRepository(
    db,
    photos,
    writer: SyncedWriter(db, accountId: s.userId, clock: () => now),
    scope: s,
    clock: () => now,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    photos = FakePhotoStore();
    now = DateTime.utc(2026, 10, 30, 12);
    repo = repoFor(scope);
  });
  tearDown(() => db.close());

  /// Izmene koje čekaju slanje, redom: "entitet:op".
  Future<List<String>> outbox({bool withIds = false}) async => [
    for (final e in await (db.select(
      db.syncOutbox,
    )..orderBy([(t) => OrderingTerm.asc(t.seq)])).get())
      withIds ? '${e.entity}:${e.recordId}:${e.op}' : '${e.entity}:${e.op}',
  ];

  Future<void> clearOutbox() => db.delete(db.syncOutbox).go();

  test('izvor URL-a ostaje posle izmene i vraćanja verzije', () async {
    final imported = Recipe(
      id: 'url',
      title: 'Pita',
      servings: 4,
      ingredients: const [Ingredient(name: 'brašno')],
      source: RecipeSource.url,
      sourceUrl: 'https://example.com/pita',
      createdAt: now,
    );
    await repo.create(imported);
    expect((await repo.get('url'))?.sourceUrl, imported.sourceUrl);
    await repo.update(
      imported.copyWith(title: 'Izmenjena pita'),
      kind: ChangeKind.manual,
    );
    expect((await repo.get('url'))?.sourceUrl, imported.sourceUrl);
    expect(
      (await repo.watchVersions('url').first).single.recipe.sourceUrl,
      imported.sourceUrl,
    );
    await repo.undoLast('url');
    expect((await repo.get('url'))?.sourceUrl, imported.sourceUrl);
  });

  test('veze koraka se čuvaju u receptu i u prethodnoj verziji', () async {
    final linked = recipe('r1').copyWith(
      ingredients: const [Ingredient(id: 'i-k', name: 'kupus')],
      stepUses: const [
        [StepUse(ingredientId: 'i-k', quantity: 1, unit: 'glavica')],
      ],
    );
    await repo.create(linked);
    expect((await repo.get('r1'))!.stepUses, linked.stepUses);
    expect((await repo.get('r1'))!.ingredients.single.id, 'i-k');

    await repo.update(
      linked.copyWith(steps: const ['Kuvati.', 'Poslužiti.']),
      kind: ChangeKind.manual,
    );
    final now = (await repo.get('r1'))!;
    expect(now.usesFor(0).single.unit, 'glavica');
    expect(now.usesFor(1), isEmpty);
    final version = (await repo.watchVersions('r1').first).single;
    expect(version.recipe.stepUses, linked.stepUses);
  });

  test('recept bez veza ne upisuje zapis veza', () async {
    await repo.create(recipe('r1'));
    expect((await db.select(db.recipes).get()).single.stepLinksJson, isNull);
  });

  test('lista je od najnovijeg ka najstarijem', () async {
    await repo.create(recipe('a', title: 'Pasulj', createdAt: DateTime(2026)));
    await repo.create(recipe('b', createdAt: DateTime(2026, 5)));

    final list = await repo.watchAll().first;
    expect(list.map((r) => r.title), ['Sarma', 'Pasulj']);
    expect((await repo.get('a'))!.ingredients.single.name, 'kupus');
    expect(await repo.get('nema'), isNull);
  });

  test('izmena čuva prethodnu verziju sa vrstom, zahtevom i modelom', () async {
    await repo.create(recipe('a'));
    await repo.update(
      recipe('a', title: 'Posna sarma'),
      kind: ChangeKind.ai,
      instruction: 'posno',
      changedBy: 'Gemini Pro',
    );

    expect((await repo.get('a'))!.title, 'Posna sarma');
    final v = (await repo.watchVersions('a').first).single;
    expect(v.recipe.title, 'Sarma');
    expect(v.kind, ChangeKind.ai);
    expect(v.instruction, 'posno');
    expect(v.changedBy, 'Gemini Pro');
    expect(v.createdAt.isAtSameMomentAs(now), isTrue);
  });

  test('čuva se najviše 30 verzija', () async {
    await repo.create(recipe('a', title: 'v0'));
    for (var i = 1; i <= 35; i++) {
      now = now.add(const Duration(minutes: 1));
      await repo.update(recipe('a', title: 'v$i'), kind: ChangeKind.manual);
    }
    final versions = await repo.watchVersions('a').first;
    expect(versions, hasLength(30));
    expect(versions.first.recipe.title, 'v34');
    expect(versions.last.recipe.title, 'v5');
  });

  test('poništavanje vraća prethodno stanje i briše tu verziju', () async {
    await repo.create(recipe('a'));
    await repo.update(recipe('a', title: 'Druga'), kind: ChangeKind.ai);

    expect(await repo.undoLast('a'), isTrue);
    expect((await repo.get('a'))!.title, 'Sarma');
    expect(await repo.watchVersions('a').first, isEmpty);
    expect(await repo.undoLast('a'), isFalse);
  });

  test('vraćanje starije verzije čuva trenutno stanje', () async {
    await repo.create(recipe('a', title: 'Prva'));
    await repo.update(recipe('a', title: 'Druga'), kind: ChangeKind.ai);
    now = now.add(const Duration(minutes: 1));
    await repo.update(recipe('a', title: 'Treća'), kind: ChangeKind.ai);

    final oldest = (await repo.watchVersions('a').first).last;
    now = now.add(const Duration(minutes: 1));
    await repo.restore(oldest.id);

    expect((await repo.get('a'))!.title, 'Prva');
    final versions = await repo.watchVersions('a').first;
    expect(versions.first.kind, ChangeKind.restore);
    expect(versions.first.recipe.title, 'Treća');

    await repo.undoLast('a');
    expect((await repo.get('a'))!.title, 'Treća');
  });

  test('brisanje uklanja recept, verzije i sliku', () async {
    final path = await photos.save(Uint8List.fromList([1]));
    await repo.create(recipe('a').copyWith(imagePath: path));
    await repo.update(recipe('a', title: 'B'), kind: ChangeKind.manual);
    await db
        .into(db.ratings)
        .insert(
          RatingsCompanion.insert(
            id: 'g1',
            recipeId: 'a',
            stars: 5,
            cookedAt: now,
            userId: const Value('u1'),
          ),
        );

    await repo.delete('a');

    expect(await repo.get('a'), isNull);
    expect(await db.select(db.recipeVersions).get(), isEmpty);
    expect(await db.select(db.ratings).get(), isEmpty);
    expect(photos.saved, isEmpty);
  });

  test('izmena nepostojećeg recepta baca grešku', () async {
    expect(
      () => repo.update(recipe('x'), kind: ChangeKind.manual),
      throwsStateError,
    );
  });

  test('pokvaren zapis verzije se preskače', () async {
    await repo.create(recipe('a'));
    await db
        .into(db.recipeVersions)
        .insert(
          RecipeVersionsCompanion.insert(
            id: 'v-bad',
            householdId: const Value('h1'),
            recipeId: 'a',
            recipeJson: '{"title": ""}',
            createdAt: now,
            changeKind: const Value('ai'),
          ),
        );
    expect(await repo.watchVersions('a').first, isEmpty);
  });

  group('nalog i red za slanje', () {
    test('čita samo recepte aktivnog domaćinstva', () async {
      await repo.create(recipe('a', title: 'Moja'));
      await repoFor(const AccountScope(userId: 'u2', householdId: 'h2'))
          .create(recipe('b', title: 'Tuđa'));
      await db
          .into(db.recipes)
          .insert(
            RecipesCompanion.insert(
              id: 'stari',
              title: 'Od pre naloga',
              servings: 1,
              source: 'manual',
              ingredientsJson: '[]',
              stepsJson: '[]',
              createdAt: now,
              updatedAt: now,
            ),
          );

      expect((await repo.watchAll().first).map((r) => r.title), ['Moja']);
      expect(await repo.get('b'), isNull);
      expect(await repo.get('stari'), isNull);
      final row = await (db.select(
        db.recipes,
      )..where((t) => t.id.equals('a'))).getSingle();
      expect(row.householdId, 'h1');
    });

    test('novi recept sa slikom: upsert i slanje slike', () async {
      await repo.create(recipe('a').copyWith(imagePath: 'recipe_photos/x.jpg'));
      expect(await outbox(withIds: true), [
        'recipe:a:upsert',
        'photo:recipe_photos/x.jpg:photoUpload',
      ]);
      final e = (await db.select(db.syncOutbox).get()).first;
      expect(e.accountId, 'u1');
    });

    test('izmena šalje verziju i recept; nova slika se šalje', () async {
      await repo.create(recipe('a'));
      await clearOutbox();
      await repo.update(
        recipe('a', title: 'B').copyWith(imagePath: 'recipe_photos/n.jpg'),
        kind: ChangeKind.manual,
      );
      expect(await outbox(), [
        'recipe_version:upsert',
        'recipe:upsert',
        'photo:photoUpload',
      ]);
      final v = (await db.select(db.recipeVersions).get()).single;
      expect(v.householdId, 'h1');
      expect((await db.select(db.syncOutbox).get()).first.recordId, v.id);
    });

    test('preko 30 verzija: najstarije se brišu i na serveru', () async {
      await repo.create(recipe('a', title: 'v0'));
      for (var i = 1; i <= 31; i++) {
        now = now.add(const Duration(minutes: 1));
        await repo.update(recipe('a', title: 'v$i'), kind: ChangeKind.manual);
      }
      final ops = await outbox();
      expect(ops.where((o) => o == 'recipe_version:delete'), hasLength(1));
      // Obrisana verzija nije ni poslata: njen upsert je uklonjen iz reda.
      expect(ops.where((o) => o == 'recipe_version:upsert'), hasLength(30));
    });

    test('poništavanje i vraćanje verzije', () async {
      await repo.create(recipe('a'));
      await repo.update(recipe('a', title: 'B'), kind: ChangeKind.ai);
      await clearOutbox();
      await repo.undoLast('a');
      expect(await outbox(), ['recipe:upsert', 'recipe_version:delete']);

      await repo.update(recipe('a', title: 'C'), kind: ChangeKind.ai);
      final v = (await repo.watchVersions('a').first).single;
      await clearOutbox();
      now = now.add(const Duration(minutes: 1));
      await repo.restore(v.id);
      expect(await outbox(), ['recipe_version:upsert', 'recipe:upsert']);
    });

    test('brisanje: verzije, ocene, stavke plana, recept i slika', () async {
      await repo.create(recipe('a').copyWith(imagePath: 'recipe_photos/x.jpg'));
      await repo.update(recipe('a', title: 'B'), kind: ChangeKind.manual);
      await db
          .into(db.ratings)
          .insert(
            RatingsCompanion.insert(
              id: 'g1',
              recipeId: 'a',
              stars: 5,
              cookedAt: now,
              userId: const Value('u1'),
            ),
          );
      await db
          .into(db.mealPlanEntries)
          .insert(
            MealPlanEntriesCompanion.insert(
              id: 'e1',
              planId: 'p1',
              date: now,
              mealType: 'lunch',
              recipeId: const Value('a'),
              householdId: const Value('h1'),
            ),
          );
      await clearOutbox();

      await repo.delete('a');

      expect(await outbox(withIds: true), [
        startsWith('recipe_version:'),
        'rating:g1:delete',
        'meal_plan_entry:e1:upsert',
        'recipe:a:delete',
        'photo:recipe_photos/x.jpg:photoDelete',
      ]);
      final entry = (await db.select(db.mealPlanEntries).get()).single;
      expect(entry.recipeId, isNull);
    });

    test('slika koju koristi drugi recept se ne briše', () async {
      await repo.create(recipe('a').copyWith(imagePath: 'recipe_photos/x.jpg'));
      await repo.create(recipe('b').copyWith(imagePath: 'recipe_photos/x.jpg'));
      await clearOutbox();
      await repo.delete('a');
      expect(await outbox(), ['recipe:delete']);
    });
  });
}
