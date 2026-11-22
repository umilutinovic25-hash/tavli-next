import 'package:drift/drift.dart';

import '../domain/food_matcher.dart';
import '../domain/food_nutrition.dart';
import '../sync/catalog_status.dart';
import 'database.dart';

/// Matcher kataloga (018, D1-007) nad lokalnim kešom: deljeni redovi i redovi
/// traženog domaćinstva. Prazan keš (npr. stariji server bez kataloga) daje
/// Unresolved za svako ime. Isto važi kad server javi [CatalogStatus.notOnServer]:
/// ranije preuzet keš se tada ne čita (može biti delimičan, npr. namirnice bez
/// aliasa).
class FoodCatalogReader {
  FoodCatalogReader(this._db);

  final AppDatabase _db;

  Future<FoodMatcher> matcherFor(
    FoodLookupScope scope, {
    required CatalogStatus status,
  }) async {
    if (status == CatalogStatus.notOnServer) return AliasFoodMatcher(const []);
    final hid = scope.householdId;
    final sharedOnly = status == CatalogStatus.accessDenied;
    final foodRows =
        await (_db.select(_db.foods)..where(
              (t) => sharedOnly
                  ? t.householdId.isNull()
                  : t.householdId.isNull() | t.householdId.equals(hid),
            ))
            .get();
    final aliasRows =
        await (_db.select(_db.foodAliases)..where(
              (t) => sharedOnly
                  ? t.householdId.isNull()
                  : t.householdId.isNull() | t.householdId.equals(hid),
            ))
            .get();

    // Osnovna jedinica koju ova verzija ne zna: namirnica se preskače, a sa
    // njom i aliasi (sirova vrednost ostaje u kešu).
    final foods = <String, CatalogFood>{};
    for (final r in foodRows) {
      final unit = FoodBaseUnit.values.asNameMap()[r.baseUnit];
      if (unit == null) continue;
      foods[r.id] = CatalogFood(
        FoodIdentity(
          id: r.id,
          slug: r.slug,
          name: r.name,
          category: r.category,
          baseUnit: unit,
          nutrition: _nutrition(r),
        ),
        householdId: r.householdId,
        withdrawn: r.withdrawnAt != null,
      );
    }
    return AliasFoodMatcher([
      for (final a in aliasRows)
        if (foods[a.foodId] case final f?)
          AliasEntry(
            food: f.food,
            aliasNormalized: a.aliasNormalized,
            householdId: a.householdId,
            withdrawn: a.withdrawnAt != null,
          ),
    ], foods: foods.values.toList());
  }

  FoodNutrition? _nutrition(FoodRow row) {
    final hasValues =
        row.kcalPer100g != null ||
        row.proteinGramsPer100g != null ||
        row.fatGramsPer100g != null ||
        row.carbsGramsPer100g != null;
    if (!hasValues) return null;
    final source = row.nutritionSource;
    final version = row.nutritionSourceVersion;
    final ref = row.nutritionSourceRef;
    if (source == null || version == null || ref == null) return null;
    return FoodNutrition(
      kcalPer100g: row.kcalPer100g,
      proteinGramsPer100g: row.proteinGramsPer100g,
      fatGramsPer100g: row.fatGramsPer100g,
      carbsGramsPer100g: row.carbsGramsPer100g,
      source: source,
      sourceVersion: version,
      sourceRef: ref,
    );
  }
}
