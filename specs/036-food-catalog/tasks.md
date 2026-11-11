# Tasks: Katalog namirnica (stalni id namirnice)

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/catalog-csv.md](contracts/catalog-csv.md), [quickstart.md](quickstart.md)

**Tests**: obavezni (ustav V, TDD). Svaki zadatak: napiši test → pokreni i vidi da pada iz pravog razloga → minimalni kod → test prolazi → `dart format lib test scripts` → commit (hook pokreće `scripts/check.sh` i pogođene testove; nikad `--no-verify`, bez `Co-Authored-By`).

**Okruženje**: `export PATH="$HOME/.cache/tavli-flutter-sdk/bin:$PATH"`; posle izmene drift tabela `dart run build_runner build --delete-conflicting-outputs`; Supabase samo lokalno (`supabase start`, portovi 5532x).

**Format**: `- [ ] Tnnn [P?] [USn?] Opis sa putanjom`. Ispod zadatka: testovi (ime → očekivanje). `[P]` = može paralelno (drugi fajlovi, bez zavisnosti od nedovršenog zadatka).

---

## Phase 1: Setup

- [x] T001 Polazna tačka: grana `036-food-catalog` na `origin/main` (`git log --oneline -3` pokazuje `dddbc8f` ispod docs commitova 036); `flutter pub get`; `flutter analyze` čist; `supabase start && supabase db reset && supabase test db` zeleno. Bez commita.
- [x] T002 Izmena ustava 2.0.1 → 2.1.0 u `.specify/memory/constitution.md` (research R9): u principu II, „Server rules“, dodaj izuzetak za referentne podatke bez ličnih podataka (čitljivi svakom `authenticated`, nijedna klijentska uloga ih ne menja, menjaju se samo migracijama); ažuriraj Sync Impact Report. Zaseban commit `docs(constitution): 2.1.0 referentni podaci`.

---

## Phase 2: Foundational (blokira sve priče)

### Zaštita postojećeg ponašanja (prvo)

- [x] T003 Golden test starih snimaka `test/domain/legacy_snapshot_golden_test.dart` (SC-002). Prolazi i **pre** bilo koje izmene; čuva se do kraja.
  - v0 snimak „jaja 3 kom“ + „jaje 2 kom“ (baza 4, porcije 2) → dva `DemandLine`: `jaja` 1 500 000, `jaje` 1 000 000.
  - v0 „češnjak 10 g“ + „beli luk 5 g“ → dva identiteta, 10 000 000 i 5 000 000.
  - v1 isto → jedan `v1:beli luk` 15 000 000.
  - v1 „1 kg brašno“ + „500 grama brašno“ → `v1:brašno` / `mass` 1 500 000 000.
  - `summarize` istih linija daje iste `ShoppingNeed` zbirove i grupe kao danas.
  - JSON snimka v0 i v1 posle `fromJson` → `toJson` je identičan ulazu (bez `foodId`, bez `dictionaryVersion` kod v0).

### Domen (test-first)

- [x] T004 [P] `lib/domain/food.dart` + `test/domain/food_catalog_test.dart`: `BaseUnit`, `Food`, `FoodConversion`, `FoodCatalog`, `FoodDraft`, `euAllergens` (data-model).
  - `match(' Jajce ')` → `f_jaje`; `match('jaj')` → null (nema približnog); zajednički alias ima prednost nad sopstvenim istog teksta.
  - `conversion('f_beli_luk', 'čen')` → 5 000 000; nepoznata jedinica → null.
  - `FoodDraft.validate`: prazan naziv / kategorija van `ingredientCategories` / jedinica van {kom, g, ml} → `FormatException`; naziv se normalizuje (trim, mala slova).
  - `euAllergens.keys` = tačno 14 kodova iz research R11.
- [x] T005 [P] Parser CSV-a `lib/domain/food_catalog_csv.dart` + `test/domain/food_catalog_csv_test.dart` (ugovor `contracts/catalog-csv.md`): ispravan red → `Food` + aliasi (naziv uključen) + konverzije + alergeni; dupli id, dupli alias (i između redova), nepoznata kategorija/jedinica/alergen, konverzija za `g`/`kg`/`l`/`kom` → greška sa brojem reda; polje pod navodnicima sa zarezom radi.
- [x] T006 [P] `Ingredient.foodId` u `lib/domain/recipe.dart`, testovi u `test/domain/recipe_test.dart`: `fromJson` čita `foodId` (prazan → null); `toJson` bez `foodId` je bajt-isti kao danas; `withFood('f_jaje')` čuva `name`, `id`, količinu.

### Server

- [x] T007 Migracija `supabase/migrations/20261112120000_food_catalog.sql`: `allergens` (14 redova), `foods`, `food_aliases`, `food_conversions`, `food_allergens` po data-model (checkovi, indeksi za sync, `touch_updated_at`, `record_deletion`/`skip_if_deleted` gde ima brisanja, trigger senke aliasa, trigger istog `household_id` kao namirnica), RLS i grantovi iz tabele prava. pgTAP `supabase/tests/15_food_catalog_test.sql` (pisan prvi) + dopuna `supabase/tests/01_catalog_test.sql`.
  - Dva naloga A, B (različita domaćinstva): oba čitaju zajednički red; nijedan ne može `insert`/`update` sa `household_id null` (42501 / 0 redova); A pravi sopstvenu namirnicu, B je ne vidi; A ne može da promeni `base_unit` (nema prava na kolonu); `delete` na `foods` nema prava.
  - Alias „jaja“ postoji zajednički → A-ov insert istog aliasa odbijen; alias sa velikim slovom ili duplim razmakom odbijen checkom.
  - `food_allergens` sa kodom van `allergens` → FK greška; `anon` nema prava ni na jednoj novoj tabeli.
- [x] T008 Migracija `supabase/migrations/20261112120100_food_ids.sql`: `food_id` na `pantry_items` i `shopping_items` + trigger (zajednička ili ista domaćinstva). pgTAP u `15_food_catalog_test.sql`: A ne može da postavi `food_id` na B-ovu sopstvenu namirnicu; zajednička i sopstvena A → OK.

### Drift + sync

- [x] T009 Drift v17 u `lib/data/database.dart` (četiri tabele, `foodId` na `PantryItems` i `ShoppingItems`), regenerisan `database.g.dart`, test u `test/data/migration_test.dart`: v16 baza sa redovima → v17, redovi netaknuti, nove kolone null, nove tabele prazne; ponovljen korak ne pada (provera `PRAGMA table_info`).
- [x] T010 Sync entiteti u `lib/sync/entities.dart` (`FoodEntity`, `FoodAliasEntity`, `FoodConversionEntity`, `FoodAllergenEntity`, roditelj `food`) + `food_id` u `PantryItemEntity` i `ShoppingItemEntity`; testovi u `test/sync/entities_test.dart`: `toRemote`/`fromRemote` kružno; red sa `household_id: null` se upisuje lokalno sa `householdId == null`; redosled registra drži `food` pre dece.
- [x] T011 Zajednički redovi preživljavaju promenu naloga/domaćinstva: testovi u `test/sync/household_join_sync_test.dart` i `test/sync/legacy_mover_test.dart` — posle pridruživanju drugom domaćinstvu i posle `LegacyMover` redovi `foods` sa `householdId == null` ostaju (ili se kursor kataloga resetuje pa se ponovo preuzmu — jedno od dva, test kaže koje). Ispravka samo ako test pada.
  - Rezultat: `LegacyMover` je prebacivao zajednički katalog u nalog (test pao) → `SyncEntity.hasSharedRows`, mover preskače katalog. Brisanje nestalog domaćinstva (`account_service`) već briše samo `household_id = ?`; test to čuva. Test je u `test/account/account_service_test.dart`, ne u `household_join_sync_test.dart`.
- [x] T012 `lib/data/food_repository.dart` + `test/data/food_repository_test.dart`: `watchCatalog()` → `FoodCatalog` (zajednički + aktivno domaćinstvo); `createOwn(FoodDraft, aliases, allergens)` u jednoj transakciji piše namirnicu, alias naziva + dodatne aliase, alergene i outbox; alias koji postoji u katalogu → `FoodAliasTakenException` bez ikakvog upisa; `rename`/`recategorize` samo sopstvene.

**Checkpoint**: T003 zelen, `supabase test db` zelen, katalog se preuzima i čita iz drift-a.

---

## Phase 3: User Story 1 — Ista namirnica kroz recept, Ostavu i nabavku (P1) 🎯 MVP

**Cilj**: identitet `food:<id>` u obračunu, zalihi i nabavci. **Nezavisan test**: T018 (SC-001).

- [x] T013 [US1] v2 u `lib/domain/shopping_demand.dart`, testovi u `test/domain/shopping_demand_test.dart` i `test/domain/ingredient_synonyms_test.dart`: `dictionaryIngredientKey(n, 2, foodId: 'f_jaje')` → `food:f_jaje`; bez `foodId` → isto kao v1; v0/v1 nepromenjeni; `demandFor` v2 sa zamrznutom konverzijom „2 čena“ (`factorMicros` 5 000 000) + „10 g“ istog `foodId` → jedan red `mass` 20 000 000; „1 kašika soli“ bez konverzije → grupa `unit:kašika` (imam/nemam, R4); SC-001 domenski: A + B → 3 500 000.
- [x] T014 [US1] Snimak v2 u `lib/domain/shopping_source.dart`, testovi u `test/domain/shopping_source_test.dart`: `withCurrentDictionary(catalog)` → `dictionaryVersion: 2`, `foodId` po sastojku, `conversion` samo gde katalog ima konverziju za tu jedinicu; JSON kružno; posle promene kataloga (čen 5 → 4 g) ponovni obračun istog snimka i dalje daje 20 000 000.
- [x] T015 [US1] Food identitet u `lib/domain/supply_allocation.dart`, testovi u `test/domain/supply_allocation_test.dart`: zaliha „jajce 2 kom“ (`foodIngredient: food:f_jaje`) pokriva v2 potrebu `food:f_jaje`; ista zaliha viđena kao legacy + v1 + food identitet troši se najviše jednom (zbir alokacija ≤ 2 000 000); kupovina i njen prijem (`samePhysicalAs`) i dalje jedan kapacitet.
- [x] T016 [US1] `lib/data/shopping_repository.dart`, testovi u `test/data/shopping_repository_test.dart`: potvrda plana i samostalne nabavke pravi v2 snimak; `Supply` iz Ostave/kupovine sa `food_id` dobija food identitet (trenutna konverzija); nova stavka iz `food:<id>` dobija `food_id` i naziv namirnice (R14), bez namirnice na uređaju → tekst prvog izvora; `totalsOf` grupiše po `food:<id>` kad stavka ima `food_id`.
- [x] T017 [US1] `lib/data/pantry_repository.dart`, test u `test/data/pantry_repository_test.dart`: `receivePurchases` prenosi `food_id` sa kupljene stavke na zalihu.
- [x] T018 [US1] Tok SC-001 kroz repozitorijume `test/data/food_catalog_flow_test.dart`: recepti A, B i zaliha „jajce 2 kom“ sa `f_jaje` → plan potvrđen → jedna otvorena stavka „jaje“, 1,5 kom; kontrola bez `foodId` → stavke „jaja“ 1,5 kom i „jaje“ 2 kom, zaliha ne pokriva ništa.

- [x] T019 [US1] Isti identitet van plana (analiza C1): `ingredientIdentity(String name, String? foodId)` u `lib/domain/shopping_sync.dart` (`food:<id>` kad postoji, inače `ingredientKey(name)`), korišćen u `lib/domain/use_first.dart` (Potroši prvo), `lib/features/recipes/ingredient_review_sheet.dart` (provera Ostave u receptu) i `ShoppingSyncPlan`/„Dodaj u kupovinu“ u `lib/data/shopping_repository.dart`. Poređenje po namirnici samo kad **obe** strane imaju `foodId`; inače tekst kao danas. Testovi u `test/domain/shopping_sync_test.dart`, `test/domain/use_first_test.dart`, `test/data/shopping_repository_test.dart`: zaliha „jajce“ (`f_jaje`) pokriva „jaja“ (`f_jaje`) u Potroši prvo i u proveri Ostave; bez `foodId` ponašanje isto kao pre (postojeći testovi nepromenjeni i zeleni).
  - Izvedeno: umesto jednog ključa `ingredientIdentity` uvedeno je poređenje para `sameIngredient(aName, aFood, bName, bFood)` (pravilo „obe strane“ ne može jednim ključem). Isto pravilo važi i u raspodeli zalihe (`supplyCovers`): potreba po namirnici se pokriva zalihom bez namirnice istog teksta, da stari redovi Ostave ne izgube pokriće kad recept dobije `foodId`; druga namirnica istog teksta ne pokriva. „Potroši prvo“ sada računa po v2 (nepotvrđeno = v1 tekst, uključujući češnjak → beli luk).

**Checkpoint**: SC-001 zelen; T003 i dalje zelen.

---

## Phase 4: User Story 2 — Potvrda namirnice pri unosu (P1)

**Nezavisan test**: „Jajce“ → `f_jaje` automatski; „zmajevo voće“ → nepotvrđeno → nova namirnica.

- [x] T020 [US2] Automatska popuna `foodId` (samo kad je null, nikad ne prepisuje izbor) u `lib/data/recipe_repository.dart`, `pantry_repository.dart`, `shopping_repository.dart` (ručne stavke); testovi u odgovarajućim `test/data/*_test.dart`: „Jajce “ → `f_jaje`, tekst „Jajce“ ostaje; ručno izabran drugi `foodId` se ne menja; nepoznat tekst → null, čuvanje uspeva.
- [x] T021 [P] [US2] `lib/features/foods/`: `FoodChip` („Nepotvrđeno“ / naziv namirnice), `FoodPickerSheet` („Izaberi namirnicu“, „Pretraži namirnice“, „Nova namirnica“), `NewFoodForm` („Naziv namirnice“, „Kategorija“, „Osnovna jedinica“, „Sačuvaj kao moju namirnicu“, greška „Ova namirnica već postoji u katalogu.“); widget testovi u `test/features/foods/`: pretraga po aliasu nalazi namirnicu; „Nova namirnica“ iz nepotvrđenog reda nudi upisani tekst kao naziv i čuva ga kao alias (US2 AC4); zauzet alias → poruka, bez upisa; sheet na uskoj, dijalog na širokoj širini.
  - Izvedeno: `pickFood(context, text:, category:, unit:)` u `food_picker.dart` vraća id namirnice; `FoodCatalog.search` (domen) pretražuje nazive i aliase; `foodRepositoryProvider` i `foodCatalogProvider` u `lib/providers.dart`. Nova namirnica čuva i upisani tekst i naziv kao aliase.
- [x] T022 [US2] Forma recepta `lib/features/recipes/recipe_form_screen.dart` (dijalog sastojka) koristi `FoodChip`/`FoodPickerSheet`; widget test u `test/features/recipes/`: nepotvrđen sastojak prikazuje „Nepotvrđeno“, izbor upisuje `foodId`, tekst nepromenjen, kategorija sastojka se popunjava kategorijom namirnice (osoba je može promeniti); promena namirnice i čuvanje pravi novu verziju recepta (postojeći `_addVersion`), snimak već potvrđenog plana nepromenjen.
  - Izvedeno: dijalog sastojka je ranije gubio `foodId` pri izmeni (gradio sastojak bez njega); sada ga čuva (test „izmena sastojka bez izbora čuva postojeću namirnicu“). Red u listi sastojaka nepotvrđenog sastojka nosi „· Nepotvrđeno“.
- [ ] T023 [P] [US2] Forme Ostave (`lib/features/pantry/pantry_form_screen.dart`) i stavke nabavke (`lib/features/shopping/`) koriste iste widgete; widget testovi za izbor i za „Nepotvrđeno“.

---

## Phase 5: User Story 3 — Postojeći podaci i stari snimci (P1)

**Nezavisan test**: T003 + T026.

- [x] T024 [US3] Generator `scripts/catalog_seed.dart` (koristi parser iz T005; izlaz SQL po ugovoru, `on conflict (id) do nothing`, upozorenje za alias koji zaklanja postojeći) + test `test/scripts/catalog_seed_test.dart` (mali CSV → očekivan SQL).
  - Izvedeno: čista funkcija `catalogSeedSql` je u `lib/domain/food_catalog_csv.dart` (test u `test/domain/food_catalog_csv_test.dart`); skripta samo čita CSV i piše SQL. Upozorenje o senci sopstvenog aliasa nije moguće bez baze; sukob sa postojećim zajedničkim aliasom obara migraciju (jedinstveni indeks).
- [x] T025 [US3] `supabase/catalog/foods.csv` (~150–250 namirnica: rečnik 018, jedinice/sastojci iz `lib/ai/prompts.dart`, ručni spisak; dvosmisleni aliasi izostavljeni) i generisana `supabase/migrations/20261112120200_food_catalog_seed.sql`. pgTAP: `f_jaje` postoji sa aliasima „jaja“, „jajce“; `f_beli_luk` ima „češnjak“ i konverziju čen = 5 000 000; broj zajedničkih namirnica u opsegu 150–250. **CSV pregleda tim pre spajanja** (napomena u PR-u).
- [x] T026 [US3] Jednokratno mapiranje `supabase/migrations/20261112120300_food_mapping.sql` (`recipes.ingredients` jsonb, `pantry_items`, `shopping_items`, samo tačan zajednički alias); pgTAP (SC-003): recept sa „Jaja“ i „zmajevo voće“ → prvi dobija `foodId: f_jaje`, drugi bez ključa; `name`/`quantity`/`unit` svih redova nepromenjeni; `recipe_versions` i `shopping_sources` nepromenjeni (hash pre/posle); `updated_by` zadržan.
  - Izvedeno: logika u `private.map_food_ids()` (migracija je poziva jednom; pgTAP `supabase/tests/17_food_mapping_test.sql` je poziva nad svojim redovima). Menja samo redove kojima nedostaje namirnica, pa nepromenjeni recepti zadržavaju `updated_at`; prazan `foodId` se tretira kao nepostojeći (kao u `Ingredient.fromJson`).

---

## Phase 6: User Story 4 — AI ne piše u katalog (P2)

- [x] T027 [US4] `suggestFood(Ingredient)` u `lib/domain/food.dart`, testovi u `test/domain/food_catalog_test.dart`: „mango 200 g“ kategorija „voće i povrće“ → nacrt sa `g`; jedinica „kašika“ → nacrt bez osnovne jedinice (osoba bira); prazan naziv → nema predloga; nikad ne vraća nacrt sa `household_id null`.
  - Izvedeno: `FoodDraft` nema `householdId`; domaćinstvo uvek dodeljuje `FoodRepository.createOwn`, pa nacrt ne može postati zajednički. Sastojak koji već ima namirnicu ne dobija predlog.
- [ ] T028 [US4] U formi recepta za izvor ai/photo/url: „AI predlaže novu namirnicu: „…“.“, „Potvrdi“ (otvara popunjen `NewFoodForm`) / „Odbaci“; widget test (SC-005): lažni AI recept sa nepoznatim sastojkom → „Odbaci“ → broj redova `foods` isti, recept se čuva sa nepotvrđenim sastojkom; „Potvrdi“ → jedan sopstveni red sa `householdId` aktivnog domaćinstva.

---

## Phase 7: User Story 5 — Oznake alergena (P3)

- [x] T029 [P] [US5] `recipeAllergens(Recipe, FoodCatalog)` → `({Set<String> codes, bool complete})` u `lib/domain/food.dart`, testovi: jaje + pšenično brašno → {eggs, gluten}, complete; jedan nepotvrđen sastojak → complete false; sve potvrđeno bez oznaka → prazno, complete.
- [ ] T030 [US5] `AllergenLine` u `lib/features/foods/` i detalj recepta; widget testovi: „Sadrži: jaja, gluten“; „Podaci o alergenima nisu potpuni.“ kad complete false; nigde teksta „bez alergena“ (pretraga stabla widgeta).
- [ ] T031 [US5] Izbor oznaka iz `euAllergens` u `NewFoodForm` → `food_allergens` kroz `FoodRepository.createOwn`; test: izabrane oznake upisane, slobodan tekst nije moguć.

---

## Phase 8: Polish

- [ ] T032 [P] `docs/architecture.md`: kratak odeljak o katalogu (tabele, v2, referentni podaci); `lib/data/personal_export.dart` — izvoz sadrži sopstvene namirnice domaćinstva (sa aliasima, konverzijama i alergenima), bez zajedničkog kataloga (odluka G1); test u `test/data/personal_export_test.dart`.
- [ ] T033 `spec-converge` (kod vs spec) dok ne kaže „Converged“; ispravke kao zasebni commitovi.
- [ ] T034 `flutter test` ceo, `supabase db reset && supabase test db`, `flutter build macos --debug`; quickstart ručno na uskoj i širokoj širini.
- [ ] T035 PR opis: veza na spec, upozorenje o mešovitim verzijama klijenata (v2 snimak na starom klijentu), CSV na pregled timu, lista migracija.

---

## Dependencies & Execution Order

- T001 → T002 → T003 (pre svake izmene obračuna).
- T004, T005, T006 paralelno posle T003.
- T007 → T008 (server); T009 → T010 → T011; T012 posle T004 + T009.
- US1: T013 (← T004, T006) → T014 → T015 → T016 (← T010, T012) → T017 → T018 → T019.
- US2: T020 (← T012) → T021 ∥ → T022, T023.
- US3: T024 (← T005) → T025 (← T007) → T026 (← T008, T025). T026 može pre US2.
- US4: T027 (← T004) → T028 (← T021, T022).
- US5: T029 (← T004) → T030; T031 (← T021, T012).
- Polish posle svih priča.

## Parallel Example

```text
Posle T003:  T004 food.dart  ∥  T005 CSV parser  ∥  T006 Ingredient.foodId  ∥  T007 server migracija
Posle T012:  T021 widgeti  ∥  T024 generator  ∥  T029 alergeni (domen)
```

## Implementation Strategy

1. **MVP = Phase 1–3** (+ T024–T026 da katalog ima podatke): isti `food_id` se sabira kroz plan, Ostavu i nabavku; stari snimci isti.
2. Zatim US2 (bez UI-ja korisnik ne može da potvrdi nepoznato), US4, US5.
3. Ako diff (bez `.g.dart` i CSV-a) pređe ~1 500 linija: 036a = Phase 1–3 + US3, 036b = US2 + US4 + US5 (oba od najnovijeg `main`).
