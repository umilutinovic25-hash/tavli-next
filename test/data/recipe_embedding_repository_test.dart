import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/recipe_embedding_repository.dart';
import 'package:tavli/domain/recipe.dart';

Recipe _recipe({String title = 'Pasulj'}) => Recipe(
  id: 'recipe-1',
  title: title,
  servings: 2,
  ingredients: const [Ingredient(name: 'pasulj')],
  source: RecipeSource.manual,
  createdAt: DateTime.utc(2026),
);

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'caches recipe vectors per household and invalidates changed content',
    () async {
      final vector = List<double>.filled(768, 0.25);
      final home = RecipeEmbeddingRepository(db, 'h1');
      final otherHome = RecipeEmbeddingRepository(db, 'h2');
      final recipe = _recipe();

      await home.save(recipe, vector);

      expect(await home.getFor(recipe), vector);
      expect(await home.getFor(_recipe(title: 'Pasulj sa povrćem')), isNull);
      expect(await otherHome.getFor(recipe), isNull);
      expect(await db.select(db.syncOutbox).get(), isEmpty);
    },
  );
}
