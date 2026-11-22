import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/database.dart';
import '../domain/allergen_group.dart';
import '../domain/plan_calendar.dart';

/// Pripada li zapis domaćinstvu ili osobi.
enum EntityScope { household, user }

/// Jedan entitet koji se čuva na serveru: lokalna drift tabela ↔ tabela
/// na serveru. Mapiranje: camelCase ↔ snake_case, JSON tekst ↔ jsonb,
/// lokalna putanja slike `recipe_photos/x.jpg` ↔ samo `x.jpg`, vreme u UTC.
abstract class SyncEntity<T extends Table, R> {
  const SyncEntity();

  String get name;
  String get remoteTable;
  EntityScope get scope;

  /// Kolona sa id-jem na serveru (`user_id` za profil ukusa).
  String get remoteId => 'id';

  /// Unique remote conflict target. Most tables use [remoteId]; personal
  /// ratings use their account/recipe pair to converge across devices.
  String get remoteConflict => remoteId;

  /// Entitet i kolona svakog stranog ključa u serverskom zapisu.
  List<(String, String)> get parentKeys => const [];

  /// Registar drži roditelje pre deteta.
  Iterable<String> get parents => parentKeys.map((key) => key.$1);

  TableInfo<T, R> table(AppDatabase db);
  Expression<String> idColumn(T t);

  /// Kolona naloga (householdId ili userId).
  GeneratedColumn<String> scopeColumn(T t);

  Map<String, Object?> toRemote(R row);
  Insertable<R> fromRemote(Map<String, Object?> json);

  Future<R?> read(AppDatabase db, String id) => (db.select(
    table(db),
  )..where((t) => idColumn(t).equals(id))).getSingleOrNull();

  Future<void> deleteLocal(AppDatabase db, String id) =>
      (db.delete(table(db))..where((t) => idColumn(t).equals(id))).go();

  Future<void> write(AppDatabase db, Map<String, Object?> json) =>
      db.into(table(db)).insertOnConflictUpdate(fromRemote(json));
}

String _ts(DateTime d) => d.toUtc().toIso8601String();
DateTime _date(Object? v) {
  final text = v! as String;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    return CivilDate.parse(text).toWire();
  }
  return DateTime.parse(text).toLocal();
}

DateTime? _dateOrNull(Object? v) => v == null ? null : _date(v);

/// Kalendarski dan za `date` kolonu na serveru: `YYYY-MM-DD`.
String _day(DateTime d) => CivilDate.fromWire(d).isoDate;
String? _dayOrNull(DateTime? d) => d == null ? null : _day(d);
String? _tsOrNull(DateTime? d) => d == null ? null : _ts(d);
String _json(Object? v) => jsonEncode(v);
String? _jsonOrNull(Object? v) => v == null ? null : jsonEncode(v);
Object? _decodeOrNull(String? s) => s == null ? null : jsonDecode(s);
double? _double(Object? v) => (v as num?)?.toDouble();

/// Lokalna relativna putanja slike → ime fajla na serveru i nazad.
String? photoFileName(String? localPath) => localPath?.split('/').last;
String? photoLocalPath(String? fileName) =>
    fileName == null ? null : 'recipe_photos/$fileName';

class RecipeEntity extends SyncEntity<$RecipesTable, RecipeRow> {
  const RecipeEntity();
  @override
  String get name => 'recipe';
  @override
  String get remoteTable => 'recipes';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  $RecipesTable table(AppDatabase db) => db.recipes;
  @override
  Expression<String> idColumn($RecipesTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($RecipesTable t) => t.householdId;

  @override
  Future<void> deleteLocal(AppDatabase db, String id) =>
      db.transaction(() async {
        await (db.delete(
          db.userFavorites,
        )..where((row) => row.recipeId.equals(id))).go();
        await super.deleteLocal(db, id);
      });

  @override
  Map<String, Object?> toRemote(RecipeRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'title': r.title,
    'servings': r.servings,
    'prep_minutes': r.prepMinutes,
    'source': r.source,
    'ingredients': jsonDecode(r.ingredientsJson),
    'steps': jsonDecode(r.stepsJson),
    'image_path': photoFileName(r.imagePath),
    'answered_by': r.answeredBy,
    'created_at': _ts(r.createdAt),
    'meal_types': r.mealTypesJson == null ? null : jsonDecode(r.mealTypesJson!),
    'weight': r.weight,
    'dish_kind': r.dishKind,
    'labels_source': r.labelsSource,
  };

  @override
  RecipesCompanion fromRemote(Map<String, Object?> j) => RecipesCompanion(
    id: Value(j['id']! as String),
    householdId: Value(j['household_id'] as String?),
    title: Value(j['title']! as String),
    servings: Value(j['servings']! as int),
    prepMinutes: Value(j['prep_minutes'] as int?),
    source: Value(j['source']! as String),
    ingredientsJson: Value(_json(j['ingredients'])),
    stepsJson: Value(_json(j['steps'])),
    imagePath: Value(photoLocalPath(j['image_path'] as String?)),
    answeredBy: Value(j['answered_by'] as String?),
    createdAt: Value(_date(j['created_at'])),
    updatedAt: Value(_date(j['updated_at'] ?? j['created_at'])),
    // Oznake se čuvaju sirove; vrednost koju ova verzija ne zna ostaje.
    mealTypesJson: Value(
      j['meal_types'] is List ? _json(j['meal_types']) : null,
    ),
    weight: Value(j['weight'] as String?),
    dishKind: Value(j['dish_kind'] as String?),
    labelsSource: Value(j['labels_source'] as String?),
  );
}

class RecipeVersionEntity
    extends SyncEntity<$RecipeVersionsTable, RecipeVersionRow> {
  const RecipeVersionEntity();
  @override
  String get name => 'recipe_version';
  @override
  String get remoteTable => 'recipe_versions';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  List<(String, String)> get parentKeys => const [('recipe', 'recipe_id')];
  @override
  $RecipeVersionsTable table(AppDatabase db) => db.recipeVersions;
  @override
  Expression<String> idColumn($RecipeVersionsTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($RecipeVersionsTable t) => t.householdId;

  @override
  Map<String, Object?> toRemote(RecipeVersionRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'recipe_id': r.recipeId,
    'recipe_json': jsonDecode(r.recipeJson),
    'instruction': r.instruction,
    'change_kind': r.changeKind,
    'changed_by': r.changedBy,
    'created_at': _ts(r.createdAt),
  };

  @override
  RecipeVersionsCompanion fromRemote(Map<String, Object?> j) =>
      RecipeVersionsCompanion(
        id: Value(j['id']! as String),
        householdId: Value(j['household_id'] as String?),
        recipeId: Value(j['recipe_id']! as String),
        recipeJson: Value(_json(j['recipe_json'])),
        instruction: Value(j['instruction'] as String?),
        changeKind: Value(j['change_kind']! as String),
        changedBy: Value(j['changed_by'] as String?),
        createdAt: Value(_date(j['created_at'])),
      );
}

/// Nedeljna lista plana (`meal_plan_id` i `period_start` postavljeni) se
/// posle kreiranja ne menja: ID je izveden iz plana i dana
/// (`weekListId`), a uploader je šalje sa `ignoreDuplicates`, pa server
/// tiho odbacuje svaki kasniji upsert istog ID-ja. Izmena takve liste
/// (naziv, arhiviranje, `period_end`) traži da se sa `ignoreDuplicates`
/// šalje samo kreiranje.
class ShoppingListEntity
    extends SyncEntity<$ShoppingListsTable, ShoppingListRow> {
  const ShoppingListEntity();
  @override
  String get name => 'shopping_list';
  @override
  String get remoteTable => 'shopping_lists';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  List<(String, String)> get parentKeys => const [
    ('meal_plan', 'meal_plan_id'),
  ];
  @override
  $ShoppingListsTable table(AppDatabase db) => db.shoppingLists;
  @override
  Expression<String> idColumn($ShoppingListsTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($ShoppingListsTable t) => t.householdId;

  @override
  Map<String, Object?> toRemote(ShoppingListRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'name': r.name,
    'meal_plan_id': r.mealPlanId,
    'week': r.week,
    'period_start': _dayOrNull(r.periodStart),
    'period_end': _dayOrNull(r.periodEnd),
    'created_at': _ts(r.createdAt),
  };

  @override
  ShoppingListsCompanion fromRemote(Map<String, Object?> j) =>
      ShoppingListsCompanion(
        id: Value(j['id']! as String),
        householdId: Value(j['household_id'] as String?),
        name: Value(j['name']! as String),
        mealPlanId: Value(j['meal_plan_id'] as String?),
        week: Value(j['week'] as int?),
        periodStart: Value(_dateOrNull(j['period_start'])),
        periodEnd: Value(_dateOrNull(j['period_end'])),
        createdAt: Value(_date(j['created_at'])),
      );
}

class ShoppingItemEntity
    extends SyncEntity<$ShoppingItemsTable, ShoppingItemRow> {
  const ShoppingItemEntity();
  @override
  String get name => 'shopping_item';
  @override
  String get remoteTable => 'shopping_items';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  List<(String, String)> get parentKeys => const [('shopping_list', 'list_id')];
  @override
  $ShoppingItemsTable table(AppDatabase db) => db.shoppingItems;
  @override
  Expression<String> idColumn($ShoppingItemsTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($ShoppingItemsTable t) => t.householdId;

  @override
  Map<String, Object?> toRemote(ShoppingItemRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'list_id': r.listId,
    'name': r.name,
    'quantity': r.quantity,
    'unit': r.unit,
    'category': r.category,
    'is_bought': r.isBought,
    'is_manual': r.isManual,
    'from_recipe_ids': jsonDecode(r.fromRecipeIdsJson),
    'purchase_provenance': _decodeOrNull(r.purchaseProvenanceJson),
  };

  @override
  ShoppingItemsCompanion fromRemote(Map<String, Object?> j) =>
      ShoppingItemsCompanion(
        id: Value(j['id']! as String),
        householdId: Value(j['household_id'] as String?),
        listId: Value(j['list_id']! as String),
        name: Value(j['name']! as String),
        quantity: Value(_double(j['quantity'])),
        unit: Value(j['unit'] as String?),
        category: Value(j['category']! as String),
        isBought: Value(j['is_bought'] as bool? ?? false),
        isManual: Value(j['is_manual'] as bool? ?? false),
        fromRecipeIdsJson: Value(_json(j['from_recipe_ids'] ?? const [])),
        purchaseProvenanceJson: Value(_jsonOrNull(j['purchase_provenance'])),
      );
}

class PantryItemEntity extends SyncEntity<$PantryItemsTable, PantryItemRow> {
  const PantryItemEntity();
  @override
  String get name => 'pantry_item';
  @override
  String get remoteTable => 'pantry_items';
  @override
  EntityScope get scope => EntityScope.household;

  /// Prijem kupljene stavke ide posle te kupovine.
  @override
  List<(String, String)> get parentKeys => const [
    ('shopping_item', 'source_shopping_item_id'),
  ];
  @override
  $PantryItemsTable table(AppDatabase db) => db.pantryItems;
  @override
  Expression<String> idColumn($PantryItemsTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($PantryItemsTable t) => t.householdId;

  @override
  Map<String, Object?> toRemote(PantryItemRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'name': r.name,
    'quantity': r.quantity,
    'unit': r.unit,
    'category': r.category,
    'added_at': _ts(r.addedAt),
    'expires_at': r.expiresAt == null ? null : _ts(r.expiresAt!),
    'confirmed_at': _tsOrNull(r.confirmedAt),
    'source_shopping_item_id': r.sourceShoppingItemId,
    'quantity_set_at': _tsOrNull(r.quantitySetAt),
  };

  @override
  PantryItemsCompanion fromRemote(Map<String, Object?> j) =>
      PantryItemsCompanion(
        id: Value(j['id']! as String),
        householdId: Value(j['household_id'] as String?),
        name: Value(j['name']! as String),
        quantity: Value(_double(j['quantity'])),
        unit: Value(j['unit'] as String?),
        category: Value(j['category']! as String),
        addedAt: Value(_date(j['added_at'])),
        expiresAt: Value(_dateOrNull(j['expires_at'])),
        confirmedAt: Value(_dateOrNull(j['confirmed_at'])),
        sourceShoppingItemId: Value(j['source_shopping_item_id'] as String?),
        quantitySetAt: Value(_dateOrNull(j['quantity_set_at'])),
      );
}

class MealPlanEntity extends SyncEntity<$MealPlansTable, MealPlanRow> {
  const MealPlanEntity();
  @override
  String get name => 'meal_plan';
  @override
  String get remoteTable => 'meal_plans';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  $MealPlansTable table(AppDatabase db) => db.mealPlans;
  @override
  Expression<String> idColumn($MealPlansTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($MealPlansTable t) => t.householdId;

  @override
  Map<String, Object?> toRemote(MealPlanRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'start_date': _day(r.startDate),
    'end_date': _day(r.endDate),
    'meal_types': jsonDecode(r.mealTypesJson),
    'use_pantry': r.usePantry,
    'default_servings': r.defaultServings,
    'created_at': _ts(r.createdAt),
  };

  @override
  MealPlansCompanion fromRemote(Map<String, Object?> j) => MealPlansCompanion(
    id: Value(j['id']! as String),
    householdId: Value(j['household_id'] as String?),
    startDate: Value(_date(j['start_date'])),
    endDate: Value(_date(j['end_date'])),
    mealTypesJson: Value(_json(j['meal_types'])),
    usePantry: Value(j['use_pantry'] as bool? ?? true),
    defaultServings: Value(j['default_servings'] as int? ?? 2),
    createdAt: Value(_date(j['created_at'])),
  );
}

class MealPlanEntryEntity
    extends SyncEntity<$MealPlanEntriesTable, MealPlanEntryRow> {
  const MealPlanEntryEntity();
  @override
  String get name => 'meal_plan_entry';
  @override
  String get remoteTable => 'meal_plan_entries';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  List<(String, String)> get parentKeys => const [
    ('meal_plan', 'plan_id'),
    ('recipe', 'recipe_id'),
  ];
  @override
  $MealPlanEntriesTable table(AppDatabase db) => db.mealPlanEntries;
  @override
  Expression<String> idColumn($MealPlanEntriesTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($MealPlanEntriesTable t) => t.householdId;

  @override
  Map<String, Object?> toRemote(MealPlanEntryRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'plan_id': r.planId,
    'date': _day(r.date),
    'meal_type': r.mealType,
    'recipe_id': r.recipeId,
    'is_locked': r.isLocked,
    'is_cooked': r.isCooked,
    'servings': r.servings,
    'recipe_snapshot': _decodeOrNull(r.recipeSnapshotJson),
  };

  @override
  MealPlanEntriesCompanion fromRemote(Map<String, Object?> j) =>
      MealPlanEntriesCompanion(
        id: Value(j['id']! as String),
        householdId: Value(j['household_id'] as String?),
        planId: Value(j['plan_id']! as String),
        date: Value(_date(j['date'])),
        mealType: Value(j['meal_type']! as String),
        recipeId: Value(j['recipe_id'] as String?),
        isLocked: Value(j['is_locked'] as bool? ?? false),
        isCooked: Value(j['is_cooked'] as bool? ?? false),
        servings: Value(j['servings'] as int?),
        recipeSnapshotJson: Value(_jsonOrNull(j['recipe_snapshot'])),
      );
}

class RatingEntity extends SyncEntity<$RatingsTable, RatingRow> {
  const RatingEntity();
  @override
  String get name => 'rating';
  @override
  String get remoteTable => 'ratings';
  @override
  String get remoteConflict => 'user_id,recipe_id';
  @override
  EntityScope get scope => EntityScope.user;
  @override
  List<(String, String)> get parentKeys => const [('recipe', 'recipe_id')];
  @override
  $RatingsTable table(AppDatabase db) => db.ratings;
  @override
  Expression<String> idColumn($RatingsTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($RatingsTable t) => t.userId;

  @override
  Map<String, Object?> toRemote(RatingRow r) => {
    'id': r.id,
    'user_id': r.userId,
    'recipe_id': r.recipeId,
    'stars': r.stars,
    'is_comfort_food': r.isComfortFood,
    'comment': r.comment,
    'cooked_at': _ts(r.cookedAt),
  };

  @override
  RatingsCompanion fromRemote(Map<String, Object?> j) => RatingsCompanion(
    id: Value(j['id']! as String),
    userId: Value(j['user_id'] as String?),
    recipeId: Value(j['recipe_id']! as String),
    stars: Value(j['stars']! as int),
    isComfortFood: Value(j['is_comfort_food'] as bool? ?? false),
    comment: Value(j['comment'] as String?),
    cookedAt: Value(_date(j['cooked_at'])),
  );
}

/// Izvor potražnje u listi: planirani obrok ili samostalna priprema.
class ShoppingSourceEntity
    extends SyncEntity<$ShoppingSourcesTable, ShoppingSourceRow> {
  const ShoppingSourceEntity();
  @override
  String get name => 'shopping_source';
  @override
  String get remoteTable => 'shopping_sources';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  List<(String, String)> get parentKeys => const [
    ('shopping_list', 'list_id'),
    ('meal_plan_entry', 'plan_entry_id'),
    ('recipe', 'recipe_id'),
  ];
  @override
  $ShoppingSourcesTable table(AppDatabase db) => db.shoppingSources;
  @override
  Expression<String> idColumn($ShoppingSourcesTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($ShoppingSourcesTable t) => t.householdId;

  @override
  Map<String, Object?> toRemote(ShoppingSourceRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'list_id': r.listId,
    'kind': r.kind,
    'plan_entry_id': r.planEntryId,
    'recipe_snapshot': _decodeOrNull(r.recipeSnapshotJson),
    'servings': r.servings,
    'recipe_id': r.recipeId,
    'origin_key': r.originKey,
    'superseded_at': _tsOrNull(r.supersededAt),
    'closed_at': _tsOrNull(r.closedAt),
    'created_at': _ts(r.createdAt),
  };

  @override
  ShoppingSourcesCompanion fromRemote(Map<String, Object?> j) =>
      ShoppingSourcesCompanion(
        id: Value(j['id']! as String),
        householdId: Value(j['household_id'] as String?),
        listId: Value(j['list_id']! as String),
        kind: Value(j['kind']! as String),
        planEntryId: Value(j['plan_entry_id'] as String?),
        recipeSnapshotJson: Value(_jsonOrNull(j['recipe_snapshot'])),
        servings: Value(j['servings'] as int?),
        recipeId: Value(j['recipe_id'] as String?),
        originKey: Value(j['origin_key'] as String?),
        supersededAt: Value(_dateOrNull(j['superseded_at'])),
        closedAt: Value(_dateOrNull(j['closed_at'])),
        createdAt: Value(_date(j['created_at'])),
      );
}

/// Doprinos izvora stavci; količina u milionitim delovima osnovne jedinice.
class ShoppingContributionEntity
    extends SyncEntity<$ShoppingContributionsTable, ShoppingContributionRow> {
  const ShoppingContributionEntity();
  @override
  String get name => 'shopping_contribution';
  @override
  String get remoteTable => 'shopping_contributions';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  List<(String, String)> get parentKeys => const [
    ('shopping_source', 'source_id'),
    ('shopping_item', 'shopping_item_id'),
  ];
  @override
  $ShoppingContributionsTable table(AppDatabase db) => db.shoppingContributions;
  @override
  Expression<String> idColumn($ShoppingContributionsTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($ShoppingContributionsTable t) =>
      t.householdId;

  @override
  Map<String, Object?> toRemote(ShoppingContributionRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'shopping_item_id': r.shoppingItemId,
    'source_id': r.sourceId,
    'ingredient_key': r.ingredientKey,
    'unit_group': r.unitGroup,
    'base_unit': r.baseUnit,
    'micros': r.micros,
    'name': r.name,
    'category': r.category,
    'notes': jsonDecode(r.notesJson),
  };

  @override
  ShoppingContributionsCompanion fromRemote(Map<String, Object?> j) =>
      ShoppingContributionsCompanion(
        id: Value(j['id']! as String),
        householdId: Value(j['household_id'] as String?),
        shoppingItemId: Value(j['shopping_item_id'] as String?),
        sourceId: Value(j['source_id']! as String),
        ingredientKey: Value(j['ingredient_key']! as String),
        unitGroup: Value(j['unit_group']! as String),
        baseUnit: Value(j['base_unit']! as String),
        micros: Value(j['micros'] as int?),
        name: Value(j['name']! as String),
        category: Value(j['category']! as String),
        notesJson: Value(_json(j['notes'] ?? const [])),
      );
}

/// Potvrđena zaliha dodeljena doprinosu. `supply_id` računa baza (i ovde i
/// na serveru), pa se ne šalje.
class SupplyAllocationEntity
    extends SyncEntity<$SupplyAllocationsTable, SupplyAllocationRow> {
  const SupplyAllocationEntity();
  @override
  String get name => 'supply_allocation';
  @override
  String get remoteTable => 'supply_allocations';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  List<(String, String)> get parentKeys => const [
    ('shopping_contribution', 'contribution_id'),
    ('pantry_item', 'pantry_item_id'),
    ('shopping_item', 'purchased_shopping_item_id'),
  ];
  @override
  $SupplyAllocationsTable table(AppDatabase db) => db.supplyAllocations;
  @override
  Expression<String> idColumn($SupplyAllocationsTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($SupplyAllocationsTable t) =>
      t.householdId;

  @override
  Map<String, Object?> toRemote(SupplyAllocationRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'contribution_id': r.contributionId,
    'pantry_item_id': r.pantryItemId,
    'purchased_shopping_item_id': r.purchasedShoppingItemId,
    'micros': r.micros,
    'covers_whole_unknown': r.coversWholeUnknown,
    'created_at': _ts(r.createdAt),
  };

  @override
  SupplyAllocationsCompanion fromRemote(Map<String, Object?> j) =>
      SupplyAllocationsCompanion(
        id: Value(j['id']! as String),
        householdId: Value(j['household_id'] as String?),
        contributionId: Value(j['contribution_id']! as String),
        pantryItemId: Value(j['pantry_item_id'] as String?),
        purchasedShoppingItemId: Value(
          j['purchased_shopping_item_id'] as String?,
        ),
        micros: Value(j['micros'] as int?),
        coversWholeUnknown: Value(j['covers_whole_unknown'] as bool? ?? false),
        createdAt: Value(_date(j['created_at'])),
      );
}

/// Profil ukusa: lokalni id je userId osobe.
class TasteProfileEntity
    extends SyncEntity<$UserProfilesTable, UserProfileRow> {
  const TasteProfileEntity();
  @override
  String get name => 'taste_profile';
  @override
  String get remoteTable => 'taste_profiles';
  @override
  String get remoteId => 'user_id';
  @override
  EntityScope get scope => EntityScope.user;
  @override
  $UserProfilesTable table(AppDatabase db) => db.userProfiles;
  @override
  Expression<String> idColumn($UserProfilesTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($UserProfilesTable t) => t.id;

  @override
  Map<String, Object?> toRemote(UserProfileRow r) => {
    'user_id': r.id,
    'profile': jsonDecode(r.profileJson),
  };

  @override
  UserProfilesCompanion fromRemote(Map<String, Object?> j) =>
      UserProfilesCompanion(
        id: Value(j['user_id']! as String),
        profileJson: Value(_json(j['profile'])),
      );
}

class FavoriteEntity extends SyncEntity<$UserFavoritesTable, UserFavoriteRow> {
  const FavoriteEntity();

  @override
  String get name => 'favorite';
  @override
  String get remoteTable => 'user_favorites';
  @override
  EntityScope get scope => EntityScope.user;
  @override
  List<(String, String)> get parentKeys => const [('recipe', 'recipe_id')];
  @override
  $UserFavoritesTable table(AppDatabase db) => db.userFavorites;
  @override
  Expression<String> idColumn($UserFavoritesTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($UserFavoritesTable t) => t.userId;

  @override
  Map<String, Object?> toRemote(UserFavoriteRow row) => {
    'id': row.id,
    'user_id': row.userId,
    'recipe_id': row.recipeId,
    'recipe_household_id': row.recipeHouseholdId,
    'is_favorite': row.isFavorite,
  };

  @override
  UserFavoritesCompanion fromRemote(Map<String, Object?> json) =>
      UserFavoritesCompanion.insert(
        id: json['id']! as String,
        userId: json['user_id']! as String,
        recipeId: json['recipe_id']! as String,
        recipeHouseholdId: json['recipe_household_id']! as String,
        isFavorite: json['is_favorite']! as bool,
      );
}

/// Owner-only allergen settings, synced as one replaceable selection.
class AllergenSelectionEntity
    extends SyncEntity<$UserAllergenSelectionsTable, UserAllergenSelectionRow> {
  const AllergenSelectionEntity();

  @override
  String get name => 'allergen_selection';
  @override
  String get remoteTable => 'user_allergen_selections';
  @override
  String get remoteId => 'user_id';
  @override
  EntityScope get scope => EntityScope.user;
  @override
  $UserAllergenSelectionsTable table(AppDatabase db) =>
      db.userAllergenSelections;
  @override
  Expression<String> idColumn($UserAllergenSelectionsTable t) => t.userId;
  @override
  GeneratedColumn<String> scopeColumn($UserAllergenSelectionsTable t) =>
      t.userId;

  @override
  Map<String, Object?> toRemote(UserAllergenSelectionRow row) => {
    'user_id': row.userId,
    'group_codes': jsonDecode(row.groupCodesJson),
  };

  @override
  UserAllergenSelectionsCompanion fromRemote(Map<String, Object?> json) {
    final selection = AllergenGroup.parseSelection(json['group_codes']);
    return UserAllergenSelectionsCompanion.insert(
      userId: json['user_id']! as String,
      groupCodesJson: jsonEncode([
        for (final group in AllergenGroup.values)
          if (selection.contains(group)) group.code,
      ]),
    );
  }
}

/// Obrok označen kao skuvan (zapis operacije; poništavanje ga ne briše).
class CookedEventEntity extends SyncEntity<$CookedEventsTable, CookedEventRow> {
  const CookedEventEntity();
  @override
  String get name => 'cooked_event';
  @override
  String get remoteTable => 'cooked_events';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  List<(String, String)> get parentKeys => const [
    ('meal_plan_entry', 'plan_entry_id'),
  ];
  @override
  $CookedEventsTable table(AppDatabase db) => db.cookedEvents;
  @override
  Expression<String> idColumn($CookedEventsTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($CookedEventsTable t) => t.householdId;

  @override
  Map<String, Object?> toRemote(CookedEventRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'plan_entry_id': r.planEntryId,
    'meal_date': CivilDate.fromWire(r.mealDate).toString(),
    'meal_type': r.mealType,
    'actor_user_id': r.actorUserId,
    'servings': r.servings,
    'cooked_at': _ts(r.cookedAt),
    'undone_at': _tsOrNull(r.undoneAt),
    'undo_reason': r.undoReason,
  };

  @override
  CookedEventsCompanion fromRemote(Map<String, Object?> j) =>
      CookedEventsCompanion(
        id: Value(j['id']! as String),
        householdId: Value(j['household_id'] as String?),
        planEntryId: Value(j['plan_entry_id']! as String),
        mealDate: Value(_date(j['meal_date'])),
        mealType: Value(j['meal_type']! as String),
        actorUserId: Value(j['actor_user_id']! as String),
        servings: Value(j['servings']! as int),
        cookedAt: Value(_date(j['cooked_at'])),
        undoneAt: Value(_dateOrNull(j['undone_at'])),
        undoReason: Value(j['undo_reason'] as String?),
      );
}

/// Koliko je jedno kuvanje uzelo iz jedne stavke ostave.
class PantryConsumptionEntity
    extends SyncEntity<$PantryConsumptionsTable, PantryConsumptionRow> {
  const PantryConsumptionEntity();
  @override
  String get name => 'pantry_consumption';
  @override
  String get remoteTable => 'pantry_consumptions';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  List<(String, String)> get parentKeys => const [
    ('cooked_event', 'event_id'),
    ('pantry_item', 'pantry_item_id'),
  ];
  @override
  $PantryConsumptionsTable table(AppDatabase db) => db.pantryConsumptions;
  @override
  Expression<String> idColumn($PantryConsumptionsTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($PantryConsumptionsTable t) =>
      t.householdId;

  @override
  Map<String, Object?> toRemote(PantryConsumptionRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'event_id': r.eventId,
    'pantry_item_id': r.pantryItemId,
    'base_unit': r.baseUnit,
    'micros': r.micros,
    'created_at': _ts(r.createdAt),
  };

  @override
  PantryConsumptionsCompanion fromRemote(Map<String, Object?> j) =>
      PantryConsumptionsCompanion(
        id: Value(j['id']! as String),
        householdId: Value(j['household_id'] as String?),
        eventId: Value(j['event_id']! as String),
        pantryItemId: Value(j['pantry_item_id']! as String),
        baseUnit: Value(j['base_unit']! as String),
        micros: Value(j['micros']! as int),
        createdAt: Value(_date(j['created_at'])),
      );
}

/// Namirnica kataloga (018). Samo se preuzima: deljene redove piše
/// migracija, a kućni upis dolazi u kasnijem koraku.
class FoodEntity extends SyncEntity<$FoodsTable, FoodRow> {
  const FoodEntity();
  @override
  String get name => 'food';
  @override
  String get remoteTable => 'foods';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  $FoodsTable table(AppDatabase db) => db.foods;
  @override
  Expression<String> idColumn($FoodsTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($FoodsTable t) => t.householdId;

  @override
  Map<String, Object?> toRemote(FoodRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'slug': r.slug,
    'name': r.name,
    'category': r.category,
    'base_unit': r.baseUnit,
    'source': r.source,
    'kcal_per_100g': r.kcalPer100g,
    'protein_grams_per_100g': r.proteinGramsPer100g,
    'fat_grams_per_100g': r.fatGramsPer100g,
    'carbs_grams_per_100g': r.carbsGramsPer100g,
    'nutrition_source': r.nutritionSource,
    'nutrition_source_version': r.nutritionSourceVersion,
    'nutrition_source_ref': r.nutritionSourceRef,
    'reviewed_at': _tsOrNull(r.reviewedAt),
    'withdrawn_at': _tsOrNull(r.withdrawnAt),
    'created_at': _ts(r.createdAt),
  };

  @override
  FoodsCompanion fromRemote(Map<String, Object?> j) => FoodsCompanion(
    id: Value(j['id']! as String),
    householdId: Value(j['household_id'] as String?),
    slug: Value(j['slug']! as String),
    name: Value(j['name']! as String),
    category: Value(j['category']! as String),
    baseUnit: Value(j['base_unit']! as String),
    source: Value(j['source'] as String?),
    kcalPer100g: Value((j['kcal_per_100g'] as num?)?.toDouble()),
    proteinGramsPer100g: Value(
      (j['protein_grams_per_100g'] as num?)?.toDouble(),
    ),
    fatGramsPer100g: Value((j['fat_grams_per_100g'] as num?)?.toDouble()),
    carbsGramsPer100g: Value((j['carbs_grams_per_100g'] as num?)?.toDouble()),
    nutritionSource: Value(j['nutrition_source'] as String?),
    nutritionSourceVersion: Value(j['nutrition_source_version'] as String?),
    nutritionSourceRef: Value(j['nutrition_source_ref'] as String?),
    reviewedAt: Value(_dateOrNull(j['reviewed_at'])),
    withdrawnAt: Value(_dateOrNull(j['withdrawn_at'])),
    createdAt: Value(_date(j['created_at'])),
    updatedAt: Value(_date(j['updated_at'] ?? j['created_at'])),
  );
}

/// Alias namirnice (018). Samo se preuzima, kao i [FoodEntity].
class FoodAliasEntity extends SyncEntity<$FoodAliasesTable, FoodAliasRow> {
  const FoodAliasEntity();
  @override
  String get name => 'food_alias';
  @override
  String get remoteTable => 'food_aliases';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  List<(String, String)> get parentKeys => const [('food', 'food_id')];
  @override
  $FoodAliasesTable table(AppDatabase db) => db.foodAliases;
  @override
  Expression<String> idColumn($FoodAliasesTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($FoodAliasesTable t) => t.householdId;

  @override
  Map<String, Object?> toRemote(FoodAliasRow r) => {
    'id': r.id,
    'food_id': r.foodId,
    'household_id': r.householdId,
    'alias': r.alias,
    'alias_normalized': r.aliasNormalized,
    'withdrawn_at': _tsOrNull(r.withdrawnAt),
    'created_at': _ts(r.createdAt),
  };

  @override
  FoodAliasesCompanion fromRemote(Map<String, Object?> j) =>
      FoodAliasesCompanion(
        id: Value(j['id']! as String),
        foodId: Value(j['food_id']! as String),
        householdId: Value(j['household_id'] as String?),
        alias: Value(j['alias']! as String),
        aliasNormalized: Value(j['alias_normalized']! as String),
        withdrawnAt: Value(_dateOrNull(j['withdrawn_at'])),
        createdAt: Value(_date(j['created_at'])),
        updatedAt: Value(_date(j['updated_at'] ?? j['created_at'])),
      );
}

/// Ime u profilu (lokalno u `Accounts`). Šalje se kao izmena imena, ne upsert.
const profileEntity = 'profile';

/// Svi entiteti sa podacima, redom roditelj pre deteta (slanje i preuzimanje).
/// Entitet može imati više roditelja ([SyncEntity.parents]); redosled je
/// topološki: obroci pre izvora, kupovina pre prijema u ostavu, raspodela
/// poslednja.
const List<SyncEntity<Table, Object?>> syncEntities = [
  RecipeEntity(),
  RecipeVersionEntity(),
  MealPlanEntity(),
  MealPlanEntryEntity(),
  ShoppingListEntity(),
  ShoppingItemEntity(),
  PantryItemEntity(),
  ShoppingSourceEntity(),
  ShoppingContributionEntity(),
  SupplyAllocationEntity(),
  CookedEventEntity(),
  PantryConsumptionEntity(),
  RatingEntity(),
  TasteProfileEntity(),
  AllergenSelectionEntity(),
  FavoriteEntity(),
];

/// Katalog namirnica: van [syncEntities], jer se preuzima posebno (server
/// bez tabela nije greška) i ne šalje se. Namirnica pre aliasa.
const List<SyncEntity<Table, Object?>> catalogEntities = [
  FoodEntity(),
  FoodAliasEntity(),
];

SyncEntity<Table, Object?>? entityByName(String name) {
  for (final e in [...syncEntities, ...catalogEntities]) {
    if (e.name == name) return e;
  }
  return null;
}
