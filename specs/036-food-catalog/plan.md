# Implementation Plan: Katalog namirnica (stalni id namirnice)

**Branch**: `036-food-catalog` (from latest `main`, dddbc8f) | **Date**: 2026-11-11 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/036-food-catalog/spec.md`

## Summary

Namirnica dobija stalni id u novim tabelama `foods`, `food_aliases`, `food_conversions`, `food_allergens` (+ referentna `allergens`). Sastojak recepta (`foodId` u JSON-u), Ostava i nabavka (`food_id` kolona) čuvaju id; tekst ostaje prikaz. Obračun se nadograđuje kao **rečnik v2** postojećeg mehanizma iz 018: identitet `food:<id>`, konverzija zamrznuta u snimku, raspodela zalihe dobija treći identitet nad istim `canonicalId`. Stari snimci (v0, v1) se ne diraju. Zajednički katalog dolazi iz pregledanog CSV-a kroz migraciju, preuzima se kroz postojeći sync (RLS ograničava redove), a mapiranje postojećih podataka radi serverska migracija. AI ne piše u katalog; predlog nove namirnice potvrđuje osoba.

## Technical Context

**Language/Version**: Dart ≥ 3.13, Flutter 3.47 (SDK `~/.cache/tavli-flutter-sdk`)

**Primary Dependencies**: postojeće — flutter_riverpod, drift, supabase_flutter, dio. **Nema novih zavisnosti** (CSV generator koristi samo `dart:io`; parser je ručno pisan i testiran).

**Storage**: Supabase Postgres (nove tabele + kolone, RLS), drift keš `schemaVersion` 16 → 17.

**Testing**: `flutter test` (domen TDD, repozitorijumi sa in-memory drift, widget testovi za izbor namirnice), `supabase test db` (pgTAP, dva naloga), golden test starih snimaka.

**Target Platform**: Android, iOS, macOS.

**Project Type**: mobile/desktop app + Supabase backend.

**Performance Goals**: `FoodCatalog.match` O(1) (mapa aliasa u memoriji); učitavanje kataloga (~1 500 redova) < 50 ms iz drift-a; prvo preuzimanje kataloga ≤ 3 strane od 500 redova.

**Constraints**: offline posle prvog preuzimanja; snimci zamrznuti; ništa se ne pogađa približno; bez promene AI prompta (037).

**Scale/Scope**: ~150–250 zajedničkih namirnica, ~1 000 aliasa; 3 forme (recept, Ostava, stavka nabavke) dobijaju izbor namirnice; detalj recepta dobija red alergena.

## Constitution Check

| Princip | Status |
|---|---|
| I. Srpski UI | ✅ Sav novi tekst u spec-u („New UI copy“). |
| II. Offline, nalog, RLS | ⚠️ → ✅ posle izmene: zajednički katalog je čitljiv svim `authenticated` (nije „vlasnik ili član“). **Izmena ustava 2.0.1 → 2.1.0** (R9) je prvi zadatak; RLS na svim novim tabelama, izričiti GRANT-ovi, `anon` bez prava, drift bump + migracija, upis kroz outbox. |
| III. AI samo kroz AIRouter | ✅ Bez novih AI poziva; prompt i `fromAiJson` nepromenjeni (037). |
| IV. Tajne | ✅ Nema. Seed ne čita produkciju. |
| V. Test-first | ✅ Domen (v2 ključ, konverzija, raspodela, matcher, draft, CSV parser) testovi prvi; pgTAP za RLS sa dva naloga; golden za stare snimke. |
| VI. Responsive | ✅ Izbor namirnice kao bottom sheet (uzak) / dijalog (širok), po postojećem obrascu formi. |
| VII. Mali commitovi | ✅ Redosled iz tasks.md; `.g.dart` uz izvor. |
| VIII. Jedna funkcija/spec/grana | ✅ 037, Worker, datumi i ostalo izvan opsega. |
| IX. Guardrails | ✅ Nove migracije kao novi fajlovi; `01_catalog_test.sql` ažuriran sa novim pravima. |

Ponovna provera posle dizajna: bez novih odstupanja.

## Project Structure

### Documentation

```text
specs/036-food-catalog/
├── spec.md
├── plan.md
├── research.md          # R1–R14
├── data-model.md
├── quickstart.md
├── contracts/catalog-csv.md
└── tasks.md             # /speckit-tasks
```

### Source Code

```text
.specify/memory/constitution.md          # 2.1.0 (R9)
supabase/
├── catalog/foods.csv                    # pregledan izvor zajedničkog kataloga
├── migrations/
│   ├── 20261112120000_food_catalog.sql        # tabele, RLS, grantovi, trigeri, allergens
│   ├── 20261112120100_food_ids.sql            # food_id kolone + trigger domaćinstva
│   ├── 20261112120200_food_catalog_seed.sql   # generisano iz CSV-a
│   └── 20261112120300_food_mapping.sql        # jednokratno mapiranje postojećih podataka
└── tests/15_food_catalog_test.sql (+ 01_catalog_test.sql prava)
scripts/catalog_seed.dart                # CSV → SQL
lib/domain/
├── food.dart                            # Food, FoodConversion, FoodCatalog, FoodDraft, euAllergens, CSV parser
├── recipe.dart                          # Ingredient.foodId
├── shopping_demand.dart                 # v2 ključ, konverzija
├── shopping_source.dart                 # snimak v2 + zamrznuta konverzija
└── supply_allocation.dart               # food identitet
lib/data/
├── database.dart (+ .g.dart)            # 4 tabele, food_id kolone, v17
├── food_repository.dart                 # keš kataloga, match, createOwn
├── recipe_repository.dart               # popuna foodId pri upisu
├── pantry_repository.dart               # popuna foodId, prenos pri prijemu
└── shopping_repository.dart             # popuna, v2 potvrda, Supply sa food identitetom, naziv stavke
lib/sync/entities.dart                   # 4 entiteta + food_id mapiranje
lib/features/foods/                      # FoodChip („Nepotvrđeno“), FoodPickerSheet, NewFoodForm, AllergenLine
lib/features/recipes/, pantry/, shopping/   # povezivanje widgeta u forme i detalj recepta
test/ (ogledalo lib/)
```

## Faze implementacije (redosled, svaka se proverava pre sledeće)

1. **Ustav 2.1.0** (zaseban commit).
2. **Domen, TDD** — `food.dart`; `Ingredient.foodId` (stari JSON bajt-isti); v2 ključ + konverzija; snimak v2; `Supply` food identitet. Golden test starih snimaka (SC-002) pre bilo koje izmene obračuna. SC-001 kao domenski test.
3. **Server** — migracija tabela + pgTAP (dva naloga: zajednički čitljiv, ne može se pisati; sopstveni nevidljiv drugom domaćinstvu; alias senka odbijena); `food_ids` kolone; generator + CSV + seed migracija; migracija mapiranja + pgTAP (SC-003: tekst nepromenjen, mapirano samo tačno).
4. **Drift + sync** — tabele, v17 migracija + test migracije; 4 entiteta; test da promena domaćinstva i `LegacyMover` ne diraju zajedničke redove.
5. **Repozitorijumi** — `FoodRepository`; popuna `foodId` u receptu/Ostavi/nabavci (samo kad je null); prijem prenosi `food_id`; potvrda plana i samostalne nabavke na v2; naziv stavke iz namirnice. Test toka SC-001 kroz repozitorijume.
6. **UI** — „Nepotvrđeno“ + izbor + „Nova namirnica“ u tri forme; AI predlog (R13); red alergena u detalju recepta. Widget testovi; provera uska/široka.
7. **Završno** — `spec-converge`, `flutter test`, `supabase test db`, `flutter build macos --debug`, quickstart ručno.

## Rizici

| Rizik | Ublažavanje |
|---|---|
| Mešovite verzije klijenata: stari klijent v2 snimak obračunava po tekstu | Isto kao 018: koordinisano ažuriranje pre objave; zapisano u PR-u. |
| Serverska migracija mapiranja preko `touch_updated_at` menja `updated_by` | Migracija radi kao `postgres` (auth.uid() null → zadržava stari `updated_by`, po `coalesce`). Provera u pgTAP. |
| Red sa lokalnom izmenom na čekanju ne dobija mapiranje | Prihvaćeno (Q3); auto-popuna pri sledećem upisu ga mapira. |
| Brisanje keša pri promeni domaćinstva obriše zajednički katalog | Test u fazi 4; ako se obriše, katalog se ponovo preuzima (cursor reset), ne gubi se ništa trajno. |
| Seed alias pogrešan (npr. „luk“ = crni ili beli?) | Dvosmislen tekst se **ne** stavlja kao alias; ostaje nepotvrđen. Pravilo u `contracts/catalog-csv.md` + PR pregled CSV-a. |
| Veličina zadatka | Jedna grana, commitovi po fazi. Ako PR pređe ~1 500 linija bez generisanog koda i CSV-a, delimo na 036a (domen + server + sync) i 036b (UI), oba od najnovijeg `main`. |

## Complexity Tracking

| Odstupanje | Zašto | Jednostavnija alternativa odbačena jer |
|---|---|---|
| Referentni podaci čitljivi svim `authenticated` (ustav II) | Zajednički katalog mora biti isti za sve domaćinstva i dostupan offline | Kopija kataloga po domaćinstvu: ×N redova, divergencija ispravki, isti problem jedinstvenosti aliasa |
