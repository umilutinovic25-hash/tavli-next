import 'package:tavli/data/database.dart';

/// Zajednička namirnica „jaje“ sa aliasima, kao posle preuzimanja (036).
Future<void> seedEggs(AppDatabase db) async {
  await db
      .into(db.foods)
      .insert(
        FoodsCompanion.insert(
          id: 'f_jaje',
          name: 'jaje',
          category: 'mlečni proizvodi i jaja',
          baseUnit: 'kom',
        ),
      );
  for (final a in ['jaje', 'jaja', 'jajce']) {
    await db
        .into(db.foodAliases)
        .insert(
          FoodAliasesCompanion.insert(
            id: 'f_jaje:$a',
            foodId: 'f_jaje',
            alias: a,
          ),
        );
  }
}
