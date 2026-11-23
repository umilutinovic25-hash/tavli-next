import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/recipe_repository.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/recipe_labels.dart';
import 'package:tavli/domain/recipe_version.dart';
import 'package:tavli/sync/entities.dart';
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

  test('lista je od najnovijeg ka najstarijem', () async {
    await repo.create(recipe('a', title: 'Pasulj', createdAt: DateTime(2026)));
    await repo.create(recipe('b', createdAt: DateTime(2026, 5)));

    final list = await repo.watchAll().first;
    expect(list.map((r) => r.title), ['Sarma', 'Pasulj']);
    expect((await repo.get('a'))!.ingredients.single.name, 'kupus');
    expect(await repo.get('nema'), isNull);
  });

  test('undo kopiranog recepta koristi originalni redosled verzija', () async {
    const copiedId = 'join-recipe';
    await repo.create(recipe(copiedId, title: 'Trenutni recept'));
    // The download can insert the latest snapshot before the earliest snapshot.
    final versions = entityByName('recipe_version')!;
    for (final (id, title, createdAt) in [
      ('join-latest', 'Pre poslednje izmene', '2026-11-20T12:00:02Z'),
      ('join-earliest', 'Početni recept', '2026-11-20T12:00:01Z'),
    ]) {
      await versions.write(db, {
        'id': id,
        'household_id': scope.householdId,
        'recipe_id': copiedId,
        'recipe_json': recipe(copiedId, title: title).toJson(),
        'change_kind': 'ai',
        'created_at': createdAt,
      });
    }

    expect(await repo.undoLast(copiedId), isTrue);
    expect((await repo.get(copiedId))?.title, 'Pre poslednje izmene');
    expect(await repo.undoLast(copiedId), isTrue);
    expect((await repo.get(copiedId))?.title, 'Početni recept');
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

  group('oznake', () {
    final aiLabels = RecipeLabels(
      meals: const ['lunch'],
      weight: 'hearty',
      dishKind: 'cooked',
      source: LabelsSource.ai.name,
    );

    test('AI recept čuva oznake; čitaju se nazad iste', () async {
      await repo.create(recipe('a').copyWith(labels: aiLabels));

      final saved = (await repo.get('a'))!.labels;
      expect(saved, aiLabels);
      expect(saved.mealSet, {MealSuitability.lunch});
    });

    test('korisnik menja oznake: bez nove verzije, sa outbox-om', () async {
      await repo.create(recipe('a'));
      await db.delete(db.syncOutbox).go();

      await repo.setLabels(
        'a',
        RecipeLabels.byUser(
          meals: {MealSuitability.dinner, MealSuitability.snack},
          weight: DishWeight.light,
        ),
      );

      final labels = (await repo.get('a'))!.labels;
      expect(labels.meals, ['snack', 'dinner']);
      expect(labels.weightValue, DishWeight.light);
      expect(labels.dishKind, isNull);
      expect(labels.isUserSet, isTrue);
      expect(await repo.watchVersions('a').first, isEmpty);
      final outbox = await db.select(db.syncOutbox).get();
      expect(outbox.map((r) => (r.entity, r.recordId)), [('recipe', 'a')]);
    });

    test('poništavanje i vraćanje verzije čuvaju trenutne oznake', () async {
      await repo.create(recipe('a'));
      await repo.update(recipe('a', title: 'Druga'), kind: ChangeKind.ai);
      final user = RecipeLabels.byUser(meals: {MealSuitability.lunch});
      await repo.setLabels('a', user);

      expect(await repo.undoLast('a'), isTrue);
      expect((await repo.get('a'))!.title, 'Sarma');
      expect((await repo.get('a'))!.labels, user);

      await repo.update(recipe('a', title: 'Treća'), kind: ChangeKind.ai);
      await repo.setLabels('a', user);
      final version = (await repo.watchVersions('a').first).single;
      await repo.restore(version.id);
      expect((await repo.get('a'))!.labels, user);
    });

    test('ručna izmena recepta ne briše oznake', () async {
      await repo.create(recipe('a').copyWith(labels: aiLabels));
      final current = (await repo.get('a'))!;

      await repo.update(
        current.copyWith(title: 'Sarma od zelja'),
        kind: ChangeKind.manual,
      );

      expect((await repo.get('a'))!.labels, aiLabels);
    });

    test('ručna izmena iz zastarele forme ne vraća stare oznake', () async {
      await repo.create(recipe('a').copyWith(labels: aiLabels));
      // Forma je otvorena pre nego što je korisnik promenio oznake.
      final staleForm = (await repo.get('a'))!;
      final user = RecipeLabels.byUser(meals: {MealSuitability.dinner});
      await repo.setLabels('a', user);

      await repo.update(
        staleForm.copyWith(title: 'Sarma od zelja'),
        kind: ChangeKind.manual,
      );

      final saved = (await repo.get('a'))!;
      expect(saved.title, 'Sarma od zelja');
      expect(saved.labels, user);
    });

    test('zastareo AI predlog ne menja novije oznake korisnika', () async {
      await repo.create(recipe('a').copyWith(labels: aiLabels));
      // AI je radio na receptu sa starim oznakama i vratio svoje.
      final proposal = (await repo.get('a'))!.copyWith(
        title: 'Posna sarma',
        labels: RecipeLabels(
          meals: const ['dinner'],
          weight: 'light',
          source: LabelsSource.ai.name,
        ),
      );
      final user = RecipeLabels.byUser(
        meals: {MealSuitability.lunch},
        weight: DishWeight.medium,
      );
      await repo.setLabels('a', user);

      await repo.update(proposal, kind: ChangeKind.ai);

      final saved = (await repo.get('a'))!;
      expect(saved.title, 'Posna sarma');
      expect(saved.labels, user);
    });

    test(
      'AI izmena donosi nove oznake kad korisnik nije postavio svoje',
      () async {
        await repo.create(recipe('a').copyWith(labels: aiLabels));
        final fresh = RecipeLabels(
          meals: const ['dinner'],
          weight: 'light',
          source: LabelsSource.ai.name,
        );

        await repo.update(
          (await repo.get('a'))!.copyWith(labels: fresh),
          kind: ChangeKind.ai,
        );
        expect((await repo.get('a'))!.labels, fresh);

        // AI odgovor bez oznaka ne briše postojeće.
        await repo.update(
          (await repo.get('a'))!.copyWith(labels: RecipeLabels.none),
          kind: ChangeKind.ai,
        );
        expect((await repo.get('a'))!.labels, fresh);
      },
    );
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
        .into(db.recipeEmbeddings)
        .insert(
          RecipeEmbeddingsCompanion.insert(
            recipeId: 'a',
            householdId: scope.householdId,
            contentHash: 'hash',
            model: 'text-embedding-3-small',
            vectorJson: '[0.1]',
            createdAt: now,
          ),
        );
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
    expect(await db.select(db.recipeEmbeddings).get(), isEmpty);
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
