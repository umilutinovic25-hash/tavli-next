# Data model: 036 Katalog namirnica

Sve je dodavanje: nijedna postojeća kolona ni tabela se ne briše ni ne menja značenje.

## Nove tabele (server `public` + drift keš)

### foods
| kolona | tip (server) | drift | pravilo |
|---|---|---|---|
| id | text pk, 1–64 | TextColumn | zajednička: slug `f_…` iz seed-a; sopstvena: UUID sa uređaja; nikad se ne menja ni ne koristi ponovo |
| household_id | uuid null → households, cascade | TextColumn nullable | null = zajednički katalog |
| name | text 1–60 | TextColumn | nominativ jednine, mala slova |
| category | text, check ∈ `ingredientCategories` | TextColumn | |
| base_unit | text, check ∈ {kom, g, ml} | TextColumn | stalna (nema update prava) |
| created_at, updated_at, updated_by | timestamptz/uuid | DateTimeColumn | `touch_updated_at('updated_by')` |

Indeks: `(household_id, updated_at, id)` za sync.

### food_aliases
| kolona | tip | pravilo |
|---|---|---|
| id | text pk | zajednički: `<food_id>:<alias>`; sopstveni: UUID |
| food_id | text → foods.id | |
| household_id | uuid null | mora biti isto kao `foods.household_id` (složen FK `(food_id, household_id)` ili trigger; za null — trigger) |
| alias | text 1–60 | check: već normalizovan (trim, mala slova, jedan razmak) |

Jedinstveno: `(alias) where household_id is null`; `(household_id, alias) where household_id is not null`. Trigger: sopstveni alias ne sme postojati u zajedničkom. Naziv namirnice je uvek i njen alias.

### food_conversions
| kolona | tip | pravilo |
|---|---|---|
| id | text pk | |
| food_id, household_id | kao gore | |
| unit | text 1–20 | normalizovan; ne sme biti g/kg/ml/l/kom (već pokriveni) osim `ml` kod namirnice sa `base_unit = g` (gustina) i `g` kod `base_unit = ml` |
| factor_micros | bigint > 0 | milioniti delovi osnovne jedinice za 1 jedinicu |

Jedinstveno: `(food_id, unit)`. Seed u 036 ne puni gustinu (Q1).

### allergens (samo server)
`code text pk` (14 EU kodova), `name_sr text`. Samo `select` za `authenticated`. U Dartu: `const euAllergens` (isti kodovi, srpski nazivi).

### food_allergens
`id text pk`, `food_id`, `household_id`, `allergen_code text → allergens.code`; jedinstveno `(food_id, allergen_code)`. Drift: bez FK na alergene (proverava `euAllergens`).

### Prava (`authenticated`)
| tabela | select | insert | update | delete |
|---|---|---|---|---|
| foods | zajednički ili član | član, `household_id not null` | član (okidač: `base_unit` i `household_id` stalni) | — |
| food_aliases | isto | član, not null | član (okidač: `food_id`, `household_id` stalni) | — |
| food_conversions | isto | član, not null | član (isti okidač) | — |
| food_allergens | isto | član, not null | član (isti okidač) | član, not null |
| allergens | svi | — | — | — |

`update` postoji jer uploader šalje upsert (`on conflict do update`), a Postgres za to traži pravo `update`. `anon`: ništa. Zajednički redovi: samo migracije. Okidač `food_child_check` (security definer) traži da dete ima isto domaćinstvo kao namirnica; `food_alias_not_shared` odbija sopstveni alias koji postoji u zajedničkom katalogu (23505).

## Izmene postojećih tabela

### pantry_items, shopping_items
- `food_id text null → foods(id)` (server); drift `TextColumn foodId nullable`.
- Trigger: `food_id` mora biti zajednička namirnica ili namirnica istog domaćinstva.
- Drift `schemaVersion` 16 → 17: `addColumn` (uz proveru `PRAGMA table_info`, kao v16) + `createTable` za četiri tabele.

### recipes.ingredients (jsonb) / `ingredientsJson`
Sastojak dobija opcioni ključ `foodId` (string). Bez `foodId` JSON ostaje bajt-isti kao danas.

## Domen (lib/domain)

```dart
// recipe.dart — Ingredient
final String? foodId;            // fromJson: _blankToNull(json['foodId'])
Ingredient withFood(String? foodId);
// toJson: 'foodId': ?foodId

// food.dart (novo)
enum BaseUnit { kom, g, ml }
class Food { id, householdId?, name, category, baseUnit; bool get isShared; }
class FoodConversion { foodId, unit, factorMicros }
class FoodCatalog {                 // nepromenljiv pogled na keš
  Food? byId(String id);
  String? match(String text);       // tačan alias; zajednički pre sopstvenog
  FoodConversion? conversion(String foodId, String unit);
  Set<String> allergens(String foodId);
}
class FoodDraft { name, category, baseUnit; validate() → baca FormatException }
const euAllergens = <String, String>{'gluten': 'gluten', 'eggs': 'jaja', …};

// shopping_demand.dart
String dictionaryIngredientKey(String name, int version, {String? foodId});
//   v2: foodId != null ? 'food:$foodId' : v1 ključ
// normalizeUnit: dictionaryVersion 2 = v1 pravila jedinica
// DemandSource: + FoodConversion? po sastojku dolazi iz snimka (R2)

// shopping_source.dart — RecipeSnapshot
// dictionaryVersion: 2; sastojak u snimku: + foodId (nedostajući se popunjava tačnim aliasom)
// snimak: + conversions {"<foodId>|<jedinica>": {factorMicros, baseUnit}} (samo kad nije prazno)
RecipeSnapshot withCurrentDictionary([FoodCatalog? catalog]);  // zamrzava konverzije

// supply_allocation.dart — Supply
final String? foodIngredient;   // 'food:<id>'
final String? foodUnitGroup;
```

## Obračun v2 (sastojak u snimku)

```
if foodId == null:            key = v1 tekst, jedinica = v1 pravila
else:
  key = 'food:<foodId>'
  u = normalizeUnit(unit, v1)
  if snapshot.conversions[conversionKey(foodId, unit)] postoji:
      group = grupa osnovne jedinice (mass/volume/count:kom)
      micros = round(toMicros(q) * factorMicros / 1e6)
  else: group = u.group, micros = toMicros(q) * u.factor
```

## Primer (SC-001)

| izvor | tekst | foodId | porcije | količina | micros |
|---|---|---|---|---|---|
| A (baza 4) | jaja | f_jaje | 2 | 3 kom | 1 500 000 |
| B (baza 2) | jaje | f_jaje | 2 | 2 kom | 2 000 000 |
| Ostava | jajce | f_jaje | — | 2 kom | 2 000 000 |

Potreba `food:f_jaje / count:kom` = 3 500 000; raspodela 2 000 000; za kupovinu **1 500 000 (1,5 kom)**, jedna stavka „jaje“.
