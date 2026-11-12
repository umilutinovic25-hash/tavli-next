# Zadaci 039

- [x] T001 Domen `lib/domain/allergy.dart` + `test/domain/allergy_test.dart`: EU pogodak preko foodId i preko aliasa; slobodan unos preko kataloga i po celim rečima („sveže jagode“ da, „jagodasto“ ne); nepotvrđeno samo uz alergije; bez alergija prazno; unija članova; validacija (nepoznat kod, 31. stavka, predug unos).
- [ ] T002 Server migracija `member_allergies` + okidač brisanja pri napuštanju + prenos starih alergija; pgTAP `supabase/tests/*_member_allergies_test.sql` sa dva naloga (čitanje člana, zabrana tuđeg upisa, nečlan ne vidi, napuštanje briše, prenos updated_by/vlasnik i mapiranje kodova).
- [ ] T003 drift v18 `MemberAllergies` + migracioni test; `MemberAllergyEntity` u registru sinhronizacije.
- [ ] T004 `AllergyRepository` (watchMine, watchHousehold, current, saveMine kroz outbox) + test.
- [ ] T005 `RecipeAI`: provera, jedan ponovni zahtev, `AllergenViolation`; upit sa unijom. Testovi u `test/ai/recipe_ai_test.dart`.
- [ ] T006 `MealPlanAI`: filtriranje biblioteke, ponovni zahtev sažetaka, prazna mesta + greška. Testovi u `test/ai/meal_plan_ai_test.dart`.
- [ ] T007 Provideri + poruka greške (`AllergenViolation`) na ekranima po nazivu, razgovora i plana; widget test.
- [ ] T008 Ekran Preferencije: „Moje alergije“ (čipovi EU, Ostalo, unija); widget test na 400 i 1200 px.
- [ ] T009 `AllergenLine` i pregled pre čuvanja: „Sadrži alergen člana: …“, „Nepotvrđeno, proveri alergene“; widget testovi.
- [ ] T010 Lični izvoz format 4 sa `allergies`; politika privatnosti; `docs/architecture.md`.
- [ ] T011 `spec-converge` do „Converged“; `flutter test`, `supabase db reset && supabase test db`, `flutter analyze`; PR.
