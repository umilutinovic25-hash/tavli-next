import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../ai/embedding_client.dart';
import '../domain/recipe.dart';
import 'database.dart';

/// Local cache for private derived data. Vectors are device-local and are not
/// registered as synced entities.
class RecipeEmbeddingRepository {
  const RecipeEmbeddingRepository(this._db, this._householdId);

  final AppDatabase _db;
  final String _householdId;

  Future<List<double>?> getFor(Recipe recipe) async {
    final row =
        await (_db.select(_db.recipeEmbeddings)..where(
              (t) =>
                  t.recipeId.equals(recipe.id) &
                  t.householdId.equals(_householdId),
            ))
            .getSingleOrNull();
    if (row == null ||
        row.model != recipeEmbeddingModel ||
        row.contentHash != recipeEmbeddingContentHash(recipe)) {
      return null;
    }
    try {
      final decoded = jsonDecode(row.vectorJson);
      if (decoded is! List || decoded.length != recipeEmbeddingDimensions) {
        return null;
      }
      final vector = [for (final value in decoded) (value as num).toDouble()];
      return vector.every((value) => value.isFinite) ? vector : null;
    } on Object {
      return null;
    }
  }

  Future<void> save(Recipe recipe, List<double> vector) async {
    if (vector.length != recipeEmbeddingDimensions ||
        vector.any((value) => !value.isFinite)) {
      throw const FormatException('Neispravan vektor recepta');
    }
    await _db
        .into(_db.recipeEmbeddings)
        .insertOnConflictUpdate(
          RecipeEmbeddingsCompanion.insert(
            recipeId: recipe.id,
            householdId: _householdId,
            contentHash: recipeEmbeddingContentHash(recipe),
            model: recipeEmbeddingModel,
            vectorJson: jsonEncode(vector),
            createdAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<void> delete(String recipeId) =>
      (_db.delete(_db.recipeEmbeddings)..where(
            (t) =>
                t.recipeId.equals(recipeId) &
                t.householdId.equals(_householdId),
          ))
          .go();
}

/// Stable text sent to the embedding provider and used to invalidate the
/// cached vector after recipe content changes.
String recipeEmbeddingText(Recipe recipe) => [
  'Naslov: ${recipe.title}',
  'Sastojci: ${recipe.ingredients.map((ingredient) => [if (ingredient.quantity != null) ingredient.quantity, ingredient.unit, ingredient.name, ingredient.note].whereType<Object>().join(' ')).join('; ')}',
  if (recipe.steps.isNotEmpty) 'Priprema: ${recipe.steps.join('. ')}',
].join('\n');

String recipeEmbeddingContentHash(Recipe recipe) =>
    sha256.convert(utf8.encode(recipeEmbeddingText(recipe))).toString();
