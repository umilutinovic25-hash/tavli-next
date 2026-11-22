# Nutrition reference and portion-calculation research

**Status:** USDA source mapping is integrated into the shared catalog seed for
Trello #24 after Uroš confirmed the manual catalog review was complete on
2026-11-23. This covers reference values only; it does not ship a diary,
recipe-calculation or nutrition-display feature. Dev 1 evidence for D1-011,
D1-015 and D1-016 / FR-001–003 in [spec 023](spec.md).

## Reference-source observations

The [USDA FoodData Central API guide](https://fdc.nal.usda.gov/api-guide/)
states that FoodData Central data is public domain and published under CC0 1.0;
it requests source attribution. Its [download page](https://fdc.nal.usda.gov/download-datasets/)
identifies SR Legacy as the April 2018 release. The [SR Legacy description](https://fdc.nal.usda.gov/food-search/?query=Fish%2C+mackerel&type=SR+Legacy)
states that this historical data type is not updated. This documents a source
and version, not whether a particular USDA food is an accurate substitute for
a local product.

The official [ANSES Ciqual 2025 documentation](https://ciqual.anses.fr/cms/sites/default/files/inline-files/Table%20Ciqual%202025%20doc%20FR_2025_11_19.pdf)
describes reuse under an Open Licence and conditions including preserving
meaning and identifying source and version. No Ciqual data was imported here;
the relevant team reviewer must assess source terms and version before any use.
No claim is made that either source provides personalized dietary advice.

## SR Legacy extraction

The review worksheet's proposed FDC IDs were joined to the official
[FoodData Central SR Legacy April 2018 CSV release](https://fdc.nal.usda.gov/download-datasets/).
The reproducible extraction command is:

```sh
python3 scripts/build_nutrition_reference_csv.py \
  specs/018-ingredient-catalog/research/catalog-review-worksheet.csv \
  /path/to/FoodData_Central_sr_legacy_food_csv_2018-04.zip \
  specs/023-optional-nutrition/research/nutrition-values-sr-legacy-2018.csv
```

Observed result: 334 worksheet rows; 308 rows (92.2%) have all four requested
nutrients (energy kcal, protein, total fat and carbohydrate). The remaining 26
have no complete USDA record and stay unknown. Values are copied by exact FDC ID
from the dataset's nutrient records, not inferred from food names. The generated
[review artifact](research/nutrition-values-sr-legacy-2018.csv) records the source,
release, FDC reference and CC0 1.0 for complete rows. The artifact does not
alter the worksheet's identity or source review state and is not an application
seed. It does not include Ciqual values.

The extractor test uses a synthetic two-food archive to prove ID-based joining,
unknown preservation and source attribution. Its local result passes. Coverage
is measured against the 334 reviewed worksheet identities. They and 326
unambiguous legacy aliases are seeded by
[`20261123090000_initial_food_catalog_seed.sql`](../../supabase/migrations/20261123090000_initial_food_catalog_seed.sql).
The companion pgTAP test asserts 334 shared foods, 308 fully attributed USDA
records and 26 foods with unknown nutrition. Two historical flour aliases are
omitted because the worksheet maps them to distinct foods. The worksheet's
archival status column still says `pending`; the seed follows Uroš's explicit
confirmation that the catalog review is complete. No allergen data is inferred
or added by this seed.

## Earlier prototype evidence

An earlier prototype of the nutrition features had a catalog of 171 foods, of
which 166 had a USDA SR Legacy mapping and 5 had none, plus a portion
calculation and ingredient-unit conversions. A review of that mapping found
five more questionable entries (coffee, tea, coconut, breadcrumbs and puff
pastry). Removing them would leave 161 of the 171 mapped.
None of this is in team `dev`, and the mapping is not an accepted team seed.
The counts do not describe an active team catalog or prove correctness of the
remaining mappings.

The [portion-calculation fixture](fixtures/recipe_nutrition_test.dart.txt)
holds ten synthetic test cases for a per-portion calculation. It is stored as
text and is not run by the team test suite: the nutrition modules it exercises
do not exist in team `dev`, so these cases are specifications of expected
results for whoever implements the calculation, not passing tests.

All fixture values are synthetic. Two manually checkable examples are:

- 200 g at 77 kcal per 100 g, divided into two portions: `77 kcal/portion`.
- 200 g at 77 kcal per 100 g plus two 50 g pieces at 143 kcal per 100 g,
  divided into two portions: `(154 + 143) / 2 = 148.5 kcal/portion`.

The fixture also checks that missing data is excluded and counted as incomplete,
not treated as zero. It does not establish that actual food matches, densities,
brands, sources or individual results are accurate. Its modules do not exist
on current team `dev`.

The step-free shopping journey is covered by team tests on `dev` (PR #40).
They do not by themselves establish the complete team flow from saving a
step-free meal through shopping and per-portion nutrition.

## Partial-result acceptance case

Use eight recipe ingredients with known quantities and confirmed catalog links.
Give seven ingredients nutrition records and leave the eighth without a record.
The result reports coverage of 7 out of 8 ingredients and marks the per-serving
calculation incomplete. Check that each displayed subtotal equals the sum of
the seven contributions divided by the recipe servings. The missing ingredient
must remain identifiable and must not be treated as a zero-nutrition entry.

The [recipe-detail widget fixture](fixtures/recipe_nutrition_display_test.dart.txt)
for [Trello #28](https://trello.com/c/BX76Fv3o) opens the recipe route with eight
linked foods and a loaded synthetic catalog. With seven 100 g contributions and
two servings, the screen shows `~350 kcal`, 35 g protein, 7 g fat and 52.5 g
carbohydrates per serving with “Računato za 7 od 8 sastojaka.” With all eight
nutrition records absent, the recipe stays visible and both nutrition lines
are hidden. The fixture is not run in this repository: `dev` has no nutrition
screen, `foods` has no nutrition columns, and CI does not execute `.dart.txt`
files. The arithmetic (7 × 100 kcal / 2 servings = 350 kcal) was checked by
hand. The fixture is written against a different API than `dev` has: it sets
`Ingredient.foodId` and `foods.kcal100` and imports
`features/foods/nutrition_line.dart`, while `dev` links an ingredient through
`Ingredient.link` (`IngredientLink`, from #100) and has no nutrition source.
Adapt those three places when the nutrition screen lands, then copy the fixture
to `test/features/recipes/recipe_nutrition_display_test.dart` and run it with
`flutter test`.

Review the display copy and whether partial totals appear in the nutrition
diary with Dev 3. Repeat this case against the accepted Tavli catalog, alongside
a complete control and an unknown-quantity case, before treating the workflow
as verified. The stored fixture does not satisfy that gate.

## Remaining review and integration

- Review each candidate food identity, source version, portion mass/density
  and preparation state. Do not import ambiguous mappings or invent values;
  absent values remain unknown. Reassess the prototype's corrections
  rather than copying either historical seed blindly.
- Agree how consumers represent coverage, approximate conversions and missing
  data. Team acceptance includes a seven-of-eight ingredient case; the stored
  fixture has a synthetic version of it, which still has to be repeated against
  the accepted Tavli catalog.
- Keep attributed reference values separate from private member diaries and
  targets. Tracking is off by default according to [spec 023](spec.md); this
  research does not implement tracking, consent, storage or access control.
- After relevant decisions and catalog/unit dependencies are accepted, test
  the team calculation, step-free meal flow, account isolation and migration
  on the actual team implementation. No clinical accuracy or personalized
  target calculation is established by synthetic unit tests.

No source approval, team review or task completion is asserted by this report.
