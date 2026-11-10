import 'dart:convert';

import 'package:drift/drift.dart';

import '../account/auth_controller.dart';
import '../domain/ids.dart';
import '../domain/recipe.dart';
import '../domain/recipe_version.dart';
import '../sync/synced_writer.dart';
import 'database.dart';
import 'recipe_photo_store.dart';

/// Recepti i njihove prethodne verzije u lokalnoj bazi (kešu naloga).
/// Čita samo recepte domaćinstva iz [AccountScope]; svaka izmena se u istoj
/// transakciji upisuje i u red za slanje na server ([SyncedWriter]).
class RecipeRepository {
  RecipeRepository(
    this._db,
    this._photos, {
    required this._writer,
    required this._scope,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final RecipePhotoStore _photos;
  final SyncedWriter _writer;
  final AccountScope _scope;
  final DateTime Function() _clock;

  static const _recipe = 'recipe';
  static const _version = 'recipe_version';

  /// Redosled umetanja: id-jevi verzija su slučajni, pa rowid razrešava
  /// verzije sa istim vremenom.
  static const _rowid = CustomExpression<int>('rowid');

  /// Najviše toliko prethodnih verzija po receptu.
  static const maxVersions = 30;

  SimpleSelectStatement<$RecipesTable, RecipeRow> _all() =>
      _db.select(_db.recipes)
        ..where((t) => t.householdId.equals(_scope.householdId))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);

  Stream<List<Recipe>> watchAll() =>
      _all().watch().map((rows) => rows.map(_fromRow).toList());

  /// Svi recepti domaćinstva, jednom (npr. za predlog plana).
  Future<List<Recipe>> getAll() async =>
      (await _all().get()).map(_fromRow).toList();

  SimpleSelectStatement<$RecipesTable, RecipeRow> _one(String id) => _db.select(
    _db.recipes,
  )..where((t) => t.id.equals(id) & t.householdId.equals(_scope.householdId));

  Stream<Recipe?> watch(String id) =>
      _one(id).watchSingleOrNull().map(_fromRowOrNull);

  Future<Recipe?> get(String id) =>
      _one(id).getSingleOrNull().then(_fromRowOrNull);

  Future<void> create(Recipe recipe) => _db.transaction(() async {
    await _db.into(_db.recipes).insert(_toCompanion(recipe));
    await _writer.upsert(_recipe, recipe.id);
    if (recipe.imagePath case final p?) await _writer.photoUpload(p);
  });

  /// Menja recept i čuva prethodno stanje kao verziju.
  Future<void> update(
    Recipe next, {
    required ChangeKind kind,
    String? instruction,
    String? changedBy,
  }) => _db.transaction(() async {
    final current = await get(next.id);
    if (current == null) throw StateError('Recept ${next.id} ne postoji');
    await _addVersion(current, kind, instruction, changedBy);
    await _replace(next);
    if (next.imagePath case final p? when p != current.imagePath) {
      await _writer.photoUpload(p);
    }
  });

  /// Od najnovije ka najstarijoj. Pokvareni zapisi se preskaču.
  Stream<List<RecipeVersion>> watchVersions(String recipeId) =>
      _versionsQuery(recipeId).watch().map(_versionsFromRows);

  Future<List<RecipeVersion>> _versions(String recipeId) =>
      _versionsQuery(recipeId).get().then(_versionsFromRows);

  SimpleSelectStatement<$RecipeVersionsTable, RecipeVersionRow> _versionsQuery(
    String recipeId,
  ) => _db.select(_db.recipeVersions)
    ..where(
      (t) =>
          t.recipeId.equals(recipeId) &
          t.householdId.equals(_scope.householdId),
    )
    ..orderBy([
      (t) => OrderingTerm.desc(t.createdAt),
      (_) => OrderingTerm.desc(_rowid),
    ]);

  static List<RecipeVersion> _versionsFromRows(List<RecipeVersionRow> rows) => [
    for (final r in rows) ?_versionFromRow(r),
  ];

  /// Vraća stanje pre poslednje izmene i briše tu verziju.
  /// Vraća false kad nema šta da se poništi.
  Future<bool> undoLast(String recipeId) => _db.transaction(() async {
    final versions = await _versions(recipeId);
    if (versions.isEmpty) return false;
    final last = versions.first;
    await _replace(last.recipe);
    await (_db.delete(
      _db.recipeVersions,
    )..where((t) => t.id.equals(last.id))).go();
    await _writer.delete(_version, last.id);
    return true;
  });

  /// Vraća izabranu verziju; trenutno stanje se čuva kao nova verzija.
  Future<void> restore(String versionId) => _db.transaction(() async {
    final row =
        await (_db.select(_db.recipeVersions)..where(
              (t) =>
                  t.id.equals(versionId) &
                  t.householdId.equals(_scope.householdId),
            ))
            .getSingle();
    final version = _versionFromRow(row);
    if (version == null) throw StateError('Verzija $versionId je pokvarena');
    await update(version.recipe, kind: ChangeKind.restore);
  });

  /// Briše recept, njegove verzije, ocene i slike (i na serveru).
  Future<void> delete(String id) async {
    final photoPaths = <String>{};
    await _db.transaction(() async {
      final current = await get(id);
      if (current == null) return;
      if (current.imagePath case final p?) photoPaths.add(p);
      final versionIds = [
        for (final v in await (_db.select(
          _db.recipeVersions,
        )..where((t) => t.recipeId.equals(id))).get())
          v.id,
      ];
      for (final v in await _versions(id)) {
        if (v.recipe.imagePath case final p?) photoPaths.add(p);
      }
      await (_db.delete(
        _db.recipeVersions,
      )..where((t) => t.recipeId.equals(id))).go();
      for (final v in versionIds) {
        await _writer.delete(_version, v);
      }
      final ratings = await (_db.select(
        _db.ratings,
      )..where((t) => t.recipeId.equals(id))).get();
      await (_db.delete(_db.ratings)..where((t) => t.recipeId.equals(id))).go();
      for (final r in ratings) {
        if (r.userId == _scope.userId) await _writer.delete('rating', r.id);
      }
      final entries = await (_db.select(
        _db.mealPlanEntries,
      )..where((t) => t.recipeId.equals(id))).get();
      await (_db.update(_db.mealPlanEntries)
            ..where((t) => t.recipeId.equals(id)))
          .write(const MealPlanEntriesCompanion(recipeId: Value(null)));
      for (final e in entries) {
        await _writer.upsert('meal_plan_entry', e.id);
      }
      await (_db.delete(_db.recipes)..where((t) => t.id.equals(id))).go();
      await _writer.delete(_recipe, id);
      // Slika se briše samo ako je nijedan drugi recept ni verzija ne koristi.
      for (final p in [...photoPaths]) {
        if (await _isPhotoUsed(p)) {
          photoPaths.remove(p);
        } else {
          await _writer.photoDelete(p);
        }
      }
    });
    for (final p in photoPaths) {
      await _photos.delete(p);
    }
  }

  Future<bool> _isPhotoUsed(String path) async {
    final inRecipes =
        await (_db.select(_db.recipes)
              ..where(
                (t) =>
                    t.imagePath.equals(path) &
                    t.householdId.equals(_scope.householdId),
              )
              ..limit(1))
            .get();
    if (inRecipes.isNotEmpty) return true;
    final inVersions =
        await (_db.select(_db.recipeVersions)
              ..where(
                (t) =>
                    t.recipeJson.like('%${jsonEncode(path)}%') &
                    t.householdId.equals(_scope.householdId),
              )
              ..limit(1))
            .get();
    return inVersions.isNotEmpty;
  }

  Future<void> _addVersion(
    Recipe previous,
    ChangeKind kind,
    String? instruction,
    String? changedBy,
  ) async {
    final versionId = newId();
    await _db
        .into(_db.recipeVersions)
        .insert(
          RecipeVersionsCompanion.insert(
            id: versionId,
            householdId: Value(_scope.householdId),
            recipeId: previous.id,
            recipeJson: jsonEncode(previous.toJson()),
            instruction: Value(instruction),
            changeKind: Value(kind.name),
            changedBy: Value(changedBy),
            createdAt: _clock(),
          ),
        );
    await _writer.upsert(_version, versionId);
    final keep = _db.selectOnly(_db.recipeVersions)
      ..addColumns([_db.recipeVersions.id])
      ..where(_db.recipeVersions.recipeId.equals(previous.id))
      ..orderBy([
        OrderingTerm.desc(_db.recipeVersions.createdAt),
        OrderingTerm.desc(_rowid),
      ])
      ..limit(maxVersions);
    final pruned =
        await (_db.select(_db.recipeVersions)..where(
              (t) => t.recipeId.equals(previous.id) & t.id.isNotInQuery(keep),
            ))
            .get();
    for (final v in pruned) {
      await (_db.delete(
        _db.recipeVersions,
      )..where((t) => t.id.equals(v.id))).go();
      await _writer.delete(_version, v.id);
    }
  }

  Future<void> _replace(Recipe recipe) async {
    await (_db.update(_db.recipes)..where(
          (t) =>
              t.id.equals(recipe.id) & t.householdId.equals(_scope.householdId),
        ))
        .write(_toCompanion(recipe));
    await _writer.upsert(_recipe, recipe.id);
  }

  RecipesCompanion _toCompanion(Recipe r) => RecipesCompanion.insert(
    id: r.id,
    title: r.title,
    servings: r.servings,
    prepMinutes: Value(r.prepMinutes),
    source: r.source.name,
    ingredientsJson: jsonEncode([for (final i in r.ingredients) i.toJson()]),
    stepsJson: jsonEncode(r.steps),
    imagePath: Value(r.imagePath),
    answeredBy: Value(r.answeredBy),
    sourceUrl: Value(r.sourceUrl),
    createdAt: r.createdAt,
    updatedAt: _clock(),
    householdId: Value(_scope.householdId),
  );

  static Recipe? _fromRowOrNull(RecipeRow? row) =>
      row == null ? null : _fromRow(row);

  static Recipe _fromRow(RecipeRow row) => Recipe(
    id: row.id,
    title: row.title,
    servings: row.servings,
    prepMinutes: row.prepMinutes,
    ingredients: [
      for (final i in jsonDecode(row.ingredientsJson) as List<dynamic>)
        Ingredient.fromJson(i as Map<String, dynamic>),
    ],
    steps: [
      for (final s in jsonDecode(row.stepsJson) as List<dynamic>) s as String,
    ],
    source: RecipeSource.values.asNameMap()[row.source] ?? RecipeSource.manual,
    imagePath: row.imagePath,
    answeredBy: row.answeredBy,
    sourceUrl: row.sourceUrl,
    createdAt: row.createdAt,
  );

  static RecipeVersion? _versionFromRow(RecipeVersionRow row) {
    try {
      return RecipeVersion(
        id: row.id,
        recipeId: row.recipeId,
        recipe: Recipe.fromJson(
          jsonDecode(row.recipeJson) as Map<String, dynamic>,
        ),
        kind: ChangeKind.values.asNameMap()[row.changeKind] ?? ChangeKind.ai,
        instruction: row.instruction,
        changedBy: row.changedBy,
        createdAt: row.createdAt,
      );
    } on FormatException {
      return null;
    }
  }
}
