import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../domain/account.dart';
import 'database.dart';

/// Verzija formata izvoza. Povećava se kad se menja oblik JSON-a.
const personalExportFormatVersion = 6;

/// Lični izvoz (pravo pristupa podacima). Čist builder: prima samo redove iz
/// baze i podatke naloga, pa u izvoz ne može da uđe ništa drugo (AI ključevi,
/// tokeni sesije i sadržaj secure storage-a nisu u ulazu). Slike se ne
/// izvoze kao bajtovi, samo kao putanje. Od verzije 2 (036) sadrži i
/// sopstvene namirnice domaćinstva; zajednički katalog nije lični podatak.
/// Od verzije 3 (038) sadrži sve tabele aktivnog domaćinstva, sopstveno
/// članstvo i profil ukusa; drugi članovi i druga domaćinstva ne ulaze.
/// Od verzije 4 (039) sadrži i sopstvene alergije u aktivnom domaćinstvu.
Map<String, Object?> buildPersonalExport({
  required DateTime exportedAt,
  required String email,
  String? displayName,
  List<RecipeRow> recipes = const [],
  List<MealPlanRow> mealPlans = const [],
  List<MealPlanEntryRow> mealPlanEntries = const [],
  List<ShoppingListRow> shoppingLists = const [],
  List<ShoppingItemRow> shoppingItems = const [],
  List<PantryItemRow> pantryItems = const [],
  List<SavedRecipeSearchRow> savedRecipeSearches = const [],
  List<DayRuleRow> dayRules = const [],
  List<DayTimeBudgetRow> dayTimeBudgets = const [],
  List<FoodRow> foods = const [],
  List<FoodAliasRow> foodAliases = const [],
  List<FoodConversionRow> foodConversions = const [],
  List<FoodAllergenRow> foodAllergens = const [],
  ExportMembership? membership,
  List<RecipeVersionRow> recipeVersions = const [],
  List<RatingRow> ratings = const [],
  List<WeekTemplateRow> weekTemplates = const [],
  List<CookSoonItemRow> cookSoonItems = const [],
  List<HouseholdPreferenceRow> householdPreferences = const [],
  UserProfileRow? tasteProfile,
  List<ShoppingSourceRow> shoppingSources = const [],
  List<ShoppingContributionRow> shoppingContributions = const [],
  List<SupplyAllocationRow> supplyAllocations = const [],
  MemberAllergyRow? allergies,
}) => {
  'formatVersion': personalExportFormatVersion,
  'exportedAt': _date(exportedAt),
  'account': {'email': email, 'displayName': displayName},
  'sections': {
    'recipes': [for (final r in recipes) _recipe(r)],
    'mealPlans': [for (final p in mealPlans) _mealPlan(p)],
    'mealPlanEntries': [for (final e in mealPlanEntries) _mealPlanEntry(e)],
    'shoppingLists': [for (final l in shoppingLists) _shoppingList(l)],
    'shoppingItems': [for (final i in shoppingItems) _shoppingItem(i)],
    'pantryItems': [for (final p in pantryItems) _pantryItem(p)],
    'savedRecipeSearches': [
      for (final s in savedRecipeSearches) _savedSearch(s),
    ],
    'dayRules': [for (final d in dayRules) _dayRule(d)],
    'dayTimeBudgets': [for (final b in dayTimeBudgets) _dayTimeBudget(b)],
    'foods': [
      for (final f in foods)
        _food(f, foodAliases, foodConversions, foodAllergens),
    ],
    'membership': membership == null ? null : _membership(membership),
    'recipeVersions': [for (final v in recipeVersions) _recipeVersion(v)],
    'ratings': [for (final r in ratings) _rating(r)],
    'weekTemplates': [for (final w in weekTemplates) _weekTemplate(w)],
    'cookSoonItems': [for (final c in cookSoonItems) _cookSoonItem(c)],
    'householdPreferences': [
      for (final p in householdPreferences) _preferences(p),
    ],
    'tasteProfile': tasteProfile == null
        ? null
        : _json(tasteProfile.profileJson),
    'shoppingSources': [for (final s in shoppingSources) _shoppingSource(s)],
    'shoppingContributions': [
      for (final c in shoppingContributions) _contribution(c),
    ],
    'supplyAllocations': [for (final a in supplyAllocations) _allocation(a)],
    'allergies': allergies == null
        ? null
        : {
            'codes': _json(allergies.codesJson),
            'custom': _json(allergies.customJson),
          },
  },
};

/// Čita podatke trenutnog naloga iz lokalne baze i sastavlja izvoz.
/// Lični podaci (sačuvane pretrage) vezani su za `userId`, a podaci
/// domaćinstva za `householdId`, isto kao u repozitorijumima.
Future<Map<String, Object?>> collectPersonalExport(
  AppDatabase db,
  Account account, {
  DateTime Function() clock = DateTime.now,
}) async {
  final hh = account.householdId;
  Future<List<D>> byHousehold<T extends Table, D extends DataClass>(
    TableInfo<T, D> table,
    GeneratedColumn<String> householdId,
  ) => (db.select(table)..where((_) => householdId.equals(hh))).get();

  return buildPersonalExport(
    exportedAt: clock(),
    email: account.email,
    displayName: account.displayName,
    recipes: await byHousehold(db.recipes, db.recipes.householdId),
    mealPlans: await byHousehold(db.mealPlans, db.mealPlans.householdId),
    mealPlanEntries: await byHousehold(
      db.mealPlanEntries,
      db.mealPlanEntries.householdId,
    ),
    shoppingLists: await byHousehold(
      db.shoppingLists,
      db.shoppingLists.householdId,
    ),
    shoppingItems: await byHousehold(
      db.shoppingItems,
      db.shoppingItems.householdId,
    ),
    pantryItems: await byHousehold(db.pantryItems, db.pantryItems.householdId),
    savedRecipeSearches: await (db.select(
      db.savedRecipeSearches,
    )..where((t) => t.userId.equals(account.userId))).get(),
    dayRules: await byHousehold(db.dayRules, db.dayRules.householdId),
    dayTimeBudgets: await byHousehold(
      db.dayTimeBudgets,
      db.dayTimeBudgets.householdId,
    ),
    // Samo sopstvene namirnice (household_id = domaćinstvo); zajednički
    // katalog (null) ne ulazi u izvoz.
    foods: await byHousehold(db.foods, db.foods.householdId),
    foodAliases: await byHousehold(db.foodAliases, db.foodAliases.householdId),
    foodConversions: await byHousehold(
      db.foodConversions,
      db.foodConversions.householdId,
    ),
    foodAllergens: await byHousehold(
      db.foodAllergens,
      db.foodAllergens.householdId,
    ),
    // Samo sopstveno članstvo u aktivnom domaćinstvu; keš članova (imena
    // drugih ljudi) ne ulazi.
    membership: await _ownMembership(db, account),
    recipeVersions: await byHousehold(
      db.recipeVersions,
      db.recipeVersions.householdId,
    ),
    // Samo sopstvene ocene, i to za recepte aktivnog domaćinstva.
    ratings:
        await (db.select(db.ratings)..where(
              (t) =>
                  t.userId.equals(account.userId) &
                  t.recipeId.isInQuery(
                    db.selectOnly(db.recipes)
                      ..addColumns([db.recipes.id])
                      ..where(db.recipes.householdId.equals(hh)),
                  ),
            ))
            .get(),
    weekTemplates: await byHousehold(
      db.weekTemplates,
      db.weekTemplates.householdId,
    ),
    cookSoonItems: await byHousehold(
      db.cookSoonItems,
      db.cookSoonItems.householdId,
    ),
    householdPreferences: await byHousehold(
      db.householdPreferences,
      db.householdPreferences.householdId,
    ),
    tasteProfile: await (db.select(
      db.userProfiles,
    )..where((t) => t.id.equals(account.userId))).getSingleOrNull(),
    shoppingSources: await byHousehold(
      db.shoppingSources,
      db.shoppingSources.householdId,
    ),
    shoppingContributions: await byHousehold(
      db.shoppingContributions,
      db.shoppingContributions.householdId,
    ),
    supplyAllocations: await byHousehold(
      db.supplyAllocations,
      db.supplyAllocations.householdId,
    ),
    // Samo moje alergije u aktivnom domaćinstvu; tuđe ne ulaze.
    allergies:
        await (db.select(db.memberAllergies)..where(
              (t) => t.householdId.equals(hh) & t.userId.equals(account.userId),
            ))
            .getSingleOrNull(),
  );
}

/// Upisuje izvoz kao JSON u [dir] i vraća fajl. Ime nosi datum izvoza.
Future<File> writePersonalExportFile(
  Map<String, Object?> export,
  Directory dir,
) async {
  final at = DateTime.parse(export['exportedAt']! as String).toLocal();
  final day =
      '${at.year.toString().padLeft(4, '0')}-'
      '${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';
  final file = File('${dir.path}/tavli-izvoz-$day.json');
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(export),
    flush: true,
  );
  return file;
}

/// Ako tekst nije ispravan JSON, ostaje kao tekst (ništa se ne gubi).
Object? _json(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}

String? _date(DateTime? d) => d?.toUtc().toIso8601String();

Map<String, Object?> _recipe(RecipeRow r) => {
  'id': r.id,
  'title': r.title,
  'servings': r.servings,
  'prepMinutes': r.prepMinutes,
  'activeMinutes': r.activeMinutes,
  'totalMinutes': r.totalMinutes,
  'source': r.source,
  'sourceUrl': r.sourceUrl,
  'answeredBy': r.answeredBy,
  'ingredients': _json(r.ingredientsJson),
  'steps': _json(r.stepsJson),
  'stepLinks': r.stepLinksJson == null ? null : _json(r.stepLinksJson!),
  'imagePath': r.imagePath,
  'createdAt': _date(r.createdAt),
  'updatedAt': _date(r.updatedAt),
};

Map<String, Object?> _mealPlan(MealPlanRow p) => {
  'id': p.id,
  'startDate': _date(p.startDate),
  'endDate': _date(p.endDate),
  'mealTypes': _json(p.mealTypesJson),
  'usePantry': p.usePantry,
  'defaultServings': p.defaultServings,
  'createdAt': _date(p.createdAt),
};

Map<String, Object?> _mealPlanEntry(MealPlanEntryRow e) => {
  'id': e.id,
  'planId': e.planId,
  'date': _date(e.date),
  'mealType': e.mealType,
  'recipeId': e.recipeId,
  'recipeSnapshot': e.recipeSnapshotJson == null
      ? null
      : _json(e.recipeSnapshotJson!),
  'servings': e.servings,
  'isLocked': e.isLocked,
  'isCooked': e.isCooked,
  'kind': e.kind,
  'awayReason': e.awayReason,
  'awayNote': e.awayNote,
  'ruleOverrides': e.ruleOverridesJson == null
      ? null
      : _json(e.ruleOverridesJson!),
};

Map<String, Object?> _shoppingList(ShoppingListRow l) => {
  'id': l.id,
  'name': l.name,
  'mealPlanId': l.mealPlanId,
  'week': l.week,
  'periodStart': _date(l.periodStart),
  'periodEnd': _date(l.periodEnd),
  'createdAt': _date(l.createdAt),
};

Map<String, Object?> _shoppingItem(ShoppingItemRow i) => {
  'id': i.id,
  'listId': i.listId,
  'name': i.name,
  'foodId': i.foodId,
  'quantity': i.quantity,
  'unit': i.unit,
  'category': i.category,
  'brand': i.brand,
  'note': i.note,
  'isBought': i.isBought,
  'isManual': i.isManual,
  'fromRecipeIds': _json(i.fromRecipeIdsJson),
  'photoPath': i.photoPath,
  'priceSelection': i.priceSelectionJson == null
      ? null
      : _json(i.priceSelectionJson!),
};

Map<String, Object?> _pantryItem(PantryItemRow p) => {
  'id': p.id,
  'name': p.name,
  'foodId': p.foodId,
  'quantity': p.quantity,
  'unit': p.unit,
  'category': p.category,
  'addedAt': _date(p.addedAt),
  'expiresAt': _date(p.expiresAt),
  'confirmedAt': _date(p.confirmedAt),
};

Map<String, Object?> _savedSearch(SavedRecipeSearchRow s) => {
  'id': s.id,
  'name': s.name,
  'query': s.query,
  'maxMinutes': s.maxMinutes,
  'includeIngredient': s.includeIngredient,
  'excludeIngredient': s.excludeIngredient,
};

Map<String, Object?> _dayRule(DayRuleRow d) => {
  'id': d.id,
  'weekday': d.weekday,
  'mealType': d.mealType,
  'kind': d.kind,
  'value': d.value,
  'mode': d.mode,
  'createdAt': _date(d.createdAt),
};

Map<String, Object?> _dayTimeBudget(DayTimeBudgetRow b) => {
  'id': b.id,
  'weekday': b.weekday,
  'maxActiveMinutes': b.maxActiveMinutes,
  'windowStart': b.windowStart,
  'windowEnd': b.windowEnd,
};

Map<String, Object?> _food(
  FoodRow f,
  List<FoodAliasRow> aliases,
  List<FoodConversionRow> conversions,
  List<FoodAllergenRow> allergens,
) => {
  'id': f.id,
  'name': f.name,
  'category': f.category,
  'baseUnit': f.baseUnit,
  'aliases': [
    for (final a in aliases)
      if (a.foodId == f.id) a.alias,
  ]..sort(),
  'conversions': [
    for (final c in conversions)
      if (c.foodId == f.id) {'unit': c.unit, 'factorMicros': c.factorMicros},
  ],
  'allergens': [
    for (final a in allergens)
      if (a.foodId == f.id) a.allergenCode,
  ]..sort(),
};

/// Sopstveno članstvo u aktivnom domaćinstvu.
typedef ExportMembership = ({
  String householdId,
  String householdName,
  String role,
  DateTime? joinedAt,
});

/// Red iz keša članstva; bez njega podaci iz naloga, a `joinedAt` je null.
Future<ExportMembership> _ownMembership(AppDatabase db, Account account) async {
  final row =
      await (db.select(db.householdMemberships)..where(
            (t) =>
                t.accountId.equals(account.userId) &
                t.householdId.equals(account.householdId),
          ))
          .getSingleOrNull();
  return (
    householdId: account.householdId,
    householdName: row?.householdName ?? account.householdName,
    role: row?.role ?? account.role,
    joinedAt: row?.joinedAt,
  );
}

Map<String, Object?> _membership(ExportMembership m) => {
  'householdId': m.householdId,
  'householdName': m.householdName,
  'role': m.role,
  'joinedAt': _date(m.joinedAt),
};

Map<String, Object?> _recipeVersion(RecipeVersionRow v) => {
  'id': v.id,
  'recipeId': v.recipeId,
  'recipe': _json(v.recipeJson),
  'instruction': v.instruction,
  'changeKind': v.changeKind,
  'changedBy': v.changedBy,
  'createdAt': _date(v.createdAt),
};

Map<String, Object?> _rating(RatingRow r) => {
  'id': r.id,
  'recipeId': r.recipeId,
  'stars': r.stars,
  'isComfortFood': r.isComfortFood,
  'comment': r.comment,
  'cookedAt': _date(r.cookedAt),
};

Map<String, Object?> _weekTemplate(WeekTemplateRow w) => {
  'id': w.id,
  'name': w.name,
  'meals': _json(w.mealsJson),
  'usePantry': w.usePantry,
  'createdAt': _date(w.createdAt),
};

Map<String, Object?> _cookSoonItem(CookSoonItemRow c) => {
  'id': c.id,
  'recipeId': c.recipeId,
  'recipeSnapshot': _json(c.recipeSnapshotJson),
  'servings': c.servings,
  'position': c.position,
  'createdAt': _date(c.createdAt),
};

Map<String, Object?> _preferences(HouseholdPreferenceRow p) => {
  'id': p.id,
  'diet': _json(p.dietJson),
  'dislikes': _json(p.dislikesJson),
  'allergies': _json(p.allergiesJson),
  'servings': p.servings,
};

Map<String, Object?> _shoppingSource(ShoppingSourceRow s) => {
  'id': s.id,
  'listId': s.listId,
  'kind': s.kind,
  'planEntryId': s.planEntryId,
  'recipeSnapshot': s.recipeSnapshotJson == null
      ? null
      : _json(s.recipeSnapshotJson!),
  'servings': s.servings,
  'recipeId': s.recipeId,
  'originKey': s.originKey,
  'supersededAt': _date(s.supersededAt),
  'closedAt': _date(s.closedAt),
  'createdAt': _date(s.createdAt),
};

Map<String, Object?> _contribution(ShoppingContributionRow c) => {
  'id': c.id,
  'shoppingItemId': c.shoppingItemId,
  'sourceId': c.sourceId,
  'ingredientKey': c.ingredientKey,
  'unitGroup': c.unitGroup,
  'baseUnit': c.baseUnit,
  'micros': c.micros,
  'name': c.name,
  'category': c.category,
  'notes': _json(c.notesJson),
  'approximate': c.approximate,
};

Map<String, Object?> _allocation(SupplyAllocationRow a) => {
  'id': a.id,
  'contributionId': a.contributionId,
  'pantryItemId': a.pantryItemId,
  'purchasedShoppingItemId': a.purchasedShoppingItemId,
  'micros': a.micros,
  'coversWholeUnknown': a.coversWholeUnknown,
  'createdAt': _date(a.createdAt),
};
