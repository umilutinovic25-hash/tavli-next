import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/database.dart';

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

  /// Roditelj (zbog redosleda i brisanja), npr. recipe za recipe_version.
  String? get parent => null;

  /// Ostali roditelji po stranim ključevima (npr. obrok za izvor nabavke).
  List<String> get extraParents => const [];

  /// Svi roditelji: registar ih drži pre ovog entiteta.
  List<String> get parents => [?parent, ...extraParents];

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
DateTime _date(Object? v) => DateTime.parse(v! as String).toLocal();
DateTime? _dateOrNull(Object? v) => v == null ? null : _date(v);
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
  Map<String, Object?> toRemote(RecipeRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'title': r.title,
    'servings': r.servings,
    'prep_minutes': r.prepMinutes,
    'source': r.source,
    'ingredients': jsonDecode(r.ingredientsJson),
    'steps': jsonDecode(r.stepsJson),
    'step_links': _decodeOrNull(r.stepLinksJson),
    'image_path': photoFileName(r.imagePath),
    'answered_by': r.answeredBy,
    'source_url': r.sourceUrl,
    'active_minutes': r.activeMinutes,
    'total_minutes': r.totalMinutes,
    'created_at': _ts(r.createdAt),
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
    stepLinksJson: Value(_jsonOrNull(j['step_links'])),
    imagePath: Value(photoLocalPath(j['image_path'] as String?)),
    answeredBy: Value(j['answered_by'] as String?),
    sourceUrl: Value(j['source_url'] as String?),
    activeMinutes: Value(j['active_minutes'] as int?),
    totalMinutes: Value(j['total_minutes'] as int?),
    createdAt: Value(_date(j['created_at'])),
    updatedAt: Value(_date(j['updated_at'] ?? j['created_at'])),
  );
}

class DayTimeBudgetEntity
    extends SyncEntity<$DayTimeBudgetsTable, DayTimeBudgetRow> {
  const DayTimeBudgetEntity();
  @override
  String get name => 'day_time_budget';
  @override
  String get remoteTable => 'day_time_budgets';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  $DayTimeBudgetsTable table(AppDatabase db) => db.dayTimeBudgets;
  @override
  Expression<String> idColumn($DayTimeBudgetsTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($DayTimeBudgetsTable t) => t.householdId;

  @override
  Map<String, Object?> toRemote(DayTimeBudgetRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'weekday': r.weekday,
    'max_active_minutes': r.maxActiveMinutes,
    'window_start': r.windowStart,
    'window_end': r.windowEnd,
  };

  @override
  DayTimeBudgetsCompanion fromRemote(Map<String, Object?> j) =>
      DayTimeBudgetsCompanion(
        id: Value(j['id']! as String),
        householdId: Value(j['household_id'] as String?),
        weekday: Value(j['weekday']! as int),
        maxActiveMinutes: Value(j['max_active_minutes'] as int?),
        windowStart: Value(j['window_start'] as int?),
        windowEnd: Value(j['window_end'] as int?),
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
  String get parent => 'recipe';
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
  String get parent => 'meal_plan';
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
    'period_start': _tsOrNull(r.periodStart),
    'period_end': _tsOrNull(r.periodEnd),
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
  String get parent => 'shopping_list';
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
    'brand': r.brand,
    'note': r.note,
    'photo_path': photoFileName(r.photoPath),
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
        brand: Value(j['brand'] as String?),
        note: Value(j['note'] as String?),
        photoPath: Value(photoLocalPath(j['photo_path'] as String?)),
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
  List<String> get extraParents => const ['shopping_item'];
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
    'start_date': _ts(r.startDate),
    'end_date': _ts(r.endDate),
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

class WeekTemplateEntity
    extends SyncEntity<$WeekTemplatesTable, WeekTemplateRow> {
  const WeekTemplateEntity();
  @override
  String get name => 'week_template';
  @override
  String get remoteTable => 'week_templates';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  $WeekTemplatesTable table(AppDatabase db) => db.weekTemplates;
  @override
  Expression<String> idColumn($WeekTemplatesTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($WeekTemplatesTable t) => t.householdId;
  @override
  Map<String, Object?> toRemote(WeekTemplateRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'name': r.name,
    'meals': jsonDecode(r.mealsJson),
    'use_pantry': r.usePantry,
    'created_at': _ts(r.createdAt),
  };
  @override
  WeekTemplatesCompanion fromRemote(Map<String, Object?> j) =>
      WeekTemplatesCompanion(
        id: Value(j['id']! as String),
        householdId: Value(j['household_id'] as String?),
        name: Value(j['name']! as String),
        mealsJson: Value(_json(j['meals'])),
        usePantry: Value(j['use_pantry'] as bool? ?? true),
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
  String get parent => 'meal_plan';
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
    'date': _ts(r.date),
    'meal_type': r.mealType,
    'recipe_id': r.recipeId,
    'is_locked': r.isLocked,
    'is_cooked': r.isCooked,
    'servings': r.servings,
    'recipe_snapshot': _decodeOrNull(r.recipeSnapshotJson),
    'kind': r.kind,
    'away_reason': r.awayReason,
    'away_note': r.awayNote,
    'rule_overrides': _decodeOrNull(r.ruleOverridesJson),
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
        kind: Value(j['kind'] as String? ?? 'cook'),
        awayReason: Value(j['away_reason'] as String?),
        awayNote: Value(j['away_note'] as String?),
        ruleOverridesJson: Value(_jsonOrNull(j['rule_overrides'])),
      );
}

class CookSoonItemEntity
    extends SyncEntity<$CookSoonItemsTable, CookSoonItemRow> {
  const CookSoonItemEntity();
  @override
  String get name => 'cook_soon_item';
  @override
  String get remoteTable => 'cook_soon_items';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  List<String> get extraParents => const ['recipe'];
  @override
  $CookSoonItemsTable table(AppDatabase db) => db.cookSoonItems;
  @override
  Expression<String> idColumn($CookSoonItemsTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($CookSoonItemsTable t) => t.householdId;

  @override
  Map<String, Object?> toRemote(CookSoonItemRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'recipe_id': r.recipeId,
    'recipe_snapshot': jsonDecode(r.recipeSnapshotJson),
    'servings': r.servings,
    'position': r.position,
    'created_at': _ts(r.createdAt),
  };

  @override
  CookSoonItemsCompanion fromRemote(Map<String, Object?> j) =>
      CookSoonItemsCompanion(
        id: Value(j['id']! as String),
        householdId: Value(j['household_id'] as String?),
        recipeId: Value(j['recipe_id'] as String?),
        recipeSnapshotJson: Value(_json(j['recipe_snapshot'])),
        servings: Value(j['servings']! as int),
        position: Value(j['position'] as int? ?? 0),
        createdAt: Value(_date(j['created_at'])),
      );
}

class DayRuleEntity extends SyncEntity<$DayRulesTable, DayRuleRow> {
  const DayRuleEntity();
  @override
  String get name => 'day_rule';
  @override
  String get remoteTable => 'day_rules';
  @override
  EntityScope get scope => EntityScope.household;
  @override
  $DayRulesTable table(AppDatabase db) => db.dayRules;
  @override
  Expression<String> idColumn($DayRulesTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($DayRulesTable t) => t.householdId;

  @override
  Map<String, Object?> toRemote(DayRuleRow r) => {
    'id': r.id,
    'household_id': r.householdId,
    'weekday': r.weekday,
    'meal_type': r.mealType,
    'kind': r.kind,
    'value': r.value,
    'mode': r.mode,
    'created_at': _ts(r.createdAt),
  };

  @override
  DayRulesCompanion fromRemote(Map<String, Object?> j) => DayRulesCompanion(
    id: Value(j['id']! as String),
    householdId: Value(j['household_id'] as String?),
    weekday: Value(j['weekday']! as int),
    mealType: Value(j['meal_type'] as String?),
    kind: Value(j['kind']! as String),
    value: Value(j['value'] as String?),
    mode: Value(j['mode'] as String? ?? 'required'),
    createdAt: Value(_date(j['created_at'])),
  );
}

class RatingEntity extends SyncEntity<$RatingsTable, RatingRow> {
  const RatingEntity();
  @override
  String get name => 'rating';
  @override
  String get remoteTable => 'ratings';
  @override
  EntityScope get scope => EntityScope.user;
  @override
  String get parent => 'recipe';
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
  String get parent => 'shopping_list';
  @override
  List<String> get extraParents => const ['meal_plan_entry', 'recipe'];
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
  String get parent => 'shopping_source';
  @override
  List<String> get extraParents => const ['shopping_item'];
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
  String get parent => 'shopping_contribution';
  @override
  List<String> get extraParents => const ['pantry_item', 'shopping_item'];
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

class SavedRecipeSearchEntity
    extends SyncEntity<$SavedRecipeSearchesTable, SavedRecipeSearchRow> {
  const SavedRecipeSearchEntity();
  @override
  String get name => 'saved_recipe_search';
  @override
  String get remoteTable => 'saved_recipe_searches';
  @override
  EntityScope get scope => EntityScope.user;
  @override
  $SavedRecipeSearchesTable table(AppDatabase db) => db.savedRecipeSearches;
  @override
  Expression<String> idColumn($SavedRecipeSearchesTable t) => t.id;
  @override
  GeneratedColumn<String> scopeColumn($SavedRecipeSearchesTable t) => t.userId;
  @override
  Map<String, Object?> toRemote(SavedRecipeSearchRow r) => {
    'id': r.id,
    'user_id': r.userId,
    'name': r.name,
    'query': r.query,
    'max_minutes': r.maxMinutes,
    'include_ingredient': r.includeIngredient,
    'exclude_ingredient': r.excludeIngredient,
  };
  @override
  SavedRecipeSearchesCompanion fromRemote(Map<String, Object?> j) =>
      SavedRecipeSearchesCompanion(
        id: Value(j['id']! as String),
        userId: Value(j['user_id']! as String),
        name: Value(j['name']! as String),
        query: Value(j['query']! as String),
        maxMinutes: Value(j['max_minutes'] as int?),
        includeIngredient: Value(j['include_ingredient']! as String),
        excludeIngredient: Value(j['exclude_ingredient']! as String),
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

/// Ime u profilu (lokalno u `Accounts`). Šalje se kao izmena imena, ne upsert.
const profileEntity = 'profile';

/// Svi entiteti sa podacima, redom roditelj pre deteta (slanje i preuzimanje).
/// Entitet može imati više roditelja ([SyncEntity.parents]); redosled je
/// topološki: obroci pre izvora, kupovina pre prijema u ostavu, raspodela
/// poslednja.
const List<SyncEntity<Table, Object?>> syncEntities = [
  RecipeEntity(),
  RecipeVersionEntity(),
  DayTimeBudgetEntity(),
  MealPlanEntity(),
  WeekTemplateEntity(),
  MealPlanEntryEntity(),
  CookSoonItemEntity(),
  DayRuleEntity(),
  ShoppingListEntity(),
  ShoppingItemEntity(),
  PantryItemEntity(),
  ShoppingSourceEntity(),
  ShoppingContributionEntity(),
  SupplyAllocationEntity(),
  RatingEntity(),
  TasteProfileEntity(),
  SavedRecipeSearchEntity(),
];

SyncEntity<Table, Object?>? entityByName(String name) {
  for (final e in syncEntities) {
    if (e.name == name) return e;
  }
  return null;
}
