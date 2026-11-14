# Plan 039

**Grana** `039-allergy-guard` (od main 61849b9). Bez novih zavisnosti.

## Podaci
- Server `member_allergies`: `id text` = `household_id || ':' || user_id` (deterministički, dva uređaja iste osobe ne prave dva reda), `household_id uuid` → households (cascade), `user_id uuid default auth.uid()`, `codes jsonb` ⊂ 14 EU kodova, `custom jsonb` (`private.is_text_list(custom, 30, 40)`), `created_at/updated_at/updated_by`, okidači touch/record_deletion/skip_if_deleted (entitet `member_allergy`). RLS: select `is_member(household_id)`; insert/update/delete `is_member(household_id) and user_id = auth.uid()`. GRANT samo `authenticated`.
- Okidač na `household_members` after delete briše red tog člana (napuštanje, uklanjanje).
- Migracija podataka: za `household_preferences.allergies` ≠ []: osoba = `updated_by` ako je član, inače vlasnik; srpski EU nazivi (`jaja`, `kikiriki`, …) → kodovi, ostalo → `custom`; zatim `allergies = '[]'`. Kolona ostaje zbog starijih klijenata.
- drift 17 → 18: `PersonAllergies` (id, householdId, userId, codesJson, customJson); `SyncEntity` scope household.
- Ranija polja ostaju: `UserPreferences.allergies` se više ne uređuje u „Moje alergije“. Kasni zajednički upisi starijih klijenata i postojećeg outbox-a ulaze u uniju, AI uputstva, zaštitnu proveru i upozorenja. EU nazivi postaju kodovi kao u serverskom prenosu, ostalo je slobodan unos. Zajednički unos se ne pripisuje proizvoljnoj osobi; vidi se u „Važi za sve obroke“.

## Domen (`lib/domain/allergy.dart`)
`PersonAllergies` (validacija), `HouseholdAllergies.union`, `checkAllergens(ingredients, catalog, allergies) → AllergyCheck(hits, unconfirmed)`, `AllergyHit(ingredient, label)`, `AllergenViolation` (izuzetak sa srpskom porukom).

## AI
- `RecipeAI` i `MealPlanAI` dobijaju `Future<AllergyContext> Function()?` (katalog + unija). `fromDishName`/`refine`: provera → jedan ponovni `run` sa redom „must not contain“ → `AllergenViolation`. `fromImage` ne proverava (upozorenje u UI-ju).
- `MealPlanAI`: biblioteka se filtrira pre upita; sažeci: provera → ponovni zahtev za pogođene naslove → pogođena mesta se uklanjaju, `PlanGenerationFailed(draft, AllergenViolation)`.
- `preferencesBlock` dobija uniju umesto `prefs.allergies`.
- Ponovni zahtev nije `FormatException` (taj ponavlja isti upit i menja model).

## UI
`AllergenLine` (detalj) i pregled pre čuvanja pokazuju pogodak i „Nepotvrđeno“; ekran Preferencije: sekcija „Moje alergije“; poruka greške kroz postojeće mapiranje.

## Ustav
I srpski UI ✅ · II RLS, GRANT, pgTAP sa dva naloga, drift bump + test, outbox ✅ · III AI kroz AIRouter ✅ · IV bez tajni ✅ · V testovi prvi (domen, AI, pgTAP) ✅ · VI uska i široka širina (postojeći ekran) ✅

## Rizik
Mešovite verzije: stariji klijent i dalje piše `household_preferences.allergies` i ne vidi `member_allergies`. Jednokratna migracija se ne ponavlja; novi klijent zato prati obe tabele. Izolacija domaćinstva i lični izvoz ostaju kao ranije.
