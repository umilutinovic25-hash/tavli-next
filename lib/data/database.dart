import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

// Liste (sastojci, koraci, tipovi obroka) se čuvaju kao JSON tekst:
// uvek se čitaju zajedno sa roditeljskim redom.
//
// Lokalna baza je keš naloga (006a): podaci domaćinstva imaju `householdId`,
// lični podaci `userId`. null = podaci od pre naloga (prebacuju se jednom,
// pri prvoj prijavi). Id-jeve pravi uređaj (tekst), pa ponovljeno slanje
// na server ne pravi duplikate.

@DataClassName('RecipeRow')
class Recipes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  IntColumn get servings => integer()();
  IntColumn get prepMinutes => integer().nullable()();
  TextColumn get source => text()(); // RecipeSource.name
  TextColumn get ingredientsJson => text()();
  TextColumn get stepsJson => text()();

  /// Veze sastojaka i koraka (v12): [{text, uses}], null bez veza.
  TextColumn get stepLinksJson => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  TextColumn get answeredBy => text().nullable()();
  TextColumn get sourceUrl => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get householdId => text().nullable()();

  /// Potvrđeno aktivno i ukupno vreme u minutima (v13).
  IntColumn get activeMinutes => integer().nullable()();
  IntColumn get totalMinutes => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Raspoloživo vreme domaćinstva za jedan dan u nedelji (v13). Id je
/// `<domaćinstvo>-<dan>`, pa dva uređaja pišu isti red.
@DataClassName('DayTimeBudgetRow')
class DayTimeBudgets extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().nullable()();

  /// 1 = ponedeljak … 7 = nedelja.
  IntColumn get weekday => integer()();
  IntColumn get maxActiveMinutes => integer().nullable()();

  /// Prozor za kuvanje u minutima od ponoći.
  IntColumn get windowStart => integer().nullable()();
  IntColumn get windowEnd => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Prethodne verzije recepta, za vraćanje posle AI izmene.
@DataClassName('RecipeVersionRow')
class RecipeVersions extends Table {
  TextColumn get id => text()();
  TextColumn get recipeId => text().references(Recipes, #id)();
  TextColumn get recipeJson => text()();
  TextColumn get instruction => text().nullable()();

  /// ChangeKind.name: kakva izmena je zamenila ovu verziju.
  TextColumn get changeKind => text().withDefault(const Constant('ai'))();

  /// Model koji je napravio AI izmenu.
  TextColumn get changedBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get householdId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PantryItemRow')
@TableIndex(
  name: 'pantry_items_source_item',
  columns: {#sourceShoppingItemId},
  unique: true,
)
class PantryItems extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get quantity => real().nullable()();
  TextColumn get unit => text().nullable()();
  TextColumn get category => text()();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  TextColumn get householdId => text().nullable()();

  /// Kad je osoba potvrdila količinu; samo potvrđena zaliha pokriva potrebu.
  DateTimeColumn get confirmedAt => dateTime().nullable()();

  /// Prijem kupljene stavke: ista zaliha kao ta kupovina, ne nova (v5).
  TextColumn get sourceShoppingItemId => text().nullable()();

  /// Namirnica iz kataloga (036); null = nepotvrđeno, `name` je prikaz.
  TextColumn get foodId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ShoppingListRow')
@TableIndex(
  name: 'shopping_lists_plan_period',
  columns: {#mealPlanId, #periodStart},
  unique: true,
)
class ShoppingLists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get mealPlanId => text().nullable()();

  /// Redni broj nedeljnog dela plana (1–6), null inače.
  IntColumn get week => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get householdId => text().nullable()();

  /// Nedeljni deo plana (kalendarski datumi kao UTC ponoć, v5); null za
  /// listu bez plana i za raniju listu.
  DateTimeColumn get periodStart => dateTime().nullable()();
  DateTimeColumn get periodEnd => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ShoppingItemRow')
class ShoppingItems extends Table {
  TextColumn get id => text()();
  TextColumn get listId => text().references(ShoppingLists, #id)();
  TextColumn get name => text()();
  RealColumn get quantity => real().nullable()();
  TextColumn get unit => text().nullable()();
  TextColumn get category => text()();
  BoolColumn get isBought => boolean().withDefault(const Constant(false))();
  BoolColumn get isManual => boolean().withDefault(const Constant(false))();
  TextColumn get fromRecipeIdsJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get householdId => text().nullable()();

  /// Zamrznuti izvori, porcije i raspodela u trenutku kupovine (v5); kasnije
  /// izmene plana ne menjaju istoriju kupovine.
  TextColumn get purchaseProvenanceJson => text().nullable()();

  TextColumn get brand => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get photoPath => text().nullable()();

  /// Namirnica iz kataloga (036); null = nepotvrđeno, `name` je prikaz.
  TextColumn get foodId => text().nullable()();

  /// Potvrđen proizvod i pakovanje za poređenje cena.
  TextColumn get priceSelectionJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MealPlanRow')
class MealPlans extends Table {
  TextColumn get id => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  TextColumn get mealTypesJson => text()(); // ["breakfast","lunch","dinner"]
  BoolColumn get usePantry => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get householdId => text().nullable()();

  /// Porcije za nove obroke plana (1–20, v5).
  IntColumn get defaultServings => integer().withDefault(const Constant(2))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('WeekTemplateRow')
class WeekTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get mealsJson => text()();
  BoolColumn get usePantry => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MealPlanEntryRow')
class MealPlanEntries extends Table {
  TextColumn get id => text()();
  TextColumn get planId => text().references(MealPlans, #id)();
  DateTimeColumn get date => dateTime()();
  TextColumn get mealType => text()();
  TextColumn get recipeId => text().nullable().references(Recipes, #id)();
  BoolColumn get isLocked => boolean().withDefault(const Constant(false))();
  BoolColumn get isCooked => boolean().withDefault(const Constant(false))();
  TextColumn get householdId => text().nullable()();

  /// Porcije ovog obroka (1–20, v5); null za stari unos (porcije recepta).
  IntColumn get servings => integer().nullable()();

  /// Odobren recept u trenutku planiranja (RecipeSnapshot JSON, v5). Izmena
  /// recepta u biblioteci ne menja plan.
  TextColumn get recipeSnapshotJson => text().nullable()();

  /// `cook` ili `away` (v11): obrok van kuće zauzima mesto bez nabavke.
  TextColumn get kind => text().withDefault(const Constant('cook'))();

  /// `restaurant`, `visiting` ili `skip` (v11), samo za `away`.
  TextColumn get awayReason => text().nullable()();
  TextColumn get awayNote => text().nullable()();

  /// Id-jevi obaveznih pravila dana dozvoljenih baš za ovaj obrok (v14).
  TextColumn get ruleOverridesJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Recept koji osoba želi uskoro da skuva, još bez datuma (v10). Snimak
/// recepta ostaje i kad se recept obriše; potražnju za nabavku pravi tek
/// raspoređivanje u plan.
@DataClassName('CookSoonItemRow')
class CookSoonItems extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().nullable()();
  TextColumn get recipeId => text().nullable().references(Recipes, #id)();
  TextColumn get recipeSnapshotJson => text()();

  /// Porcije pri raspoređivanju (1–20).
  IntColumn get servings => integer()();

  /// Redosled u redu (manji je pre).
  IntColumn get position => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pravilo za dan u nedelji (v14): "ponedeljak bez mesa", "petak riba".
@DataClassName('DayRuleRow')
class DayRules extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().nullable()();

  /// 1 = ponedeljak … 7 = nedelja.
  IntColumn get weekday => integer()();

  /// MealType.name; null = svi obroci.
  TextColumn get mealType => text().nullable()();

  /// RuleKind.name
  TextColumn get kind => text()();
  TextColumn get value => text().nullable()();

  /// RuleMode.name
  TextColumn get mode => text().withDefault(const Constant('required'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Preferencije za ishranu domaćinstva (v15): jedan red po domaćinstvu, id je
/// id domaćinstva. Liste su JSON tekst (kao ostale liste u bazi). Vreme
/// izmene ne čuva se lokalno: sinhronizacija čita `updated_at` sa servera.
@DataClassName('HouseholdPreferenceRow')
class HouseholdPreferences extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().nullable()();

  /// Niz FoodDiet.name: vegetarian, vegan, glutenFree, lactoseFree.
  TextColumn get dietJson => text().withDefault(const Constant('[]'))();

  /// Namirnice koje domaćinstvo ne voli (niz stringova, mala slova).
  TextColumn get dislikesJson => text().withDefault(const Constant('[]'))();

  /// Alergije (niz stringova); AI ih nikad ne sme koristiti.
  TextColumn get allergiesJson => text().withDefault(const Constant('[]'))();

  /// Broj osoba u domaćinstvu (1–20).
  IntColumn get servings => integer().withDefault(const Constant(2))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Alergije jedne osobe u domaćinstvu (v18, 039). Id je
/// `domaćinstvo:osoba`. Svi članovi čitaju redove svog domaćinstva (provera
/// AI recepata važi za uniju), a menja ih samo osoba sama.
@DataClassName('MemberAllergyRow')
class MemberAllergies extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().nullable()();
  TextColumn get userId => text()();

  /// Niz EU kodova (`euAllergens`).
  TextColumn get codesJson => text().withDefault(const Constant('[]'))();

  /// Slobodan unos (niz stringova, mala slova).
  TextColumn get customJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Izvor potražnje u listi (v5): planirani obrok ili samostalna priprema
/// recepta. Id samostalnog izvora je id pripreme.
@DataClassName('ShoppingSourceRow')
@TableIndex(
  name: 'shopping_sources_list_entry',
  columns: {#listId, #planEntryId},
  unique: true,
)
class ShoppingSources extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().nullable()();
  TextColumn get listId => text().references(ShoppingLists, #id)();

  /// ShoppingSourceKind.name: planEntry | recipePreparation.
  TextColumn get kind => text()();
  TextColumn get planEntryId =>
      text().nullable().references(MealPlanEntries, #id)();

  /// Samo samostalna priprema: zamrznut recept, porcije, recept iz
  /// biblioteke (ako postoji) i poreklo (recept ili nesačuvan nacrt).
  TextColumn get recipeSnapshotJson => text().nullable()();
  IntColumn get servings => integer().nullable()();
  TextColumn get recipeId => text().nullable()();
  TextColumn get originKey => text().nullable()();

  /// "Ponovi nabavku" zamenjuje tekuću pripremu novom; stara ostaje istorija.
  DateTimeColumn get supersededAt => dateTime().nullable()();

  /// Skuvano ili uklonjeno: ne pravi novu kupovinu, raspodela ostaje.
  DateTimeColumn get closedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Doprinos jednog izvora jednoj stavci (v5): izvor + sastojak + grupa
/// jedinica. Količina u milionitim delovima osnovne jedinice.
@DataClassName('ShoppingContributionRow')
@TableIndex(
  name: 'shopping_contributions_identity',
  columns: {#sourceId, #ingredientKey, #unitGroup},
  unique: true,
)
class ShoppingContributions extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().nullable()();

  /// Otvorena stavka na kojoj se vidi preostala potreba; null kad je sve
  /// pokriveno zalihom.
  TextColumn get shoppingItemId =>
      text().nullable().references(ShoppingItems, #id)();
  TextColumn get sourceId => text().references(ShoppingSources, #id)();
  TextColumn get ingredientKey => text()();
  TextColumn get unitGroup => text()();
  TextColumn get baseUnit => text()();

  /// null samo kad količina nije poznata (grupa `unknown`).
  IntColumn get micros => integer().nullable()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  TextColumn get notesJson => text().withDefault(const Constant('[]'))();

  /// Količina sadrži približnu meru (kuhinjska mera, rečnik v3): prikaz ~.
  BoolColumn get approximate => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Potvrđena zaliha dodeljena doprinosu (v5): iz ostave ili kupovine,
/// tačno jedno. Prijem kupovine se beleži kao kupovina (ista zaliha).
@DataClassName('SupplyAllocationRow')
@TableIndex(
  name: 'supply_allocations_identity',
  columns: {#contributionId, #supplyId},
  unique: true,
)
class SupplyAllocations extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().nullable()();
  TextColumn get contributionId =>
      text().references(ShoppingContributions, #id)();
  TextColumn get pantryItemId => text().nullable()();
  TextColumn get purchasedShoppingItemId => text().nullable()();

  /// Kanonski identitet zalihe (id kupovine ili stavke ostave).
  TextColumn get supplyId => text().generatedAs(
    coalesce([purchasedShoppingItemId, pantryItemId]),
    stored: true,
  )();
  IntColumn get micros => integer().nullable()();

  /// Osoba je potvrdila da ima celu stavku nepoznate količine.
  BoolColumn get coversWholeUnknown =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RatingRow')
class Ratings extends Table {
  TextColumn get id => text()();
  TextColumn get recipeId => text().references(Recipes, #id)();
  IntColumn get stars => integer()();
  BoolColumn get isComfortFood =>
      boolean().withDefault(const Constant(false))();
  TextColumn get comment => text().nullable()();
  DateTimeColumn get cookedAt => dateTime()();
  TextColumn get userId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Profil ukusa kao JSON (polja će se često menjati). Id je userId osobe;
/// `legacy` za red od pre naloga.
@DataClassName('UserProfileRow')
class UserProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get profileJson => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SavedRecipeSearchRow')
class SavedRecipeSearches extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get query => text()();
  IntColumn get maxMinutes => integer().nullable()();
  TextColumn get includeIngredient => text()();
  TextColumn get excludeIngredient => text()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('ModelStatusRow')
class ModelStatuses extends Table {
  TextColumn get provider => text()();
  TextColumn get model => text()();

  /// KeyOrigin.name: limiti važe posebno za svaki ključ.
  TextColumn get keyOrigin => text().withDefault(const Constant('user'))();
  DateTimeColumn get blockedUntil => dateTime().nullable()();
  IntColumn get requestsToday => integer().withDefault(const Constant(0))();
  TextColumn get usageDay => text().nullable()(); // yyyy-mm-dd
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {provider, model, keyOrigin};
}

/// Nalozi prijavljeni na ovom uređaju: profil i domaćinstvo za pokretanje
/// bez mreže. Sesija (tokeni) se nikad ne čuva ovde, samo u Keychain-u.
@DataClassName('AccountRow')
class Accounts extends Table {
  TextColumn get userId => text()();
  TextColumn get email => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get householdId => text()();
  TextColumn get householdName => text()();
  TextColumn get role => text()();
  BoolColumn get initialDownloadDone =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastPullAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  /// Ručni izbor aktivnog domaćinstva (samo na ovom uređaju); null znači
  /// domaćinstvo kome se korisnik poslednje pridružio.
  TextColumn get preferredHouseholdId => text().nullable()();

  @override
  Set<Column> get primaryKey => {userId};
}

/// Domaćinstva čiji je korisnik član (keš sa servera, bez outbox-a: menja ih
/// samo server). Ceo skup se zamenjuje pri svakom osvežavanju naloga.
@DataClassName('HouseholdMembershipRow')
class HouseholdMemberships extends Table {
  TextColumn get accountId => text()();
  TextColumn get householdId => text()();
  TextColumn get householdName => text()();
  TextColumn get role => text()();
  DateTimeColumn get joinedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {accountId, householdId};
}

/// Članovi domaćinstva sa imenima (keš sa servera, bez imejla i outbox-a).
@DataClassName('HouseholdMemberCacheRow')
class HouseholdMemberCache extends Table {
  TextColumn get accountId => text()();
  TextColumn get householdId => text()();
  TextColumn get userId => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get role => text()();
  DateTimeColumn get joinedAt => dateTime()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {accountId, householdId, userId};
}

/// Izmene koje čekaju slanje na server, redom. Čuva samo šta je promenjeno;
/// sadržaj se čita iz reda u trenutku slanja.
@DataClassName('OutboxRow')
@TableIndex(
  name: 'sync_outbox_account_state_seq',
  columns: {#accountId, #state, #seq},
)
class SyncOutbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get accountId => text()();
  TextColumn get entity => text()();
  TextColumn get recordId => text()();

  /// upsert | delete | photoUpload | photoDelete
  TextColumn get op => text()();

  /// pending | rejected
  TextColumn get state => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  /// Samo kod greške, nikad sadržaj zapisa.
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Dokle je preuzet svaki entitet naloga: (updatedAt, lastId).
@DataClassName('SyncCursorRow')
class SyncCursors extends Table {
  TextColumn get accountId => text()();
  TextColumn get entity => text()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get lastId => text()();

  @override
  Set<Column> get primaryKey => {accountId, entity};
}

/// Namirnica iz kataloga (036). `householdId` null = zajednički katalog
/// (samo za čitanje, stiže sa servera); inače sopstvena namirnica.
@DataClassName('FoodRow')
class Foods extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get category => text()();

  /// `BaseUnit.name`: kom, g ili ml.
  TextColumn get baseUnit => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Normalizovan tekst → namirnica.
@DataClassName('FoodAliasRow')
class FoodAliases extends Table {
  TextColumn get id => text()();
  TextColumn get foodId => text()();
  TextColumn get householdId => text().nullable()();
  TextColumn get alias => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Jedna `unit` = `factorMicros` milionitih delova osnovne jedinice.
@DataClassName('FoodConversionRow')
class FoodConversions extends Table {
  TextColumn get id => text()();
  TextColumn get foodId => text()();
  TextColumn get householdId => text().nullable()();
  TextColumn get unit => text()();
  IntColumn get factorMicros => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Oznaka alergena namirnice; kod iz `euAllergens`.
@DataClassName('FoodAllergenRow')
class FoodAllergens extends Table {
  TextColumn get id => text()();
  TextColumn get foodId => text()();
  TextColumn get householdId => text().nullable()();
  TextColumn get allergenCode => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Recipes,
    RecipeVersions,
    DayTimeBudgets,
    PantryItems,
    ShoppingLists,
    ShoppingItems,
    MealPlans,
    WeekTemplates,
    MealPlanEntries,
    CookSoonItems,
    DayRules,
    HouseholdPreferences,
    MemberAllergies,
    ShoppingSources,
    ShoppingContributions,
    SupplyAllocations,
    Ratings,
    UserProfiles,
    SavedRecipeSearches,
    AppSettings,
    ModelStatuses,
    Accounts,
    HouseholdMemberships,
    HouseholdMemberCache,
    SyncOutbox,
    SyncCursors,
    Foods,
    FoodAliases,
    FoodConversions,
    FoodAllergens,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'tavli'));

  @override
  int get schemaVersion => 20;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Samo keš pauza (najduže jedan dan), pa tabelu pravimo iznova
        // umesto kopiranja redova u novi primarni ključ.
        await m.deleteTable(modelStatuses.actualTableName);
        await m.createTable(modelStatuses);
      }
      if (from < 3) {
        await m.addColumn(recipeVersions, recipeVersions.changeKind);
        await m.addColumn(recipeVersions, recipeVersions.changedBy);
      }
      if (from < 4) await transaction(() => _migrateToAccounts(m));
      if (from < 5) await transaction(() => _migrateToPlanShopping(m));
      if (from < 6) {
        final rows = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'saved_recipe_searches'",
        ).get();
        if (rows.isEmpty) await m.createTable(savedRecipeSearches);
      }
      if (from < 7) {
        final columns = await customSelect('PRAGMA table_info("recipes")')
            .get();
        if (!columns.any((row) => row.read<String>('name') == 'source_url')) {
          await m.addColumn(recipes, recipes.sourceUrl);
        }
      }
      if (from < 8) {
        final rows = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'week_templates'",
        ).get();
        if (rows.isEmpty) await m.createTable(weekTemplates);
      }
      if (from < 9) {
        final columns = await customSelect('PRAGMA table_info(shopping_items)')
            .get();
        final names = {for (final c in columns) c.read<String>('name')};
        if (!names.contains('brand')) {
          await m.addColumn(shoppingItems, shoppingItems.brand);
        }
        if (!names.contains('note')) {
          await m.addColumn(shoppingItems, shoppingItems.note);
        }
        if (!names.contains('photo_path')) {
          await m.addColumn(shoppingItems, shoppingItems.photoPath);
        }
      }
      // v6–v9 koriste druge grane (018–023); red "Uskoro kuvam" je v10.
      if (from < 10) {
        final exists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' "
          "AND name = 'cook_soon_items'",
        ).get();
        if (exists.isEmpty) await m.createTable(cookSoonItems);
      }
      // v6–v10 koriste druge grane (018–025); obrok van kuće je v11.
      if (from < 11) {
        final columns = {
          for (final c in await customSelect(
            'PRAGMA table_info(meal_plan_entries)',
          ).get())
            c.read<String>('name'),
        };
        for (final c in [
          mealPlanEntries.kind,
          mealPlanEntries.awayReason,
          mealPlanEntries.awayNote,
        ]) {
          if (!columns.contains(c.$name)) {
            await m.addColumn(mealPlanEntries, c);
          }
        }
      }
      // v6–v11 koriste druge grane (018–026); veze koraka su v12.
      if (from < 12) {
        final columns = await customSelect('PRAGMA table_info(recipes)').get();
        if (!columns.any((c) => c.read<String>('name') == 'step_links_json')) {
          await m.addColumn(recipes, recipes.stepLinksJson);
        }
      }
      // v6–v12 koriste druge grane (018–027); vreme po danu je v13.
      if (from < 13) {
        final columns = {
          for (final c in await customSelect(
            'PRAGMA table_info(recipes)',
          ).get())
            c.read<String>('name'),
        };
        for (final c in [recipes.activeMinutes, recipes.totalMinutes]) {
          if (!columns.contains(c.$name)) await m.addColumn(recipes, c);
        }
        final tables = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' "
          "AND name = 'day_time_budgets'",
        ).get();
        if (tables.isEmpty) await m.createTable(dayTimeBudgets);
      }
      // v6–v13 koriste druge grane (018–028); pravila po danima su v14.
      if (from < 14) {
        final columns = await customSelect(
          'PRAGMA table_info(meal_plan_entries)',
        ).get();
        if (!columns.any(
          (c) => c.read<String>('name') == 'rule_overrides_json',
        )) {
          await m.addColumn(mealPlanEntries, mealPlanEntries.ruleOverridesJson);
        }
        final tables = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' "
          "AND name = 'day_rules'",
        ).get();
        if (tables.isEmpty) await m.createTable(dayRules);
      }
      // Preferencije za ishranu domaćinstva su v15.
      if (from < 15) {
        final tables = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' "
          "AND name = 'household_preferences'",
        ).get();
        if (tables.isEmpty) await m.createTable(householdPreferences);
      }
      if (from < 16) {
        final columns = await customSelect('PRAGMA table_info(accounts)').get();
        if (!columns.any(
          (c) => c.read<String>('name') == 'preferred_household_id',
        )) {
          await m.addColumn(accounts, accounts.preferredHouseholdId);
        }
        final existing = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('household_memberships', 'household_member_cache')",
        ).get();
        final names = {for (final r in existing) r.read<String>('name')};
        if (!names.contains('household_memberships')) {
          await m.createTable(householdMemberships);
        }
        if (!names.contains('household_member_cache')) {
          await m.createTable(householdMemberCache);
        }
      }
      if (from < 17) {
        for (final (
              TableInfo<Table, Object?> table,
              GeneratedColumn<Object> column,
            )
            in [
              (pantryItems, pantryItems.foodId),
              (shoppingItems, shoppingItems.foodId),
            ]) {
          final columns = await customSelect(
            'PRAGMA table_info(${table.actualTableName})',
          ).get();
          if (!columns.any((c) => c.read<String>('name') == 'food_id')) {
            await m.addColumn(table, column);
          }
        }
        final existing = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('foods', 'food_aliases', 'food_conversions', "
          "'food_allergens')",
        ).get();
        final names = {for (final r in existing) r.read<String>('name')};
        for (final table in <TableInfo<Table, Object?>>[
          foods,
          foodAliases,
          foodConversions,
          foodAllergens,
        ]) {
          if (!names.contains(table.actualTableName)) {
            await m.createTable(table);
          }
        }
      }
      if (from < 18) {
        final existing = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'member_allergies'",
        ).get();
        if (existing.isEmpty) await m.createTable(memberAllergies);
      }
      if (from < 19) {
        final columns = await customSelect('PRAGMA table_info(shopping_items)')
            .get();
        if (!columns.any(
          (c) => c.read<String>('name') == 'price_selection_json',
        )) {
          await m.addColumn(shoppingItems, shoppingItems.priceSelectionJson);
        }
      }
      if (from < 20) {
        final columns = await customSelect(
          'PRAGMA table_info(shopping_contributions)',
        ).get();
        if (!columns.any((c) => c.read<String>('name') == 'approximate')) {
          await m.addColumn(
            shoppingContributions,
            shoppingContributions.approximate,
          );
        }
      }
    },
  );

  /// v5: porcije i odobren recept u planu, nedeljni delovi listi, poreklo
  /// kupovine, prijem u ostavu i tri tabele za izvore, doprinose i
  /// raspodelu zalihe. Postojeći redovi i id-jevi ostaju; stare liste se ne
  /// dele na nedelje.
  Future<void> _migrateToPlanShopping(Migrator m) async {
    // Tabela napravljena iznova u v4 koraku (sa starije verzije) već ima
    // nove kolone.
    Future<void> add(TableInfo<Table, Object?> table, GeneratedColumn c) async {
      final columns = await customSelect(
        'PRAGMA table_info("${table.actualTableName}")',
      ).get();
      if (columns.any((r) => r.read<String>('name') == c.$name)) return;
      await m.addColumn(table, c);
    }

    await add(mealPlans, mealPlans.defaultServings);
    await add(mealPlanEntries, mealPlanEntries.servings);
    await add(mealPlanEntries, mealPlanEntries.recipeSnapshotJson);
    await add(shoppingLists, shoppingLists.periodStart);
    await add(shoppingLists, shoppingLists.periodEnd);
    await add(shoppingItems, shoppingItems.purchaseProvenanceJson);
    await add(pantryItems, pantryItems.confirmedAt);
    await add(pantryItems, pantryItems.sourceShoppingItemId);
    await m.createTable(shoppingSources);
    await m.createTable(shoppingContributions);
    await m.createTable(supplyAllocations);
    final indexes = {
      for (final r in await customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      ).get())
        r.read<String>('name'),
    };
    for (final index in [
      pantryItemsSourceItem,
      shoppingListsPlanPeriod,
      shoppingSourcesListEntry,
      shoppingContributionsIdentity,
      supplyAllocationsIdentity,
    ]) {
      if (!indexes.contains(index.entityName)) await m.createIndex(index);
    }
    // Postojeći obroci dobijaju recept kakav je sada u biblioteci.
    await customStatement('''
      UPDATE meal_plan_entries SET recipe_snapshot_json = (
        SELECT json_object(
          'title', r.title, 'servings', r.servings,
          'prepMinutes', r.prep_minutes,
          'ingredients', json(r.ingredients_json),
          'steps', json(r.steps_json), 'imagePath', r.image_path)
        FROM recipes r WHERE r.id = meal_plan_entries.recipe_id)
      WHERE recipe_id IS NOT NULL
    ''');
  }

  /// v4: tekstualni id-jevi, kolone naloga i tabele za slanje. Postojeći
  /// redovi dobijaju slučajan id i null nalog (prebacuju se pri prijavi).
  Future<void> _migrateToAccounts(Migrator m) async {
    const randomId = CustomExpression<String>('lower(hex(randomblob(16)))');
    final existing = {
      for (final r in await customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ).get())
        r.read<String>('name'),
    };
    // Tabela koje nema (stara delimična šema) se samo napravi.
    Future<void> alter(TableMigration migration) async {
      final table = migration.affectedTable;
      if (!existing.contains(table.actualTableName)) {
        await m.createTable(table);
        return;
      }
      // Starija aplikacija može da vrati user_version na 3 iako su tabele
      // već v4. Već pretvoreni id-jevi i vlasništvo tada moraju da ostanu.
      final columns = await customSelect(
        'PRAGMA table_info("${table.actualTableName}")',
      ).get();
      final types = {
        for (final row in columns)
          row.read<String>('name'): row.read<String>('type').toUpperCase(),
      };
      // Kolone kasnijih verzija (v5…) se takođe dodaju: tabela se pravi
      // po trenutnoj šemi.
      final missing = [
        for (final column in table.$columns)
          if (!types.containsKey(column.$name)) column,
      ];
      final transformers = {
        for (final entry in migration.columnTransformer.entries)
          if (types[entry.key.$name] != 'TEXT') entry.key: entry.value,
      };
      if (missing.isEmpty && transformers.isEmpty) return;
      await m.alterTable(
        TableMigration(
          table,
          newColumns: missing,
          columnTransformer: transformers,
        ),
      );
    }

    await alter(TableMigration(recipes, newColumns: [recipes.householdId]));
    await alter(
      TableMigration(
        recipeVersions,
        columnTransformer: {recipeVersions.id: randomId},
        newColumns: [recipeVersions.householdId],
      ),
    );
    await alter(
      TableMigration(
        pantryItems,
        columnTransformer: {pantryItems.id: randomId},
        newColumns: [pantryItems.householdId],
      ),
    );
    await alter(
      TableMigration(shoppingLists, newColumns: [shoppingLists.householdId]),
    );
    await alter(
      TableMigration(
        shoppingItems,
        columnTransformer: {shoppingItems.id: randomId},
        newColumns: [shoppingItems.householdId],
      ),
    );
    await alter(TableMigration(mealPlans, newColumns: [mealPlans.householdId]));
    await alter(
      TableMigration(
        mealPlanEntries,
        columnTransformer: {mealPlanEntries.id: randomId},
        newColumns: [mealPlanEntries.householdId],
      ),
    );
    await alter(
      TableMigration(
        ratings,
        columnTransformer: {ratings.id: randomId},
        newColumns: [ratings.userId],
      ),
    );
    // Jedan red od pre naloga dobija id 'legacy'.
    await alter(
      TableMigration(
        userProfiles,
        columnTransformer: {
          userProfiles.id: const CustomExpression<String>(
            'CASE WHEN id = (SELECT MIN(id) FROM user_profiles) '
            "THEN 'legacy' ELSE 'legacy-' || id END",
          ),
        },
      ),
    );
    await m.createTable(accounts);
    await m.createTable(syncOutbox);
    final indexes = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    ).get();
    if (!indexes.any(
      (row) => row.read<String>('name') == syncOutboxAccountStateSeq.entityName,
    )) {
      await m.createIndex(syncOutboxAccountStateSeq);
    }
    await m.createTable(syncCursors);
  }
}
