import 'dart:convert';

import '../account/auth_controller.dart';
import '../data/database.dart';
import '../data/recipe_photo_store.dart';
import 'entities.dart';
import 'sync_remote.dart';

/// Preuzima slike recepata i verzija kojih nema na uređaju (posle podataka;
/// do tada se prikazuje zamenska slika). Neuspela slika se pokušava ponovo
/// pri sledećem preuzimanju.
class PhotoSync {
  PhotoSync({
    required this._db,
    required this._remote,
    required this._store,
    required this._scope,
    this.parallel = 4,
    this.onFetched,
  });

  final AppDatabase _db;
  final PhotoRemote _remote;
  final RecipePhotoStore _store;
  final AccountScope _scope;
  final int parallel;
  final void Function(String path)? onFetched;

  /// Vraća broj preuzetih slika.
  Future<int> fetchMissing() async {
    final missing = <String>[];
    for (final p in await _referenced()) {
      if (!await _store.exists(p)) missing.add(p);
    }
    var fetched = 0;
    for (var i = 0; i < missing.length; i += parallel) {
      final chunk = missing.skip(i).take(parallel);
      final results = await Future.wait(chunk.map(_fetch));
      fetched += results.where((ok) => ok).length;
    }
    return fetched;
  }

  Future<bool> _fetch(String path) async {
    try {
      final bytes = await _remote.download(
        '${_scope.householdId}/${photoFileName(path)}',
      );
      await _store.write(path, bytes);
      onFetched?.call(path);
      return true;
    } on SyncError {
      return false;
    }
  }

  Future<Set<String>> _referenced() async {
    final paths = <String>{};
    final recipes = await (_db.select(
      _db.recipes,
    )..where((t) => t.householdId.equals(_scope.householdId))).get();
    for (final r in recipes) {
      if (r.imagePath case final p?) paths.add(p);
    }
    final versions = await (_db.select(
      _db.recipeVersions,
    )..where((t) => t.householdId.equals(_scope.householdId))).get();
    for (final v in versions) {
      try {
        final json = jsonDecode(v.recipeJson);
        if (json is Map && json['imagePath'] is String) {
          paths.add(json['imagePath'] as String);
        }
      } on FormatException {
        // Pokvaren zapis verzije se preskače.
      }
    }
    final shoppingItems = await (_db.select(
      _db.shoppingItems,
    )..where((t) => t.householdId.equals(_scope.householdId))).get();
    for (final item in shoppingItems) {
      if (item.photoPath case final p?) paths.add(p);
    }
    return paths;
  }
}
