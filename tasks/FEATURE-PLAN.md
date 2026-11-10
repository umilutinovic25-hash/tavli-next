# Tavli Next — detaljan plan svih 90 funkcija

Generisano iz pregledanih stream manifesta. Svi koraci, acceptance i provere su planirani, nisu potvrda implementacije. Izvorni dokazi i obrazloženje ostaju u research/streams i research/manifests. Zajedničke granice određuje docs/expansion/CONTRACTS.md.

## F001 — Uvoz recepta sa URL-a

**Vlasnik:** stream A. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/features/recipes/add_recipe_sheet.dart offers existing photo/name/manual inputs; lib/features/recipes/ai_preview.dart:AiRecipePreview already reviews before save. lib/domain/recipe.dart:RecipeSource has only photo/ai/manual; Recipe has no URL/author/extraction provenance. lib/data/recipe_repository.dart:RecipeRepository.create is transactional with outbox.

**Predložena izmena:**
ImportRequestV1(kind=url, input, clientRequestId) -> ImportDraftV1(recipe candidate, provenance, field evidence, warnings, completeness). Server fetch -> schema.org JSON-LD/microdata -> bounded text extraction -> opt-in AIRouter fallback -> existing preview -> RecipeRepository transaction. Keep author, original URL, final fetched URL and claimed canonical URL distinct; none authorizes another fetch.

**Zavisnosti:** G-SERVER, G-PROVENANCE, G-SYNC

**Male vertikalne celine:**
1. Add pure adapter and synthetic HTML fixtures for single Recipe and @graph, returning unsaved drafts.
2. Add isolated server fetch policy and authenticated endpoint; reject unavailable capability.
3. Connect existing add/preview/save flow, source metadata and outbox migration; add fallback only after structured import works.

**Kriterijumi prihvatanja:**
- [ ] Structured fixture imports with zero AI requests and zero recipe writes before confirmation.
- [ ] Multiple Recipe entities require explicit selection; absent quantities remain null with review flags.
- [ ] Discard produces zero recipe/outbox writes; retry with same accepted operation ID creates one recipe.
- [ ] All redirect/image/canonical-derived requests pass G-SERVER; private target makes zero outbound connections.

**Verifikacija pri implementaciji:**
- [ ] Unit fixtures: JSON-LD object/list/@graph, microdata, malformed JSON, HowToSection, ranges and unknown yields.
- [ ] Fake DNS/HTTP tests: public->private redirect, DNS rebinding, mapped IPv6, oversized/chunked/decompression body and timeout.
- [ ] Widget save/discard/retry and local two-account RLS/outbox tests after implementation.

**Detaljni dokazi:** [stream A](../research/streams/A.md).

## F002 — Potvrđeni sinonimi sastojaka i jedinica

**Vlasnik:** stream A. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/domain/shopping_sync.dart:ingredientKey normalizes spelling; lib/domain/shopping_demand.dart:normalizeUnit and demandFor separate mass/volume/count, without household synonym records. lib/domain/supply_allocation.dart:allocateSupply requires equal keys and unit groups.

**Predložena izmena:**
AliasV1(id, householdId, kind=ingredient|unit, normalizedAlias, canonicalId, confirmedBy, revision, retiredAt). Pure resolver used by search/demand/allocation; ingredients retain display spelling. Unit aliases map labels to an existing dimension and exact factor, never infer density. Suggestions require confirmation; changed aliases preview affected live demands and preserve approved historical snapshots.

**Zavisnosti:** G-SYNC

**Male vertikalne celine:**
1. Introduce immutable alias resolver with cycle/collision rejection and fixture tests.
2. Persist confirmed household aliases through repository/outbox and migration; expose review action.
3. Use one resolver in search/demand/allocation, rebuilding affected live projections transactionally with versioned snapshots.

**Kriterijumi prihvatanja:**
- [ ] beli luk/češnjak user-confirmed mapping resolves to one ingredient; unconfirmed suggestion changes nothing.
- [ ] 500 g plus 0.5 kg canonical demand equals 1,000,000,000 micros; g and ml remain separate.
- [ ] Cycles, ambiguous canonical mappings and cross-household aliases are rejected; retirement does not rewrite history.

**Verifikacija pri implementaciji:**
- [ ] Pure tests for Serbian Latin diacritics, whitespace, duplicate/cyclic aliases and dimension mismatch.
- [ ] Golden demand/allocation before/after alias migration; two-account isolation and outbox replay.

**Detaljni dokazi:** [stream A](../research/streams/A.md).

## F003 — Sačuvane kombinovane pretrage

**Vlasnik:** stream A. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/domain/recipe_format.dart:filterRecipes searches only normalized title substring; lib/features/recipes/recipe_providers.dart:RecipeSearch holds an ephemeral string; RecipeRepository.watchAll supplies current household recipes.

**Predložena izmena:**
RecipeQueryV1(text, includeIngredientIds, excludeIngredientIds, maxPrepMinutes, includeUnknownDuration=false, dietaryRuleSetId) plus SavedRecipeQuery(id, owner, name, queryJson, version). Extend current list/provider and pure query engine; persist user data via repository/outbox. Start with local scan, add drift index only when measured. Fuzzy title matches cannot satisfy hard ingredient exclusions.

**Zavisnosti:** F002, G-RULES, G-SYNC

**Male vertikalne celine:**
1. Implement typed predicates and query serialization over existing Recipe list.
2. Expose combined filters on existing list; preserve title-search behavior and animations.
3. Persist, rename and delete saved queries; later add migration-backed index from benchmark evidence.

**Kriterijumi prihvatanja:**
- [ ] AND query <=30 min + piletina + exclude kikiriki returns exactly fixture set.
- [ ] Unknown duration excluded for strict <=30 unless explicitly included; missing metadata shown.
- [ ] Saved query survives restart/offline/sync and never leaks between accounts.
- [ ] 1,000 recipes/20 ingredients predicate benchmark target p95 <200 ms on declared baseline device, recorded rather than presumed.

**Verifikacija pri implementaciji:**
- [ ] Truth-table tests for conjunction/exclusion, unknowns, Serbian spelling and deterministic ordering.
- [ ] Widget save/load/delete; replay serialization round trip; benchmark without network or AI.

**Detaljni dokazi:** [stream A](../research/streams/A.md).

## F004 — Mogu danas da skuvam

**Vlasnik:** stream A. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/domain/shopping_demand.dart:demandFor provides scaled micros and unknownGroup; lib/domain/supply_allocation.dart:allocateSupply deduplicates purchase/receipt physical stock. lib/data/pantry_repository.dart:receivePurchases persists receipts; no recipe feasibility ranking API exists.

**Predložena izmena:**
RecipeFeasibilityV1(recipeId, servings, status=covered|missing|needsReview, remainingLines, allocations, snapshotRevision). Build from existing demandFor/allocateSupply on confirmed usable pantry supplies, considering current reservations. Standalone candidate evaluation uses a fresh copy of the same stock, while accepted multi-slot plans share one allocation ledger. Quantity-free or uncertain lines never imply numerical coverage.

**Zavisnosti:** F002, G-PANTRY, G-RULES

**Male vertikalne celine:**
1. Add pure feasibility façade over existing quantity functions.
2. Read confirmed stock/reservations through pantry data layer and show covered/missing/review groups.
3. Connect serving changes and approval refresh against current stock revision.

**Kriterijumi prihvatanja:**
- [ ] Recipe requiring 400 g with 250 g confirmed stock shows exactly 150 g missing.
- [ ] Unknown stock or recipe quantity yields needsReview, never covered.
- [ ] One purchase and its pantry receipt count once; two 200 g meals cannot both claim the same 250 g in a joint plan.
- [ ] Missing 1–2 counts distinct demand groups and lists incompatible units separately.

**Verifikacija pri implementaciji:**
- [ ] Hand-calculated 400-250=150 g fixture, serving scaling, reservations and receipt canonicalId tests.
- [ ] Regression existing demand/allocation tests plus offline recipe list/widget update on pantry edits.

**Detaljni dokazi:** [stream A](../research/streams/A.md).

## F005 — Potroši prvo

**Vlasnik:** stream A. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart:PantryItems.expiresAt/confirmedAt exist. Supply in lib/domain/supply_allocation.dart has no expiration metadata and allocates by supply ID; no expiry-aware ranking is present.

**Predložena izmena:**
ExpiryEvidence(supplyCanonicalId, confirmedExpiresOn, dateKind, confirmationRevision). Rank candidates by actually allocatable known quantity from eligible soon-expiring lots, through an adapter around existing allocation. Do not change generic allocator ordering silently: introduce explicit lot preference policy after agreement with stream C. Date-only CivilDate and injected today; past date is review/exclude policy, never a safety judgment.

**Zavisnosti:** F004, G-PANTRY

**Male vertikalne celine:**
1. Add pure expiring-lot ranking with fixed today and date-kind handling.
2. Expose window and confirmed dates on existing pantry-backed suggestions.
3. Add versioned policy to plan candidate scoring and explanation evidence.

**Kriterijumi prihvatanja:**
- [ ] Only confirmed expiry within chosen 3-day window contributes; unknown and expired dates do not earn a bonus.
- [ ] Bonus capped by quantity actually consumed by candidate; duplicated receipt earns no extra credit.
- [ ] Identical input and today produce identical order; reasons show the actual item/date.

**Verifikacija pri implementaciji:**
- [ ] Fixed-clock tests across month/year boundaries and Europe/Belgrade DST dates.
- [ ] Competing-lot fixture proving 50 g consumed from 100 g soon-expiring stock earns 50 g evidence, not 100 g.
- [ ] Widget unknown-date/expired-review and stock-revision refresh tests.

**Detaljni dokazi:** [stream A](../research/streams/A.md).

## F006 — Minimalna zaliha

**Vlasnik:** stream C. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. No threshold or replenish policy; lib/app/router.dart /pantry is EmptyStateScreen.

**Predložena izmena:**
[
  "Add household ReplenishmentPolicy(id, ingredientKey, unitGroup, minimumMicros, targetMicros, active); require target >= minimum >= 0.",
  "Build a read-only replenish proposal using canonical confirmed usable stock, unresolved reservations, bought-not-received supply and compatible open shopping coverage. Desired total demand = max(existing recipe demand, target stock gap) under a stated policy, never blindly add recipe demand plus gap. Explicit approval creates a stable replenish source, reused on retry; no automatic purchase."
]

**Zavisnosti:** G010, GQ, GTX, F039

**Male vertikalne celine:**
1. Read-only minimum/target editor and preview with deterministic domain tests.
2. Approve into current ShoppingRepository contribution/source model; sync policy and source with RLS.
3. Add pantry low-stock filter and user-controlled reminders only after proposal behavior is stable.

**Kriterijumi prihvatanja:**
- [ ] Stock 200 g, minimum 300 g, target 1000 g produces 800 g proposal; compatible unbought coverage 500 g leaves 300 g additional.
- [ ] Equality with minimum creates no prompt; unknown stock asks for review; repeated approval creates one source and preserves bought items.

**Verifikacija pri implementaciji:**
- [ ] Domain fixtures for threshold equality, two equivalent units, unknown quantity, expired lot, shared purchase/receipt identity and existing shopping.
- [ ] Repository fake-backend test: approve twice, receive once, reconcile twice; no duplicate source or capacity.

**Detaljni dokazi:** [stream C](../research/streams/C.md).

## F007 — Šabloni nedelje

**Vlasnik:** stream B. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/domain/meal_plan.dart: MealPlan/PlanDraft imaju apsolutne datume, snimke i PlanBase; lib/data/meal_plan_repository.dart: approve kreira nove izvore kroz reconcilePlan. Nema modela šablona.

**Predložena izmena:**
PlanTemplate{id,householdId,name,schemaVersion,days[dayOffset,mealType,entryKind,snapshot,recipeId,servings,preparationKey]}; sačuvati sadržaj, bez kupljenih stavki, cooked/locked statusa i rezervacija. applyTemplate(anchor,portionOverrides,targetBase) vraća PlanDraft; relativne veze priprema premapirati u nove UUID. Ne kopirati postojeće izvore potražnje.

**Zavisnosti:** G-SYNC, G-PLAN-REV

**Male vertikalne celine:**
1. Sačuvaj sedam relativnih dana iz postojećeg plana i prikaži sadržaj šablona offline.
2. Primeni na novi datum uz pregled praznih mesta, novih porcija i nove identitete.
3. Primeni na postojeći plan uz diff i zaštitu zaključanih/skuvanih/prošlih obroka; odobri kroz postojeći repository.

**Kriterijumi prihvatanja:**
- [ ] Primena 2 puta daje 2 nezavisna plana i izvore; promena jednog ne menja šablon/drugi plan.
- [ ] Od 28.12.2026. sedmi dan je 03.01.2027; stari isCooked se ne prenosi.
- [ ] Pregled i odbacivanje ne menjaju recepte, nabavku ili outbox; obrisani izvorni recept ostaje upotrebljiv preko snimka.

**Verifikacija pri implementaciji:**
- [ ] Domain: relativni datumi preko godine i prestupnog dana; povezane pripreme imaju nove, konzistentne ID-jeve.
- [ ] Repository: broj upisa/outbox-a pre i posle odbačenog pregleda, dupli submit operationId, stari fingerprint.
- [ ] Widget: primena na telefonu/rail-u i tekst 2×; regresija test/data/meal_plan_repository_test.dart.

**Detaljni dokazi:** [stream B](../research/streams/B.md).

## F008 — Režim kuvanja

**Vlasnik:** stream E. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/features/recipes/recipe_view.dart: RecipeView.build samo ispisuje sastojke i numerisane string korake. lib/features/recipes/recipe_detail_screen.dart: RecipeDetailScreen koristi KeepScreenOnScope; lib/features/recipes/keep_screen_on.dart: KeepScreenOn čuva izbor u AppSettings. lib/features/planning/meal_entry_detail.dart: MealEntryDetail prikazuje odobreni snapshot; nema cooking session modela u lib/data/database.dart.

**Predložena izmena:**
[
  "CookingSession {id,userId,householdId,recipeId?,mealEntryId?,recipeSnapshot,servings,status,currentStepId,checkedIngredientIds,completedStepIds,startedAt,finishedAt?}; snapshot je nepromenljiv tokom sesije. Sesija je lična; referencirani recept ostaje kućni.",
  "Novi cooking controller koristi postojeće RecipeView/formatere, route i ScreenWakeLock interfejs; dugmad Dalje, Nazad, Završi kuvanje; završetak eksplicitno nudi setCooked, čekiranje ništa ne troši iz ostave."
]

**Zavisnosti:** G-SYNC, G-STEP, G-LIFECYCLE

**Male vertikalne celine:**
1. Legacy snapshot adapter i state machine sa testovima; jedna sesija iz recepta bez upisa u plan.
2. Persistirana lična sesija sa checklistom i nastavkom offline; ekran telefon/rail.
3. Ulaz iz MealEntryDetail i eksplicitni završetak kroz postojeći MealPlanRepository.setCooked; lifecycle i wakelock regresija.

**Kriterijumi prihvatanja:**
- [ ] Čekiranje koraka/sastojka ne menja Recipe, PantryItems ni ShoppingContributions.
- [ ] Izmena biblioteke tokom kuvanja ne menja snapshot sesije; ponovni start daje novu sesiju.
- [ ] Izlazak/odjava oslobađaju wake lock; povratak ga traži samo ako je izbor uključen i cooking ekran vidljiv.

**Verifikacija pri implementaciji:**
- [ ] Widget test 390x844 i 1280x800: čekiraj, izađi, nastavi; uporedi recept i ostavu pre/posle.
- [ ] Fake repository: dvostruki tap Završi pravi jedan završetak; plan nije skuvan pre potvrde.
- [ ] Proširiti test/features/recipes/keep_screen_on_test.dart; uređaj: background/resume, OS odbijanje lock-a, navigacija i reduced motion.

**Detaljni dokazi:** [stream E](../research/streams/E.md).

## F009 — Više imenovanih tajmera

**Vlasnik:** stream E. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/app/animations/egg_timer.dart: EggTimer je vizuelna komponenta; demo odbrojavanje je u lib/features/settings/animations_gallery_screen.dart. Nema domena ni persistiranih kuhinjskih tajmera u lib/data/database.dart. lib/app/app.dart: _onResume obnavlja auth i sync, ne tajmere.

**Predložena izmena:**
[
  "CookingTimer {id,sessionId,stepId?,label,durationMs,remainingAtCheckpointMs,state,generation,ownerDeviceId}; operacije start/pause/resume/cancel/acknowledge su idempotentne i po ID-u.",
  "TimerClock vraća continuous monotonic elapsed + boot identity; TimerNotificationAdapter raspoređuje lokalni alarm sa timerId/generation. UTC checkpoint služi oporavku i prikazu, ne odbrojavanju u istoj boot sesiji."
]

**Zavisnosti:** F008, G-LIFECYCLE, G-SYNC

**Male vertikalne celine:**
1. Dva nezavisna foreground tajmera i fake monotonic clock.
2. Checkpoint, pauza, nastavak posle process death u istoj boot sesiji; OS alarm adapter i provera dozvola.
3. Boot/clock-discontinuity stanje i prikaz ograničenja; real device zaključavanje, Doze, force stop i reboot matrica.

**Kriterijumi prihvatanja:**
- [ ] Za A=60 s i B=90 s, posle 20 s A=40/B=70; otkazivanje A ostavlja B=70.
- [ ] Promena zidnog sata +2 h u istoj boot sesiji ne menja preostalo vreme.
- [ ] Ponovljen resume i zakašnjeli callback stare generation ne emituju dupli alarm; nijedan UI tick nije izvor istine.
- [ ] Bez dozvole prikazati Obaveštenja nisu dostupna; nakon reboot-a bez pouzdanog kontinualnog vremena prikazati Proveri tajmer umesto izmišljene tačnosti.

**Verifikacija pri implementaciji:**
- [ ] Domain test sa fake continuous clock: sleep +30 s, wall jump, pause/resume, istovremeni rokovi, negativno vreme clamp na nulu.
- [ ] Device test Android/iOS: lock, background, kill, force stop, reboot, ugašene notifikacije; izmeriti odstupanje i zabeležiti model/OS.
- [ ] Dva naloga/uređaja: sync checkpoint ne zakazuje drugi lokalni alarm; odjava uklanja pending zahteve.

**Detaljni dokazi:** [stream E](../research/streams/E.md).

## F010 — Fotografija, brend i napomena uz nabavku

**Vlasnik:** stream D. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::ShoppingItems ima name/quantity/unit/category/isBought/isManual i purchaseProvenanceJson, bez fotografije, brenda i korisničke napomene. ShoppingContributions.notesJson čuva napomene sastojaka, nije isto što i kupčeva napomena. lib/data/shopping_repository.dart::_reconcile spaja potrebe; lib/features/shopping/shopping_list_view.dart::ShoppingItemTile prikazuje postojeću stavku. lib/sync/photo_sync.dart::PhotoSync je obrazac za slike recepata, ne gotova podrška za slike artikala.

**Predložena izmena:**
[
  "Dodati ShoppingItemDetails(itemId, householdId, brand?, shopperNote?, photoAssetId?, revision); polja u zasebnom zavisnom redu čuvaju nezavisne revizije od isBought i reconciliation količine.",
  "Asset ima UUID, relativnu lokalnu putanju, privatni objectKey household/item/asset, mime, size i uploadState. Bez javnog URL-a; brisanje i retry prate isti outbox. Snapshot detalja ide u potvrđenu kupovinu; pri nestanku automatske stavke unapred definisati obrisati detalje ili prikazati predlog za novu stavku, bez tihog prenošenja na drugi proizvod."
]

**Zavisnosti:** G-SYNC, G-SCHEMA, G-ASSETS

**Male vertikalne celine:**
1. Tekstualna napomena i brend offline kroz postojeći repository/writer.
2. Privatna slika, ograničenje veličine i retry bez dupliranja.
3. Prikaz detalja pri kupovini i snapshot istorije.

**Kriterijumi prihvatanja:**
- [ ] Izmena napomene ne menja quantity, isBought ili potražnju iz recepta.
- [ ] Slika radi offline posle preuzimanja; drugi član istog domaćinstva je vidi, drugi nalog van domaćinstva dobija zabranu.
- [ ] Brisanje slike i ponovljeno slanje ne ostavljaju vidljiv duplikat.

**Verifikacija pri implementaciji:**
- [ ] Dopuniti test/data/shopping_repository_test.dart: promena plana, spajanje iste namirnice i kupovina zadržavaju predviđene detalje.
- [ ] Faked PhotoRemote: prekid posle upload-a, retry istog asset UUID-a; lokalni pgTAP sa dva domaćinstva za Storage/RLS.
- [ ] Widget: telefon i širok ekran, tekst „Napomena za kupovinu”, „Brend”, „Slika proizvoda”.

**Detaljni dokazi:** [stream D](../research/streams/D.md).

## F011 — Zajednička lista, članstvo i brze izmene

**Vlasnik:** stream D. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/domain/account.dart::Account nosi jednu householdId i role; lib/account/account_api.dart::SupabaseAccountApi.fetch koristi limit(1). supabase/migrations/20261030120100_accounts.sql::household_members dozvoljava samo owner. lib/sync/uploader.dart::_send šalje ceo red upsert-om; lib/sync/downloader.dart::_hasLocalChange preskače remote red dok postoji lokalni outbox, a _applyTombstone briše lokalnu promenu. lib/sync/sync_engine.dart::onStart/onResume su pull okidači, bez realtime pretplate.

**Predložena izmena:**
[
  "Membership(householdId,userId,role owner|admin|member|viewer,status,revision). Owner prenosi vlasništvo i briše domaćinstvo; owner/admin upravljaju običnim članovima i pozivnicama; member menja zajedničku nabavku i svoje glasove; viewer samo čita. Niko ne može sebi podići ulogu. Poslednji owner ne može otići bez transfera ili brisanja solo domaćinstva.",
  "Invitation(id,householdId,hashedToken,expiresAt,revokedAt,maxUses=1); server proverava auth i uslove pri prihvatanju u jednoj transakciji. Raw token nije u logu ni običnom kešu.",
  "Operacije sa operationId, actor, boundHouseholdId, expectedRevision i patch ostaju u postojećem outbox-u sa opcionim payload-om; server RPC atomarno proverava članstvo, reviziju, idempotency i tombstone. Realtime je invalidacija sa naknadnim pull-om, ne izvor istine. Detaljan conflict ugovor je ispod."
]

**Zavisnosti:** G-SCHEMA, G-SYNC

**Male vertikalne celine:**
1. Pozivnica, role RLS i prikaz članstva, bez realtime-a.
2. Server revizije i idempotentne komande u postojećem outbox-u, zatim lokalni conflict UI.
3. Realtime invalidacija, reconnect pull i prikaz pending/rejected/conflict.

**Kriterijumi prihvatanja:**
- [ ] Dva člana u kontrolisanom lokalnom testu vide potvrđenu promenu za najviše 2 s pri dostupnom realtime transportu; prekid prelazi na pull bez gubitka.
- [ ] Dve operacije nad istom revizijom ne mogu obe uspeti; različita nezavisna polja ne prepisuju jedno drugo.
- [ ] Viewer ne piše ni direktnim REST/RPC pozivom; opozvana pozivnica i uklonjeni član ne mogu slati nove operacije.
- [ ] Offline izmena je odmah vidljiva lokalno, uz „Čeka slanje”; konflikt ne pokazuje lažno „Sačuvano”.

**Verifikacija pri implementaciji:**
- [ ] Local Supabase pgTAP: owner/admin/member/viewer plus outsider, self escalation, replay invite, expiry tačno na granici, paralelno prihvatanje, last-owner transfer.
- [ ] Dve fake replike: kupi/poništi, napomena/kupi, obriši/izmeni, duplirani event i operationId, offline 24 h, reconnect i izmenjen sat.
- [ ] Regression: test/sync/downloader_test.dart, uploader_test.dart i test/data/shopping_repository_test.dart; provera reconciliation veza i prijema u ostavu.

**Detaljni dokazi:** [stream D](../research/streams/D.md).

## F012 — Povezani ostaci

**Vlasnik:** stream B. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/domain/meal_plan.dart: PlannedMeal ima servings i isCooked, bez pojma pojedeno; lib/data/shopping_repository.dart: reconcilePlan stvara izvor za svaki unos sa snapshot-om, _demand skalira njegove porcije. Kopiran recept sutradan danas duplira potražnju.

**Predložena izmena:**
Preparation{id,householdId,planId,cookSlot,snapshot,plannedYield,actualYield?,status}; MealConsumption{id,entryId,preparationId,reservedServings,eatenServings?,status}. Unos ima kind=cook|leftover|away. Potražnja sirovina pripada preparationId i cookSlot-u jednom; servings za jedenje nisu yield pripreme. Rezervacije ukupno <= raspoloživ prinos; status planned/cooked/discarded i reserved/eaten/released su odvojeni. F075 može dodati merenu masu, ali nije uslov za ručne porcije.

**Zavisnosti:** G-SYNC, G-PLAN-REV, G-DEMAND

**Male vertikalne celine:**
1. Migriraj svaki legacy recipe unos u jednu pripremu i jednu konzumaciju, bez promene ukupne potražnje.
2. U pregledu povećaj prinos i poveži budući obrok sa ostatkom; prikaži račun porcija i jednu nabavku.
3. Potvrdi skuvano i zatim pojedeno odvojeno; premeštanje/brisanje/undo proverava sve zavisne obroke.

**Kriterijumi prihvatanja:**
- [ ] Priprema 6 porcija sa 600 g pasulja: 4 večeras + 2 sutra = 600 g potrebe, nikada 800 g ili 1.2 kg.
- [ ] Promena sutrašnje rezervacije sa 2 na 3 bez većeg prinosa je odbijena; promena planiranog prinosa na 7 pre kuvanja daje 700 g.
- [ ] Skuvano zatvara sirovinsku nabavku jednom i zadržava postojeće rezervacije zalihe; pojedeno ne pravi novo skidanje sirovina.
- [ ] Brisanje pripreme sa vezanim ostacima zahteva eksplicitno razvezivanje/zamenu u pregledu; drugi household ne može rezervisati prinos.

**Verifikacija pri implementaciji:**
- [ ] Domain: 6=4+2, 5<4+2 invalidno, ciklus/veza na kasniju pripremu/negativan prinos zabranjeni.
- [ ] Repository: ponovljena cooked/eaten potvrda je idempotentna; cooked->uncooked uz već eaten zavisnike odbijen; cross-week ostatak ne stvara izvor u drugoj nedelji.
- [ ] Sync/RLS: dva uređaja istovremeno rezervišu poslednje 2 porcije; server prihvata najviše jednu komandu.
- [ ] Regresija supply allocations i purchaseProvenanceJson, ručna i kupljena stavka ostaju posle uklanjanja veze.

**Detaljni dokazi:** [stream B](../research/streams/B.md).

## F013 — Zamrznuti gotovi obroci

**Vlasnik:** stream C. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. lib/data/meal_plan_repository.dart::setCooked only changes cooked state; MealPlanEntries has recipeSnapshotJson but no cooked-batch inventory.

**Predložena izmena:**
[
  "Use cooked PantryItems with supplyKind=cooked and CookedBatch metadata (batchId, recipeSnapshot, preparedAt, frozenAt, confirmed portions or mass, thawReminderAt). Do not match cooked food to raw ingredients by name.",
  "Meal entry can draw portions from one batch using CookedBatchAllocation; reserving/reheating never generates raw demand again. Cooking consumes ingredients only after explicit confirmation; recording batch output uses the same operation id."
]

**Zavisnosti:** G010, GTX, F012, F038

**Male vertikalne celine:**
1. Manual cooked-batch creation and listing linked to PantryItems; no automatic ingredient decrement.
2. Link batch reservations to plan and remove duplicate raw demand in explicit batch mode.
3. Add optional local thaw reminder capability gate and snapshot-preserving sync.

**Kriterijumi prihvatanja:**
- [ ] Cook six portions once, freeze four, reserve two on each of two future meals: cooked available=0 and raw demand occurs once.
- [ ] Declining notifications or offline operation still allows manual frozenAt/thaw preparation; recipe deletion preserves batch snapshot.

**Verifikacija pri implementaciji:**
- [ ] Domain batch conservation fixtures; repository test cooking retry and reserve/cancel/reheat.
- [ ] Widget test list frozen batches, edit portions, select meal; fake clock notification deny/unavailable test.

**Detaljni dokazi:** [stream C](../research/streams/C.md).

## F014 — Grupe jela koje troše pakovanja

**Vlasnik:** stream B. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/ai/meal_plan_ai.dart: MealPlanAI.propose ima pantryNames i raspored po nedeljama, bez podataka o veličini pakovanja; lib/domain/shopping_demand.dart računa normalizovane potrebe.

**Predložena izmena:**
PackageOption{ingredientKey,unitGroup,sizeMicros,source,observedAt}; BundleProposal{3..5 draft meals,packageChoices,demandTotals,residuals,coverage}. Rangiranje deterministički računa ceil(uncovered/size)*size-uncovered po uporedivoj jedinici. Ostatak pakovanja nije kvarenje niti novac. AI može predložiti grupu, kod proverava količine i uslove.

**Zavisnosti:** G-DEMAND, G-PACKAGE-CATALOG

**Male vertikalne celine:**
1. Ručno potvrđene veličine pakovanja i tačan obračun ostatka za jednu namirnicu.
2. Pregled grupe 3–5 jela uz pokrivenost podacima i postojeću zalihu raspoređenu jednom.
3. Odobri grupu kao PlanDraft, uz zamenu jela i ponovno računanje.

**Kriterijumi prihvatanja:**
- [ ] Tri jela traže 200+150+100 g; pakovanje 500 g bez zalihe daje 1 pakovanje i 50 g ostatka.
- [ ] Sa 100 g potvrđene zalihe kupuje se 500 g za 350 g nepokrivene potrebe, ostatak 150 g; zaliha se ne oduzima po jelu.
- [ ] Nepoznata veličina/jedinica je Nepoznato, ne nula; nema tvrdnje o uštedi bez uporedivih cena.

**Verifikacija pri implementaciji:**
- [ ] Domain unapred izračunati primeri 450/500, 550/500=>2 pakovanja, mešane neuporedive jedinice.
- [ ] Repository preview bez upisa i approve jednom; postojeće kupljeno ne nestaje.
- [ ] Widget zamena jednog jela menja zbir/ostatak i prikazuje izvor veličine.

**Detaljni dokazi:** [stream B](../research/streams/B.md).

## F015 — Podsetnici za pripremu

**Vlasnik:** stream B. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/domain/shopping_source.dart: RecipeSnapshot ima tekstualne steps i prepMinutes; lib/domain/plan_calendar.dart: CivilDate nema vreme/zonu. U pregledanim planning modelima nema pripremnih obaveza.

**Predložena izmena:**
PrepObligation{id,preparationId,label,offsetMinutes,anchorKind,cookLocalTime,zoneId,enabled,revision}; NotificationGateway.capabilities/probe/schedule/cancel. Ručno uneta obaveza prvo; AI predlog mora da se potvrdi. Obaveze nisu tajmeri kuvanja F009. Trajno čuvati nameru, a raspored lokalnih notifikacija ponovo izvesti pri promeni plana/zone/dozvole.

**Zavisnosti:** G-SYNC, G-TIME, F012

**Male vertikalne celine:**
1. Ručno dodaj obavezu uz datum, sat i zonu u detalju pripreme.
2. Probe dozvole/platforme i lokalno zakazivanje sa stabilnim ID-jem.
3. Reconcile promena, brisanja, undo-a i ponovnog pokretanja; predlozi iz recepta uz pregled.

**Kriterijumi prihvatanja:**
- [ ] Kuvanje 10.11.2026. u 18:00 Europe/Belgrade i offset 12 h daju podsetnik u 06:00.
- [ ] Pomeri kuvanje za 1 h: tačno jedan novi aktivan podsetnik, stari otkazan; retry ne duplira.
- [ ] Odbijena dozvola prikazuje Podsetnici nisu dostupni i obavezu u aplikaciji; nema obećanja tačnog vremena isporuke.

**Verifikacija pri implementaciji:**
- [ ] Fake clock/gateway: denied, unsupported, reboot, stale revision, prošli rok.
- [ ] Zone testovi nonexistent/ambiguous sat pri DST: eksplicitni izbor bez tihog pomeranja CivilDate.
- [ ] Widget promena/suppress/cancel i gašenje na odjavi; OS smoke provera tek u implementaciji.

**Detaljni dokazi:** [stream B](../research/streams/B.md).

## F016 — Glasovni unos nabavke na srpskom

**Vlasnik:** stream E. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/features/shopping/shopping_list_view.dart je postojeći UI nabavke; lib/data/shopping_repository.dart: ShoppingRepository.addManual(listId,name,quantity,unit,category) već piše stavku i outbox atomarno. pubspec.yaml nema speech adapter.

**Predložena izmena:**
[
  "SpeechInput.probe(locale) -> SpeechCapability {requestedLocale,resolvedLocale,recognitionAvailable,onDeviceAvailable,permission,reason}; transcribe vraća transcript/final bez čuvanja audio snimka.",
  "ShoppingVoiceDraft {transcript,name,quantity?,unit?,unresolvedTokens}; deterministički parser srpskih brojeva/jedinica, pregled i izmena pre jednog poziva addManual. Nejasno ne pretvarati u potvrđenu količinu.",
  "F002 je opciona normalizacija potvrđenih sinonima; osnovni voice draft ne čeka taj rečnik."
]

**Zavisnosti:** G-SPEECH, G-SYNC

**Male vertikalne celine:**
1. Parser tekstualnog transkripta i draft pregled koriste isti addManual kao kucanje.
2. Android capability + mikrofon + push-to-talk; fallback na tekst.
3. iOS/macOS probe i stvarni srpski corpus; objaviti samo platforme/locale kombinacije koje prođu.

**Kriterijumi prihvatanja:**
- [ ] Dodaj dva litra mleka daje draft mleko,2,l; bez Potvrdi nema reda/outbox-a.
- [ ] Isti final callback dva puta + jedan tap potvrde daju jednu stavku; partial rezultat ne upisuje.
- [ ] Odbijena dozvola/nepodržan srpski/offline bez lokalnog modela ostavljaju kucanje upotrebljivim i pokazuju razlog.

**Verifikacija pri implementaciji:**
- [ ] Parser fixtures: dva litra, 1,5 kg, pola kilograma, bez količine i dvosmislene reči; porediti sa unapred navedenim draftom.
- [ ] Fake speech stream partial/final/error/cancel + repository call count.
- [ ] Fizički uređaji sr-RS/sr-Latn-RS kako ih platforma vrati, airplane mode i odbijene dozvole; ne pretpostaviti srpsku podršku.

**Detaljni dokazi:** [stream E](../research/streams/E.md).

## F017 — Barkod i pakovanje

**Vlasnik:** stream C. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. No barcode/catalog adapter observed; camera/AI recipe import is not a product scanner.

**Predložena izmena:**
[
  "Introduce ProductLookup.lookupBarcode(code) -> found/notFound/unavailable/invalid with CatalogProduct(source, sourceId, barcode, names, brand, quantityText, parsedPackage?, fetchedAt). Cache external responses separately from pantry.",
  "OpenFoodFactsAdapter selects name/quantity/product_quantity fields, identifies app User-Agent, times out and respects rate limits; supported Serbian language/country tags do not guarantee coverage. User confirms ingredient identity and package amount before supply creation; allow manual entry without camera or network."
]

**Zavisnosti:** GADAPTER, GQ, F039

**Male vertikalne celine:**
1. Pure barcode/result/parser contract and manual input, with tests.
2. Read-only OFF adapter/cache and preview; record attribution/data-license boundary.
3. Optional device scanner capability and explicit confirmed product-to-ingredient mapping.

**Kriterijumi prihvatanja:**
- [ ] A found 500 g package shows editable proposal without pantry write until confirmation; 404, 429, malformed quantity and offline cache miss all retain manual flow.
- [ ] Barcode leading zeros survive; volume and mass cannot be interchanged; country rs filter is not a local-stock claim.

**Verifikacija pri implementaciji:**
- [ ] Fake Dio fixtures for found/missing/429/timeout, multipack 6x125 g and unparsed labels; no live network tests.
- [ ] Camera capability/permission-denied widget tests on phone and desktop; duplicate scan event creates no duplicate receipt.
- [ ] Future Serbia pilot: user-consented basket of at least 30 local products; report found/30, correct package/found, missing translation and observed date; no coverage claim until measured.

**Detaljni dokazi:** [stream C](../research/streams/C.md).

## F018 — Cene, prodavnica, datum i dokaz

**Vlasnik:** stream D. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::ShoppingItems nema cenu, valutu, proizvod ili poslovnicu; lib/domain/shopping_demand.dart::normalizeUnit poznaje uporedive jedinice hrane, ne pakovanja proizvoda. lib/data/shopping_repository.dart::setBought/_buy zamrzava poreklo nabavke, ne novčani iznos. Postojeći supabase/migrations/20261030120200_household_data.sql nema price tabelu.

**Predložena izmena:**
[
  "ProductRef(id,barcode?,name,brand?,packageQuantityMicros?,unitGroup,source,sourceId) je odvojen od ingredientKey; potvrđen IngredientProductMapping nije automatski jednak barkodu.",
  "PriceObservation(id,householdId,productRefId,storeBranchId,observedOn,recordedAt,currency,rawDecimal,scale,priceBasis package|kg|l|unit,proofAssetId?,source,sourceRecordId?,promotionId?,qualityFlags). Exact decimal/rational quote čuva se bez float-a; Money nastaje tek po izračunatoj stavci i pravilu zaokruživanja.",
  "PriceProvider.capabilities i import javno dozvoljenih fixture podataka; ručni unos radi bez provajdera. Pokrivenost = broj stavki sa uporedivom dovoljno svežom cenom / broj traženih stavki, uz nepoznate količine odvojeno. Nijedan API nije pozvan; pokrivenost Srbije ostaje nepoznata."
]

**Zavisnosti:** G-MONEY, G-SCHEMA

**Male vertikalne celine:**
1. Ručna cena, poslovnica i datum sa privatnim dokazom.
2. Istorija i poređenje iste jedinice/pakovanja, prikaz zastarelosti i pokrivenosti.
3. Provider adapter tek posle provere uslova podataka i relevantnosti Srbije na odobrenim offline uzorcima.

**Kriterijumi prihvatanja:**
- [ ] Dve cene za 500 g i 1 kg porede se po kg; nepoznata masa ne daje lažnu najnižu cenu.
- [ ] Iznos 1.235 iz izvora sa tri decimale zadržava se tačno; total se zaokružuje samo jednom po definisanom obračunu.
- [ ] Od 10 redova sa 6 uporedivih svežih cena prikaz je 6/10 uz 4 nepoznate, bez izmišljene ukupne uštede.
- [ ] Dokaz računa ostaje privatan dok korisnik posebno ne odluči o eventualnom javnom doprinosu.

**Verifikacija pri implementaciji:**
- [ ] Offline fixture parser za decimalni string, null datum, nedostajući proof, 3-decimalnu cenu i valutu koja nije RSD.
- [ ] Ručni proračun: 500 g za 15000 minor = 30000 minor/kg; 1 kg za 28000 je jeftiniji za 2000 minor/kg.
- [ ] Repository/migration roundtrip, local RLS isolation, fake provider denied/rate-limited/unconfigured bez mreže.

**Detaljni dokazi:** [stream D](../research/streams/D.md).

## F019 — PDF i nalepljeni tekst

**Vlasnik:** stream A. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/ai/recipe_ai.dart:RecipeAI supports fromImage/fromDishName/refine; lib/features/recipes/from_photo_screen.dart and AiRecipePreview provide image draft flow. No PDF/text import endpoint or source-document model exists.

**Predložena izmena:**
Reuse ImportDraftV1 with kind=text|pdf, immutable source digest, page/character spans and extraction mode=text|ocr|ai. Proposed limits: 10 MiB PDF, 10 selected pages, 100k extracted characters; enforce byte/magic/type limits and sandbox parser with network disabled. Text first, optional OCR on empty/scanned pages; capability response reports unsupported encrypted PDF/OCR. AI must preserve unresolved quantity strings and flag uncertainty.

**Zavisnosti:** F001, G-AI, G-PROVENANCE

**Male vertikalne celine:**
1. Add paste-text pure parser/draft into same preview.
2. Add bounded PDF text service and page selection; source spans retained.
3. Add OCR capability adapter for scans with explicit unavailable state and same review/save transaction.

**Kriterijumi prihvatanja:**
- [ ] Pasted fixture and text PDF preserve ingredients, source spans and null unknown quantities with no auto-save.
- [ ] Scanned PDF without OCR reports „Prepoznavanje ovog dokumenta nije dostupno” and offers text/photo input.
- [ ] Encrypted, overlimit and malformed PDFs fail boundedly; temporary uploads expire within 24 h unless explicitly retained.

**Verifikacija pri implementaciji:**
- [ ] Synthetic PDF/text/scanned/encrypted fixtures, page/byte/time cap tests and sandbox no-egress assertion.
- [ ] Parser mismatch fake-AI tests and preview corrections/discard; no upstream code executed.

**Detaljni dokazi:** [stream A](../research/streams/A.md).

## F020 — Prevod uz očuvan original

**Vlasnik:** stream A. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/domain/recipe_version.dart:RecipeVersion stores previous recipe; lib/data/recipe_repository.dart:update retains at most 30 historical versions. lib/domain/recipe.dart:toAiJson contains numeric quantities and steps, but no immutable original language/document.

**Predložena izmena:**
TranslationDraft(sourceRevisionId, targetLocale=sr-Latn, translated text by stable field IDs, numericInvariantDiff). Freeze original in provenance asset, not only the 30-version rolling history. Send text fields and placeholder tokens for quantities/units/times to AIRouter; reconstruct typed numeric fields deterministically. Unit conversions are a separate confirmed operation. Save a normal version with translation link and provenance.

**Zavisnosti:** F019, G-AI, G-PROVENANCE, G-SYNC

**Male vertikalne celine:**
1. Implement field/token mapping and numeric-invariant validator.
2. Add AIRouter translation draft and paired original/translation preview.
3. Persist confirmed version and immutable original reference with delete/restore coverage.

**Kriterijumi prihvatanja:**
- [ ] 2.5 g, 180 °C, 1/2 and 20 minutes preserve their original numeric/unit facts, including numbers inside steps.
- [ ] Any missing/changed placeholder blocks save with a review issue.
- [ ] After 31 later edits original source remains retrievable; output UI is Serbian Latin.

**Verifikacija pri implementaciji:**
- [ ] Fake provider attempts altering numeric tokens, reordered fields and Cyrillic response.
- [ ] Round-trip source/version restore, prune/delete and private asset access tests.

**Detaljni dokazi:** [stream A](../research/streams/A.md).

## F021 — Porodični PDF kuvar

**Vlasnik:** stream F. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
RecipeRepository.getAll/get daju recepte domaćinstva; RecipeView je prikaz u aplikaciji, bez PDF izvoza. Pubspec nema PDF/printing biblioteku.

**Predložena izmena:**
[
  "Predlog: RecipeBookExportService.render(ExportSelection, frozenRecipeSnapshots, PhotoReader) -> ExportArtifact(bytes, mime, warnings). Izbor sadrži samo eksplicitno odabrane ID-jeve i redosled; metadata opcije: naslov, sadržaj, fotografije, izvorni link. Snimiti read-only stanje pre renderovanja.",
  "Izostaviti AI instrukcije iz istorije, lične ocene i tuđe profile. Uključiti samo dostupne odabrane slike; nedostajuća slika daje tekstualnu zamenu. Renderovanje u pozadini; korisnik prvo dobija pregled, zatim sistemski save/share sa capability proverom. Bez OS podrške ponuditi čuvanje fajla.",
  "Predložena nova lib/features/recipes/recipe_book_export.dart koristi postojeći repozitorijum; pdf/font dependency odabrati i obrazložiti u spec plan.md tek u implementaciji. Proveriti pravo ugrađivanja fonta i srpske glifove."
]

**Zavisnosti:** G010, G-PORTABLE

**Male vertikalne celine:**
1. Izbor dva recepta -> statičan tekstualni PDF -> pregled bez upisa.
2. Dodati paginaciju, sadržaj i lokalne slike na istom toku.
3. Dodati sistemsko čuvanje/deljenje i otkazivanje velikog izvoza.

**Kriterijumi prihvatanja:**
- [ ] PDF od izabranih 2 od 5 recepata sadrži tačno ta 2 u zadatom redosledu; nema naslova ostala 3.
- [ ] ćčđšž i dugačak korak pravilno se prelamaju; naslov i porcije su vidljivi; generisanje ne menja ni jedan outbox red.
- [ ] Nedostajuća slika ne prekida izvoz; otkazivanje ne ostavlja trajni privremeni fajl.

**Verifikacija pri implementaciji:**
- [ ] Budući service test sa fake repository i photo store: hash baze i outbox count isti pre/posle.
- [ ] Otvoriti rezultat PDF parserom, proveriti broj recepata/stranica i tekst; vizuelno proveriti čćđšž i višestranične korake.
- [ ] Widget test izbora i capability denied/cancel; ručni Android/iOS/macOS save/share smoke.

**Detaljni dokazi:** [stream F](../research/streams/F.md).

## F022 — Prenosivi schema.org/Recipe JSON

**Vlasnik:** stream F. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
Recipe.toJson je Tavli interni oblik sa id/source/imagePath/createdAt; Recipe.fromJson delegira fromAiJson koji nedostajuće porcije podrazumeva na 2. To nije schema.org adapter. Ingredient.quantity/unit su opcioni, steps su ravna lista stringova.

**Predložena izmena:**
[
  "Predložiti lib/domain/recipe_portability.dart: RecipeDocument(schemaVersion, recipeCandidate, rawSourceJson, fieldProvenance, warnings, losses); RecipeJsonAdapter.decode/encode su čiste funkcije. RecipeSource proširiti preko zasebne migracije za import, ne pogrešno označiti kao manual/AI.",
  "Izvoz: @context=https://schema.org, @type=Recipe, name=title, recipeYield=tekst potvrđenih porcija, recipeIngredient=ingredientLine, recipeInstructions=HowToStep(text); prepMinutes mapirati isključivo na prepTime PT…M, nikako izmišljati cookTime ili totalTime. createdAt mapirati dateCreated. Lokalnu putanju imagePath ne objavljivati; sliku izostaviti uz upozorenje ili poseban eksplicitni paket.",
  "Uvoz prihvata objekat, listu i @graph sa tačnim Recipe tipom (string ili niz), tekstualne sastojke i PropertyValue, tekst/HowToStep/HowToSection uz redosled i sačuvan original. Razdvojiti rawYield i potvrđene servings: 12 keksa, 4–6 porcija i odsutno polje traže pregled; bez tihe pretpostavke 2. Nepoznate mere ostaju null + raw line u provenance.",
  "Ekstenzije Tavli u namespaced sidecar mogu očuvati category/note i preciznu strukturu; generičan schema.org round-trip garantuje semantički tekst i potvrđene porcije, ne identične objekte. Raw polja se ne renderuju kao HTML i ne izvršavaju; ograničiti veličinu/dubinu; ništa ne preuzimati iz image URL-a bez posebne odluke."
]

**Zavisnosti:** G-PORTABLE

**Male vertikalne celine:**
1. Test-first tekstualni Recipe export i ručni izbor fajla -> preview.
2. Decoder za kanonski Recipe i Nextcloud tipove -> per-field upozorenja -> potvrda -> repository create.
3. @graph/sections/PropertyValue + verzionisan Tavli sidecar -> loss report i ograničeni import.

**Kriterijumi prihvatanja:**
- [ ] Tavli recept sa 250 g brašna i 2 porcije izvoz/uvoz čuva naslov, tekst svih sastojaka, korake i potvrđene 2 porcije.
- [ ] Nextcloud recipeYield=null ili "4–6 servings" traži potvrdu, bez automatskog biranja maksimalnog broja.
- [ ] Za nepodržano nutrition/tags/sections polje postoji eksplicitan losses zapis; arhiva naloga se ne prihvata kao jedan Recipe JSON.
- [ ] @graph sa Recipe i Person ne uvozi Person kao recept; 10 MB/dubina 64 su predloženi početni limiti koji daju čitljivu grešku.

**Verifikacija pri implementaciji:**
- [ ] Novi test/domain/recipe_portability_test.dart: samostalne sintetičke fixtures za context http/https, type niz, graph, sections, yield range, Unicode fractions, 0/negativno/NaN, invalid JSON.
- [ ] Golden schema output + raw field retention; round-trip porediti ugovorena polja, ne source IDs ili lokalne putanje.
- [ ] Proširiti test/data/recipe_repository_test.dart i test/sync/entities_test.dart; import preview cancel mora ostaviti 0 novih redova.

**Detaljni dokazi:** [stream F](../research/streams/F.md).

## F023 — Uvoz postojećih kolekcija

**Vlasnik:** stream F. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
Nema importer registry/batch migracionog izveštaja; create upisuje jedan recept i outbox. Naslov nije jedinstveni identitet recepta.

**Predložena izmena:**
[
  "Predložiti ImportAdapter.probe(header, boundedEntries)->format/version, preview()->ImportBatch i commit(confirmedDecisions, batchId). Početni adapteri: Nextcloud direktorijumi recipe.json + full.*, zatim Mealie recipe JSON; Paprika ide u zaseban adapter posle uzorka/fixture provere.",
  "ImportItem čuva sourceRecordId, canonicalSourceUrl, contentFingerprint, candidate, unmappedFields, imageIssues i odluku skip/create/replace. Duplikat: prvo prethodno import mapiranje/identičan hash; sličan naslov samo kandidat za korisničku proveru. Nikad automatski spojiti dva različita jela istog naslova.",
  "Verzionisani ImportBatchJournal daje nastavak i idempotenciju po batchId+itemKey. Preview nema upisa. Commit svake odobrene stavke ide preko istog repository/outbox toka; neuspešna stavka ostaje u izveštaju. Za replace koristiti update i postojeću istoriju.",
  "Arhiva ima ograničenje broja fajlova, ukupne dekompresovane veličine i dubine; odbiti apsolutne putanje, ../, symlink i nested archive bez zajedničkog budžeta. Slike samo iz potvrđenog extraction root; remote URLs ne fetchovati podrazumevano."
]

**Zavisnosti:** F022, G-PORTABLE, G-SCHEMA

**Male vertikalne celine:**
1. Batch sintetičkih Recipe JSON fajlova -> preview sa losses i duplicate candidates.
2. Nextcloud ZIP adapter sa slikama -> nastavak/otkazivanje -> journal.
3. Mealie adapter sa verzijom formata -> replace kroz update -> konačan izveštaj.

**Kriterijumi prihvatanja:**
- [ ] Ulaz 5 zapisa: 2 nova + 1 već uvezen + 1 nevalidan + 1 sličan naslov daje tačan izveštaj, a commit samo odobrene nove stavke.
- [ ] Ponovno pokretanje istog batch-a i prekid posle prve stavke ne dupliraju ništa.
- [ ] recipe.json i full.jpg povezuju se po direktorijumu, bez mešanja slika dva istoimena jela.
- [ ] 10000 entries / 250 MB expanded su predloženi početni limiti; traversal i symlink ne mogu pisati/čitati van staging direktorijuma.

**Verifikacija pri implementaciji:**
- [ ] Test-first fixture matrica za svaku eksplicitno podržanu aplikaciju/verziju; malformed header, whitespace pre {, batch mixed success, ID collisions.
- [ ] Fake photo store i repository failure injection na stavci 2; resume i ponovljen commit moraju dati isti broj ID-jeva/outbox operacija.
- [ ] Archive tests: ../outside, absolute, mixed separators, duplicate names, case collision, recursive ZIP bomb; two-account RLS restore/import tests.

**Detaljni dokazi:** [stream F](../research/streams/F.md).

## F024 — Share meni i browser unos

**Vlasnik:** stream A. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/app/router.dart contains in-app routes; existing add_recipe_sheet.dart lacks a share/extension intake contract. Existing repository and preview can own eventual save.

**Predložena izmena:**
ExternalIntakeV1(kind=url|text|image, payload, intakeId, receivedAt, platform). OS share adapter and optional browser bridge feed existing ImportRequestV1; no separate storage. Persist small pending intake in account-scoped local queue; require sign-in before preview and explicit save. Reject executable schemes and oversize payload; browser extension uses least privilege active tab and never embeds provider credentials.

**Zavisnosti:** F001, F019, G-SYNC

**Male vertikalne celine:**
1. Define deduplicated intake queue and route adapter with fake platform tests.
2. Implement capability probe/share intake per supported Android/iOS/macOS target and normal URL fallback.
3. Evaluate browser extension separately after app share works; consume same schema and endpoint.

**Kriterijumi prihvatanja:**
- [ ] Same intake delivered twice yields one pending draft; no background recipe save.
- [ ] Cold/warm start and sign-in handoff preserve payload only within selected account.
- [ ] Unsupported platform displays „Nalepi link recepta”; URL parser rejects file/javascript/data schemes.

**Verifikacija pri implementaciji:**
- [ ] Platform integration matrix for cold/warm app, canceled sign-in, account switch, app restart and invalid deep link.
- [ ] Fake hostile extension payload and preview discard/idempotent save tests.

**Detaljni dokazi:** [stream A](../research/streams/A.md).

## F025 — Uvoz objave sa društvene mreže

**Vlasnik:** stream A. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
No social import integration exists in inspected lib/ai/recipe_ai.dart or add_recipe_sheet.dart. RecipeSource cannot express source post/transcript provenance.

**Predložena izmena:**
SocialImportCapability(platform, supportedMedia, publicUrlOnly, status) delegates URL/text/image material to ImportDraftV1. Record post URL, submitted caption/transcript ownership/source and unavailable sections. Begin user-supplied caption/image rather than promise platform API access. No authenticated scraping, paywall bypass, remote code execution or invention from thumbnail/title; platform adapter returns needsUserContent when insufficient.

**Zavisnosti:** F001, F019, F024, G-PROVENANCE

**Male vertikalne celine:**
1. Accept supplied post URL plus caption/image through shared draft flow.
2. Add supported-public-domain capability adapter only after API/terms review.
3. Add transcript spans when available; retain partial draft and review state.

**Kriterijumi prihvatanja:**
- [ ] Title+thumbnail alone produces insufficient evidence, not a full recipe.
- [ ] Private/deleted/blocked post offers paste/photo path without requesting social credentials.
- [ ] Every inferred field is marked; confirmation needed before recipe save.

**Verifikacija pri implementaciji:**
- [ ] Synthetic public-caption, partial-caption, unavailable-post and prompt-injection fixtures.
- [ ] Capability-off and timeout widget flows; provenance and no-autosave checks.

**Detaljni dokazi:** [stream A](../research/streams/A.md).

## F026 — RSS predlozi

**Vlasnik:** stream A. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
No feed entities or subscription scheduler in lib/data/database.dart; RecipeRepository stores only explicitly saved recipes.

**Predložena izmena:**
FeedSubscriptionV1(id, householdId, url, enabled, etag, lastModified, checkedAt) and FeedEntryV1(feedId, entryKey, title, link, publishedAt, state). Feed entries are suggestions, separate from Recipes. Fetch server-side via G-SERVER, parse bounded RSS/Atom with XML external entities/DTD/network disabled; conditional HTTP, capped poll/backoff and per-household uniqueness. Selecting entry invokes F001 preview.

**Zavisnosti:** F001, G-SERVER, G-SYNC

**Male vertikalne celine:**
1. Implement bounded synthetic RSS/Atom parser and stable entry identity.
2. Add subscription repository/cache and constrained server polling.
3. Show suggestions with explicit import preview and unsubscribe/delete lifecycle.

**Kriterijumi prihvatanja:**
- [ ] Repeated fetch/304 produces zero duplicate entries and zero recipe writes.
- [ ] Unknown/non-date publication time stays unknown; GUID-less stable key uses normalized link and feed scope.
- [ ] XXE/entity expansion blocked; private enclosure/image/link cannot bypass fetch boundary.
- [ ] Unsubscribe halts later polling; offline shows last successful check time.

**Verifikacija pri implementaciji:**
- [ ] RSS/Atom/namespace fixtures, GUID reuse, 304, bad ETag, redirects, XML bomb and malicious link tests.
- [ ] Fake clock rate/backoff and unsubscribe; preview/discard/offline widgets and RLS.

**Detaljni dokazi:** [stream A](../research/streams/A.md).

## F027 — Podrecepti i zbir nabavke

**Vlasnik:** stream F. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
Ingredient je samo name/quantity/unit/category/note; RecipeSnapshot zamrzava ravne ingredients. demandFor čuva DemandSource identitet i sabira kompatibilne jedinice. Nema grafa recepta.

**Predložena izmena:**
[
  "Nadograditi postojeći model komponentom RecipeComponent = IngredientComponent | SubrecipeComponent(childRecipeId, childRevisionHash, requestedYield, yieldUnit, frozenChild). Parent i child čuvaju poznat baseYield; broj porcija nije automatski masa sosa.",
  "Pure expandRecipe(snapshot, requestedYield) -> ExpandedDemand(lines, provenancePaths, warnings). DFS stack odbija cikluse i preveliku dubinu pre upisa (predlog max 16); deljeni child u dva kraka mora doprineti oba puta. Za 200 g sosa iz recepta za 1000 g množiti child sastojke sa 0.2. Ne mešati g sa porcijama bez eksplicitne konverzije.",
  "Zamrznuti kompletno razrešen graf u odobrenom meal/shopping snapshot-u. Kasnija child izmena/brisanje ne menja plan. Provenance putanja sourceId/componentPath omogućava objašnjenje nabavke; odabrati da se referenca računa kao sastojci ili kao već pripremljen sos, nikada oba istovremeno."
]

**Zavisnosti:** G010, G-SCHEMA, F022, F002

**Male vertikalne celine:**
1. Jedan parent -> child sa masenim yield -> preview proširene nabavke.
2. Snapshot grafa i outbox/remote serialization -> cycle/depth validacija.
3. Više nivoa i ponovljen child -> potvrđen izbor gotovo/sastojci -> regressions nabavke.

**Kriterijumi prihvatanja:**
- [ ] Child 1000 g sosa traži 500 g paradajza; parent za 2 porcije koristi 200 g sosa: 100 g paradajza; za 4 porcije 200 g.
- [ ] A->B->A se odbija pre bilo kakvog upisa; A->B i A->C->B računaju oba doprinosa.
- [ ] Promena/brisanje child recepta posle odobrenja ne menja plan ni zamrznutu nabavku.
- [ ] Nepoznat yield daje needsReview i ne izmišlja koeficijent.

**Verifikacija pri implementaciji:**
- [ ] Domain test-first DFS cycle/diamond/depth, različite yield jedinice, null količine, mikros rounding.
- [ ] Proširiti test/domain/shopping_demand_test.dart, test/data/shopping_repository_test.dart i test/data/meal_plan_repository_test.dart za tačan unapred izračunat primer.
- [ ] Round-trip serialized graph + offline sync + RLS dva domaćinstva; stari flat snapshot ostaje validan.

**Detaljni dokazi:** [stream F](../research/streams/F.md).

## F028 — Veze sastojaka i koraka

**Vlasnik:** stream E. **Faza:** P2; G-STEP minimalni adapter potreban u P1. **Status:** planirano.

**Postojeće stanje:**
lib/domain/recipe.dart: Ingredient nema id, Recipe.steps je List<String>. lib/domain/shopping_source.dart: RecipeSnapshot.fromJson takođe čita string korake. lib/data/recipe_repository.dart: _toCompanion/_fromRow serijalizuju JSON; lib/sync/entities.dart: RecipeEntity prenosi ingredients/steps. Pozicioni indeksi nisu bezbedni pri reorder-u.

**Predložena izmena:**
[
  "Proširiti postojeći Recipe/RecipeSnapshot sa verzionisanim RecipeStep {id,text,ingredientUses,timerSuggestions?,ovenSetting?}; Ingredient dobija stabilan lokalni UUID u receptu. IngredientUse {ingredientId,amount?,unit?,usageNote?} referencira postojeći sastojak.",
  "Legacy string liste čitati preko adaptera; ID-jeve jednom dodeliti i persistirati pri migraciji, nikad nasumično pri svakom renderu. Ne uvesti drugu biblioteku recepata. Nepovezan korak prikazuje pun spisak; automatske veze samo predlog za potvrdu.",
  "F022/F084 su partneri za koordinaciju formata i validatora, ne preduslovi koji blokiraju ručno povezivanje. Minimalni G-STEP adapter ne zahteva kompletnu F028 funkciju."
]

**Zavisnosti:** G-SYNC, G-STEP, G-FORMAT-COORDINATION

**Male vertikalne celine:**
1. Definisati v2 JSON i kompatibilan legacy reader za recipe/version/plan/preparation snapshot; round-trip fixture.
2. Editor ručnih veza i prikaz količine uz korak; reorder/delete/undo.
3. AI/import/export adapteri i rolling-client guard; potvrđeni snapshotovi ne menjaju se retroaktivno.

**Kriterijumi prihvatanja:**
- [ ] Reorder sastojaka/koraka čuva veze po ID-u; uklanjanje daje vidljiv unresolved link i zahteva potvrdu.
- [ ] Brašno 500 g podeljeno 300+200 g prikazuje obe upotrebe; 600 g ukupno se označava kao konflikt, ne menja tiho recept.
- [ ] Recept v1 ostaje čitljiv sa identičnim tekstom i količinama; nepoznata raspodela ne izmišlja se.

**Verifikacija pri implementaciji:**
- [ ] Round-trip svi serializer-i: Recipe.toJson/fromJson, RecipeSnapshot, prethodne verzije, drift i SyncEntity.
- [ ] Fixtures sa duplim nazivima, ponovljenim korakom, reorder, brisanjem i restore; veze ne prelaze na drugi sastojak.
- [ ] Dva klijenta različitih schema: stariji ne sme upisom string liste obrisati v2 metapodatke; testirati zabranu pisanja ili server verzioni gate.

**Detaljni dokazi:** [stream E](../research/streams/E.md).

## F029 — Mediji uz korak

**Vlasnik:** stream E. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
Recipe.imagePath u lib/domain/recipe.dart predstavlja jednu sliku; lib/features/recipes/recipe_photo.dart: RecipePhoto i lib/data/recipe_photo_store.dart rade sa fotografijom recepta. lib/sync/photo_sync.dart i lib/sync/entities.dart: photoLocalPath koriste recipe_photos; nema per-step video ugovora.

**Predložena izmena:**
[
  "StepMedia {id,stepId,kind,storageKey?,externalUrl?,caption,altText,provenance,rights,contentHash,mime,byteLength,durationMs?}; odvojiti dish/document/step u media contract-u sa streamom F.",
  "Prvo sopstvena fotografija u privatnom storage-u i offline cache; potom kratak video uz vidljiv download/veličinu. Spoljni video je link sa izvorom, ne kopirani fajl; nema automatskog preuzimanja."
]

**Zavisnosti:** F028, F023, F065, G-SYNC

**Male vertikalne celine:**
1. Step photo upload + preview + lokalni thumbnail bez menjanja recipe image.
2. Privatne politike, retry/outbox i brisanje bez orphan fajlova.
3. Video capability/codec probe, ograničenje trajanja/veličine u spec-u i opcioni predownload.

**Kriterijumi prihvatanja:**
- [ ] Offline korak ostaje čitljiv kada medij nije preuzet; objašnjenje Medij nije dostupan.
- [ ] Drugi nalog van domaćinstva ne može preuzeti privatni fajl; promena recepta ne prevezuje medij na drugi step.
- [ ] Nema autoplay zvuka; alt tekst i caption su dostupni; otkazivanje upload-a ne ostavlja referencu na nepostojeći fajl.

**Verifikacija pri implementaciji:**
- [ ] Fake PhotoRemote: prekid veze, dupli upload retry, uklanjanje i ponovni download.
- [ ] Lokalni Supabase pgTAP/storage test sa dva naloga i pripadnošću; provera media ownership pri promeni step-a.
- [ ] Widget slow/missing cache, video unsupported codec, telefon/wide; real device memorija i lifecycle player dispose.

**Detaljni dokazi:** [stream E](../research/streams/E.md).

## F030 — Potroši ove tri namirnice

**Vlasnik:** stream A. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
filterRecipes in lib/domain/recipe_format.dart only searches titles; F004 quantity engine exists at domain level but no session-only ingredient selector.

**Predložena izmena:**
QuickIngredientIntentV1(selected canonical ingredient IDs, optional quantities/unit, expiresWithSession=true). Feed same RecipeQuery/feasibility/scoring contracts. Name-only entries contribute matched-ingredient reasons, never confirmed availability. No phantom pantry entries or supply IDs; optional quantities are ephemeral scenario supply and clearly distinct from confirmed stock.

**Zavisnosti:** F002, F004

**Male vertikalne celine:**
1. Add pure matching by canonical ingredients and evidence type.
2. Add 1–3 ingredient quick action on existing search flow.
3. Allow optional quantity scenario and transition to normal plan preview with no pantry writes.

**Kriterijumi prihvatanja:**
- [ ] Three selected ingredient names produce ranked matches even with an empty pantry.
- [ ] Name-only match shows „Sadrži izabrane namirnice”, never „Imaš sve”.
- [ ] Closing flow leaves pantry/outbox unchanged; duplicate synonyms count once.

**Verifikacija pri implementaciji:**
- [ ] Empty-pantry, synonym-duplicate and unknown-quantity tests.
- [ ] Widget enter/clear/close and verify zero database writes until explicit recipe/plan approval.

**Detaljni dokazi:** [stream A](../research/streams/A.md).

## F031 — Želim uskoro da kuvam

**Vlasnik:** stream B. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/features/planning/plan_generation.dart: useRecipe postavlja recept na određeni MealSlot; PlanRequest.only očekuje datirana mesta. Nema nedatiranog reda u pregledanim modelima.

**Predložena izmena:**
CookingQueueItem{id,householdId,recipeId?,snapshot,positionKey,requestedServings,createdBy}; nema shopping source dok se ne odobri raspoređivanje. schedule(queueItem,slot,targetBase) pravi postojeći nacrt; uklanjanje stavke reda tek u istoj transakciji sa uspešnim odobrenjem. Duplikat recepta je dozvoljen kao odvojena namera.

**Zavisnosti:** G-SYNC, G-PLAN-REV

**Male vertikalne celine:**
1. Dodaj/ukloni i promeni redosled nedatiranih snimaka offline.
2. Izaberi datum/obrok dugmetom; drag je dodatna radnja na širokom ekranu.
3. Pregled zamene postojećeg unosa i atomarno odobrenje+uklanjanje iz reda.

**Kriterijumi prihvatanja:**
- [ ] 10 stavki u redu daje 0 novih shopping sources.
- [ ] Odbijen zastareo nacrt ostavlja stavku u redu i postojeći obrok netaknut.
- [ ] Obrisani bibliotečki recept ima upotrebljiv snapshot; prazno mesto i zamena imaju različit pregled.

**Verifikacija pri implementaciji:**
- [ ] Repository fake backend: schedule rollback i isti operationId dvaput.
- [ ] Widget 390/1024 px, tastatura i tekst 2× bez obaveznog drag-a.
- [ ] Dva uređaja raspoređuju istu queue stavku: jedna potvrđena operacija, konflikt druge.

**Detaljni dokazi:** [stream B](../research/streams/B.md).

## F032 — Pravila po danima

**Vlasnik:** stream B. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/domain/meal_plan.dart: PlanRequest.wishes je slobodan tekst; lib/ai/meal_plan_ai.dart: parseOutline proverava oblik/slotove/recipeId, ne pravila sastojaka ili dana.

**Predložena izmena:**
DayRule{id,weekday,mealType?,predicate,mode=required|preferred,version}; eksplicitni SlotRuleOverride{ruleId,slot,reason}. Deterministički evaluator nad potvrđenim recipe metadata/ingredients vraća pass/fail/unknown sa dokazom. Obavezne alergije ostaju neizuzimljiva ograničenja iz streama A; lokalno dnevno pravilo nije dozvola za njihovo zaobilaženje.

**Zavisnosti:** G-SYNC, G-RULE-METADATA, G-HARD-CONSTRAINTS

**Male vertikalne celine:**
1. Ručno pravilo i evaluator za jedan potvrđen tag/namirnicu.
2. Dodaj pravila u zahtev generatora i validaciju posle AI rezultata; nema rezultata prikazuje razlog.
3. Pregled odstupanja i eksplicitni override samo dnevnog pravila, sa čuvanjem verzije u planu.

**Kriterijumi prihvatanja:**
- [ ] Ponedeljak bez mesa odbija poznat mesni recept i označava neklasifikovan kao Neprovereno.
- [ ] Petak riba i <=20 aktivnih minuta se kombinuju; 0 kandidata ne popušta pravilo tiho.
- [ ] Override ponedeljka ne važi za sledeći ponedeljak niti menja alergije.

**Verifikacija pri implementaciji:**
- [ ] Domain matrica weekday 1..7, mealType wildcard, preferred/required i unknown.
- [ ] Fake AI vrati zabranjen recept: pregled pokazuje prekršaj i approve ga odbija bez override-a.
- [ ] Offline sačuvano pravilo i RLS dva domaćinstva; regresija parseOutline.

**Detaljni dokazi:** [stream B](../research/streams/B.md).

## F033 — Obrok van kuće

**Vlasnik:** stream B. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/domain/meal_plan.dart: SlotProposal uvek bira libraryRecipeId ili draftRecipeKey; PlannedMeal.snapshot null označava legacy zapis, ne obrok van kuće. reconcilePlan preskače unos bez snimka.

**Predložena izmena:**
Proširi postojeći unos diskriminatorom kind=cook|leftover|away, awayReason=restaurant|visiting|skip i opcioni label. Ne koristiti null snapshot kao diskriminator. away zauzima termin, nema sirovinsku potražnju i generator ga čuva dok korisnik izričito ne odabere zamenu.

**Zavisnosti:** G-SYNC, G-PLAN-REV

**Male vertikalne celine:**
1. Migracija kind=cook za postojeće unose i ručni away unos.
2. Prikaži zauzet termin i isključi ga iz regenerableSlots.
3. Pregled cook<->away zamene i reconcile samo razlike.

**Kriterijumi prihvatanja:**
- [ ] Restoran, Kod roditelja i Preskačem daju 0 demand lines i prikazuju zauzet slot.
- [ ] Zamena recepta restoranom čuva kupljene/ručne stavke i oslobađa samo neiskorišćene rezervacije.
- [ ] Stari nečitljiv snapshot pokazuje Recept nije dostupan, ne Restoran.

**Verifikacija pri implementaciji:**
- [ ] Domain exhaustive switch/parser nepoznatog kind-a i legacy fallback.
- [ ] Repository zamena sa kupljenih 200 g i rezervisanih 100 g: kupovina opstaje, neiskorišćena rezerva se oslobađa.
- [ ] Widget away oznaka, undo i regeneracija koja ga ne prepisuje.

**Detaljni dokazi:** [stream B](../research/streams/B.md).

## F034 — Vreme po danu

**Vlasnik:** stream B. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/domain/shopping_source.dart: RecipeSnapshot.prepMinutes je jedina vremenska mera; lib/features/planning/meal_entry_card.dart prikazuje je kao min, bez razlikovanja aktivnog/ukupnog.

**Predložena izmena:**
RecipeTiming{activeMinutes?,elapsedMinutes?,source,confirmedAt}; SlotTimeBudget{slot,maxActiveMinutes?,maxElapsedMinutes?,window?}. Postojeći prepMinutes zadržati kao legacy nespecificirano vreme, ne migrirati automatski u aktivno. Poznato trajanje proverava kod; unknown zahteva proveru pre tvrdog ograničenja.

**Zavisnosti:** G-SYNC, G-PLAN-REV

**Male vertikalne celine:**
1. Potvrđeno aktivno/ukupno vreme i ručni budžet za jedan dan.
2. Evaluator i prikaz poznato/nepoznato u postojećem pregledu.
3. Generator filtrira/rangira uz isti evaluator, bez tihog popuštanja.

**Kriterijumi prihvatanja:**
- [ ] Utorak 20 min: recept 15 aktivno/60 ukupno prolazi aktivni limit; 25/30 ne prolazi.
- [ ] Ako postoji i prozor 18:00–18:45, 60 ukupno ne staje, iako aktivni rad prolazi.
- [ ] Legacy prepMinutes=15 ne postaje potvrđenih 15 aktivno; nedelja 90 ne menja utorak.

**Verifikacija pri implementaciji:**
- [ ] Domain granice 20/21, unknown, nula/negativno, active<=elapsed.
- [ ] Fake AI prekršaj i ručna izmena metadata posle početka nacrta invalidiraju evaluaciju.
- [ ] Widget dve jasno odvojene mere i offline unos; regresija postojećeg prikaza vremena.

**Detaljni dokazi:** [stream B](../research/streams/B.md).

## F035 — Kontrola ponavljanja

**Vlasnik:** stream A. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/ai/meal_plan_ai.dart:propose only passes already planned draft titles to outline. lib/data/meal_plan_repository.dart:setCooked toggles bool; lib/data/database.dart:MealPlanEntries has isCooked but no actual cookedAt event history.

**Predložena izmena:**
RepetitionRuleV1(canonicalRecipeId, windowDays, maxOccurrences, mode=hard|prefer) and CookingOccurrence(eventId, entryId?, recipeIdentity, recipeRevision, cookedOn, reversesEventId?). Integrate F047 actual cooking history; existing true flags have unknown actual dates and must not be fabricated from planned dates. Count actual cooking plus accepted prospective slots for planning limits, without counting canceled/undone cooking twice. Tie history to stable recipe identity, not title.

**Zavisnosti:** F047, G-RULES, G-SYNC

**Male vertikalne celine:**
1. Agree cooking-event contract with stream E and migrate legacy flags as undated evidence.
2. Add pure rolling-window counter and candidate predicate.
3. Expose frequency setting and reason; use in offline and AI candidate validation.

**Kriterijumi prihvatanja:**
- [ ] One cooking yesterday with max 1/7 days prevents another proposed occurrence; unexecuted old plans do not.
- [ ] Two recipes sharing a title remain distinct; rename does not erase history.
- [ ] Unsatisfiable frequency leaves slot unresolved and offers explicit rule edit; no silent relaxation.

**Verifikacija pri implementaciji:**
- [ ] Fixed-date 7-day boundary, undo/duplicate event, rename and same-title fixtures.
- [ ] Legacy isCooked import shows unknown date; fake AI violating frequency rejected.

**Detaljni dokazi:** [stream A](../research/streams/A.md).

## F036 — Lokacije namirnica

**Vlasnik:** stream C. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. No location field/table; /pantry remains placeholder.

**Predložena izmena:**
[
  "Add PantryLocation(id, householdId, name, active) and nullable locationId on PantryItems. Unknown location remains null; default labels Frižider/Zamrzivač/Ostava are editable.",
  "Move whole lot updates the same pantry id and canonical physical identity. A partial move requires split children and conservation under GTX; do not create extra capacity."
]

**Zavisnosti:** G010, GTX

**Male vertikalne celine:**
1. Add nullable location metadata with migration and sync/RLS.
2. Whole-lot move and filtered pantry UI.
3. Only then partial move with split transaction and 200+300=500 g fixture.

**Kriterijumi prihvatanja:**
- [ ] Move 500 g pantry lot from Ostava to Frižider: global stock remains 500 g, existing allocations remain valid, sourceShoppingItemId unchanged.
- [ ] Cross-household location rejected; deleting location reassigns to unknown and retains food.

**Verifikacija pri implementaciji:**
- [ ] Repository move+retry and location filter tests; two-account RLS and outbox replay.
- [ ] Phone/wide widget tests null/renamed/archived location and offline move.

**Detaljni dokazi:** [stream C](../research/streams/C.md).

## F037 — Otvoreno pakovanje

**Vlasnik:** stream C. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. expiresAt is single date; no openedAt or opened-use-by provenance.

**Predložena izmena:**
[
  "Add lot openedAt, labelUseByAt, openedUseByAt, dateEvidence and dateKind. Opening alone does not change mass; effective usable date is the earliest applicable confirmed date.",
  "User enters/confirms after-opening date from declaration. Never infer safety interval from barcode/name or AI. Keep original manufacturer date and disclose unknown date."
]

**Zavisnosti:** F038, F039, GTX

**Male vertikalne celine:**
1. Model separate dates/evidence and migration without populating invented dates.
2. Manual opening preview and confirmation; reconcile stock eligibility.
3. Optional reminders from effective confirmed date with permission-denied fallback.

**Kriterijumi prihvatanja:**
- [ ] Original date 20 Nov, confirmed after-opening 12 Nov => effective 12 Nov; opening twice preserves original openedAt unless explicitly corrected.
- [ ] Missing after-opening rule remains unknown, not a calculated safe lifetime; mass unchanged.

**Verifikacija pri implementaciji:**
- [ ] Injected-clock unit tests before/equal/after dates and timezone civil date handling.
- [ ] Repository stale edit conflict and widget user-confirmed label evidence, no-date flow.

**Detaljni dokazi:** [stream C](../research/streams/C.md).

## F038 — Odvojene ture iste namirnice

**Vlasnik:** stream C. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. PantryItems IDs can already represent separate rows; allocateSupply currently sorts supply canonical IDs, not expiry; receipts assume at most one pantry row per shopping item in receivePurchases.

**Predložena izmena:**
[
  "Treat existing PantryItems as lots, add lot metadata only; same ingredient can have multiple lots. Add expiry-priority selection after demand ordering: confirmed earliest eligible expiry first, unknown last, stable id tie-break; preserve valid historical reservations until user requests rebalance.",
  "For splitting a received purchase create PhysicalSupply root plus portions or explicit receipt-line children. Replace one-to-one receipt lookup only with defined migration/unique operation key; sum children <= root remaining. Never set every split child samePhysicalAs to the whole root because current canonical dedupe would collapse them."
]

**Zavisnosti:** G010, GQ, GTX

**Male vertikalne celine:**
1. Document and test physical-root/portion representation against existing canonical algorithm before schema changes.
2. Add lot dates and FEFO proposal while retaining current single-row receipts.
3. Add optional split/merge with root conservation, unique operation keys and outbox atomicity.

**Kriterijumi prihvatanja:**
- [ ] Lots 300 g expiring 12 Nov and 400 g expiring 20 Nov cover demand 500 g as 300+200 on a new allocation; remaining 200 g.
- [ ] Split purchased 1000 g into 400+600 g, repeat operation and receive retry: confirmed total stays 1000 g, never 2000 g; expired received lot must not reappear through bought fallback.

**Verifikacija pri implementaciji:**
- [ ] Extend test/domain/supply_allocation_test.dart for FEFO, unknown expiry, ties, retained reservation and split conservation.
- [ ] Repository fixture purchase->receipt->split->expire->reconcile; sync replay and two-device identical operation conflict.

**Detaljni dokazi:** [stream C](../research/streams/C.md).

## F039 — Brza provera inventara

**Vlasnik:** stream C. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. confirmedAt exists; no general pantry CRUD/inventory workflow. ShoppingRepository._reconcile checks non-null confirmation, but does not enforce a freshness age.

**Predložena izmena:**
[
  "Extend PantryRepository confirmQuantity/markEmpty/markUnknown with operation id, clock and expected revision. Known uses micros; empty is confirmed zero; unknown is null with a separate checkedAt and confidence state.",
  "Keep checkedAt distinct from quantityConfirmedAt. Define explicit user-configurable freshness policy rather than silently invalidating old stock. A received purchase marked unknown/empty must suppress bought-item fallback for the same physical root."
]

**Zavisnosti:** G010, GQ, GTX

**Male vertikalne celine:**
1. Add pure confidence/freshness contract and regression tests for received-root fallback.
2. Implement repository commands with transactional reconcile and outbox.
3. Replace pantry placeholder with list and quick confirm editor.

**Kriterijumi prihvatanja:**
- [ ] Known 250 g -> unknown results in no numeric allocation; empty gives zero; repeating confirmation never increases stock.
- [ ] With bought 250 g received and then marked empty, 100 g new demand remains 100 g, rather than being covered by the old bought record.

**Verifikacija pri implementaciji:**
- [ ] Repository fixtures known/unknown/empty across purchase receipt aliases, stale revision and fake clock.
- [ ] Widget quick inventory offline, undo explicit correction, phone/wide, text 2x; RLS two households.

**Detaljni dokazi:** [stream C](../research/streams/C.md).

## F040 — Dnevnik bačene hrane

**Vlasnik:** stream C. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. No food movement/waste reason log; isCooked is not a waste entry.

**Predložena izmena:**
[
  "Add stock movement reason waste and immutable WasteDetail(movementId, lotId, amountMicros, unitGroup, reason, occurredAt, optional amountMinor/currency). Waste and eaten movements remain distinct; no inferred monetary value.",
  "Approval subtracts confirmed capacity and recalculates affected reservations atomically; reversal creates compensating movement. Unknown quantity may be logged as qualitative but never used in numeric waste totals."
]

**Zavisnosti:** GTX, F038, F039

**Male vertikalne celine:**
1. Add typed reason and confirmed waste preview with numeric tests.
2. Post atomic movement and recompute reservations; sync and RLS.
3. Read-only monthly totals by compatible unit and cost currency with unknown coverage.

**Kriterijumi prihvatanja:**
- [ ] 500 g lot - 120 g waste = 380 g; retry same operation remains 380 g; reversal restores 500 g once.
- [ ] Report displays 120 g waste independently from consumption and excludes missing price from cost sum with coverage count.

**Verifikacija pri implementaciji:**
- [ ] Domain conservation and negative/overflow tests; repository rollback on outbox error.
- [ ] Widget reason/amount review, compensation and fake clock monthly boundary.

**Detaljni dokazi:** [stream C](../research/streams/C.md).

## F041 — Redosled kategorija prema prodavnici

**Vlasnik:** stream D. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/features/shopping/shopping_list_view.dart::ShoppingItemsList koristi byCategory(open,...); nema izabrane poslovnice ni StoreLayout u lib/data/database.dart. Postojeće kategorije i ShoppingItemTile treba zadržati.

**Predložena izmena:**
[
  "StoreBranch i StoreLayout(householdId,branchId,revision,categoryOrder[]) sa jedinstvenim category ključevima; opciona pozicija artikla kasnije. Sort ključ = poznata pozicija kategorije, postojeći redosled nepoznatih kategorija, stabilni itemId. To je pogled, ne promena identiteta ili potražnje stavke."
]

**Zavisnosti:** G-SCHEMA

**Male vertikalne celine:**
1. Ručni izbor/profil poslovnice i sačuvan raspored.
2. Determinističko sortiranje otvorenih stavki u postojećoj listi.
3. Uređivanje redosleda i offline sync rasporeda.

**Kriterijumi prihvatanja:**
- [ ] Isti spisak pri promeni prodavnice menja samo redosled; bought status i izvori ostaju isti.
- [ ] Nepoznate kategorije se pojavljuju posle uređenih i nijedna stavka nije izgubljena.
- [ ] Kupljene stavke ostaju u postojećoj odvojenoj sekciji.

**Verifikacija pri implementaciji:**
- [ ] Pure sorter fixture: voće/mlečno/hleb i nepoznata kategorija, jednaki rangovi i prazan layout.
- [ ] Widget promena A→B→A na telefonu/široko; repository roundtrip i regression setBought/receivePurchases.

**Detaljni dokazi:** [stream D](../research/streams/D.md).

## F042 — Kupovina celih pakovanja

**Vlasnik:** stream C. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. ShoppingNeed/micros summarize compatible demand; no package-size or rounding model; shopping row quantity currently doubles as purchase quantity.

**Predložena izmena:**
[
  "PackageOption(productId, contentMicros, unitGroup, packCount, confirmedAt) feeds pure PackageProposal. n=(need+pack-1)~/pack, surplus=n*pack-need for positive integer pack; zero need ->0 packs. Keep exact recipe demand separate from proposed/actual purchase.",
  "Only confirmed actual bought content becomes supply; surplus may enter pantry once through existing receipt link. Unknown size/dimension mismatch retains exact need and asks for package confirmation."
]

**Zavisnosti:** GQ, F017, F038

**Male vertikalne celine:**
1. Pure integer rounding preview with a manually entered package size (F017 optional).
2. Persist proposal separate from frozen purchase provenance; confirm actual bought amount.
3. Catalog-assisted package choice and optional multiple-size optimization only as later separate slice.

**Kriterijumi prihvatanja:**
- [ ] 750 g need with 500 g package proposes 2 packages/1000 g and 250 g surplus; 1000 g need proposes 2/0 surplus.
- [ ] 100 g pantry plus 2 bought 500 g packs can cover at most 1100 g across plans and preparations; receipt creates no additional capacity; reject zero package.

**Verifikacija pri implementaciji:**
- [ ] Integer fixtures 0,1 micro,exact multiples, huge safe bounds, unknown and mass/volume mismatch.
- [ ] Repository buy actual quantity different from proposal then receive twice, edit plan, preserve purchase history.

**Detaljni dokazi:** [stream C](../research/streams/C.md).

## F043 — Budžet tokom kupovine

**Vlasnik:** stream D. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/shopping_repository.dart::setBought/_buy i lib/features/shopping/shopping_list_view.dart::ShoppingItemsList razlikuju kupljeno/otvoreno, bez novčanog modela. ShoppingItems.purchaseProvenanceJson zamrzava izvor, ne cenu.

**Predložena izmena:**
[
  "ShoppingBudget(listId,currency,limitMinor?); PurchaseLine(itemId,purchaseEventId,quantityMicros,actualLineTotalMinor?,currency,source,confirmedAt); EstimateLine ima observationId i freshness. Odvojiti confirmedBoughtTotal, estimatedOpenTotal i unknownLineCount; null nije nula. Snapshot stvarne kupovine ne zavisi od kasnije promene kataloške cene."
]

**Zavisnosti:** G-MONEY, G-SCHEMA

**Male vertikalne celine:**
1. Potvrđena cena cele kupljene stavke i zbir.
2. Budžetski limit i odvojena procena preostalog.
3. Cena po jedinici, potvrđene količine i ispravka računa kao nova revizija.

**Kriterijumi prihvatanja:**
- [ ] Kupljene stavke 12345 i 20000 minor daju 32345; procena otvorene 5000 i jedna nepoznata daju prikaz 32345 potvrđeno + 5000 procenjeno + 1 bez cene.
- [ ] Mešane valute se ne sabiraju; nedostajuća cena nije 0.
- [ ] Označavanje bought bez cene radi kao danas i dodaje nepoznatu vrednost.

**Verifikacija pri implementaciji:**
- [ ] Test-first money parser/sum i boundary overflow; negativni račun kroz refund događaj, ne negativnu cenu artikla.
- [ ] Repository buy/unbuy/rebuy sa dva uređaja; povratak iz ostave po postojećim ograničenjima i ispravka cene ne menjaju zalihu.
- [ ] Widget „Potvrđeno”, „Procena preostalog”, „Bez cene: 1”, „Budžet”.

**Detaljni dokazi:** [stream D](../research/streams/D.md).

## F044 — Preuzimanje stavki od strane članova

**Vlasnik:** stream D. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::ShoppingItems ima isBought, nema assignedTo; lib/data/shopping_repository.dart::setBought potvrđuje kupovinu. Osnovno članstvo trenutno podržava samo owner u 20261030120100_accounts.sql.

**Predložena izmena:**
[
  "ItemClaim(itemId,householdId,assigneeUserId?,claimedAt,revision). claim(itemId,expectedRevision) je CAS komanda u postojećem outbox-u; assignment i bought su nezavisni. Sam član preuzima/oslobađa svoje; owner/admin mogu preraspodeliti uz vidljiv trag. Offline preuzimanje je provisional do server potvrde, nikad obećanje ekskluzivnosti."
]

**Zavisnosti:** F011, G-SCHEMA

**Male vertikalne celine:**
1. Prikaz „Kupujem ja” i lokalna provisional dodela.
2. Server CAS i UI za izgubljeno preuzimanje.
3. Oslobađanje, admin preraspodela i uklanjanje člana.

**Kriterijumi prihvatanja:**
- [ ] Istovremeni zahtev dva člana daje tačno jednog potvrđenog kupca; drugi vidi čije je preuzimanje uspelo.
- [ ] Claim ne menja isBought, pantry ni demand.
- [ ] Uklonjeni član ne ostaje aktivni assignee; istorija kupovine zadržava postojeće autorstvo.

**Verifikacija pri implementaciji:**
- [ ] Dva fake klijenta claim na istoj reviziji, duplicate/reordered delivery, claim+buy i claim+delete.
- [ ] Local RLS member iz drugog domaćinstva i viewer ne preuzimaju; widget „Preuzeo/la”, „Čeka potvrdu”, „Oslobodi”.

**Detaljni dokazi:** [stream D](../research/streams/D.md).

## F045 — Moja osnovna korpa

**Vlasnik:** stream D. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/data/shopping_repository.dart::addManual dodaje ručnu stavku, _reconcile čuva ručne stavke; lib/data/database.dart nema šablon redovne kupovine. To je odvojeno od ostave i minimalnih zaliha.

**Predložena izmena:**
[
  "ShoppingTemplate(id,householdId,name,revision) i TemplateLine(id,templateId,name,quantityMicros?,unit,category,productRefId?,details). instantiate(selection,listId,operationId) eksplicitno pravi ručne ShoppingItems kroz proširenje postojećeg ShoppingRepository; batch UUID obezbeđuje idempotentni retry. Pravilo duplikata je pregled i izbor „Dodaj posebno”/„Spoji”, nikad tiho povećanje kupljene stavke."
]

**Zavisnosti:** G-SCHEMA

**Male vertikalne celine:**
1. Sačuvaj i uredi šablon, bez automatskog dodavanja.
2. Izaberi podskup i dodaj u postojeću listu atomarno sa outbox-om.
3. Pregled duplikata i opcioni product/details snapshot.

**Kriterijumi prihvatanja:**
- [ ] Od 5 omiljenih izabrana 2 stvaraju tačno 2 očekivana unosa; retry istog operationId ne dodaje nove.
- [ ] Promena šablona ne menja već stvorenu nabavku.
- [ ] Nema automatskog čitanja minimalne zalihe niti automatske kupovine.

**Verifikacija pri implementaciji:**
- [ ] Repository transaction rollback i duplicate batch retry; merge dve iste namirnice sa uporedivim/neuporedivim jedinicama.
- [ ] Widget „Moja osnovna korpa” → izbor → pregled → dodaj; regression recipe/plan reconciliation i ručni redovi.

**Detaljni dokazi:** [stream D](../research/streams/D.md).

## F046 — Nutritivne vrednosti po porciji

**Vlasnik:** stream F. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
Recipe nema nutrition; Ingredient nema kanonski food ID, jestivi udeo ili gram conversion. normalizeUnit ne pretvara volumen u masu bez gustine. AI trenutno vraća recept, ne proverene nutritivne podatke.

**Predložena izmena:**
[
  "Predložiti NutrientFact(provider, datasetVersion, foodId, nutrientId, amount, unit, basisMassG, foodState, retrievedAt, license, sourceUrl). IngredientFoodBinding je korisnički potvrđena veza ingredientId->foodId i opciona density/edibleFactor sa svojim poreklom.",
  "NutrientEstimate(recipeRevisionHash, servings, nutrientTotals, perServing, coverageByNutrient, knownMassG, unmatchedIngredientIds, unknownMassIds, methodVersion). Sumirati massG/basisMassG*amount; tek zatim deliti potvrđenim servings. Nepoznat podatak nije nula; navesti broj pokrivenih sastojaka i masenu pokrivenost samo ako je ukupna masa poznata.",
  "Source-published nutrition iz Recipe JSON čuvati kao reported claim uz basis/yield i URL, odvojeno od izračunatog. AI može predložiti food match preko AIRouter; korisnik potvrđuje; AI broj nikada ne postaje NutrientFact. Ne tvrditi cooked retention ili water-loss korekciju bez metode/podataka.",
  "FoodData Central je kandidat sa CC0 podacima i key-protected API; provider health/version probe i lokalni cache. Bez ključa/429/offline koristiti već potvrđene keširane fact-ove ili \"Nema dovoljno podataka\"; integraciju ne obećavati pre adapter testa."
]

**Zavisnosti:** F002, G-SCHEMA, G-PROVENANCE

**Male vertikalne celine:**
1. Ručno potvrđena 2 food bindings + lokalni fixture facts -> tačan per-serving proračun.
2. Source metadata i coverage u RecipeView -> cache kroz repository/outbox.
3. Opcioni FDC adapter -> capability/offline/429 -> verzionisanje procene.

**Kriterijumi prihvatanja:**
- [ ] 200 g sastojka sa 10 g proteina/100 g + 100 g sa 5 g/100 g daje 25 g ukupno, 12.5 g za 2 porcije.
- [ ] Dodavanje nepoznatog ulja daje partial coverage i ne ostavlja oznaku kompletno; ml bez gustine ne tretira se kao g.
- [ ] Promena sastojka/yield-a invalidira derived estimate; izvorna tvrdnja ostaje vidljivo odvojena.

**Verifikacija pri implementaciji:**
- [ ] Domain test-first jedinice mg/g/kcal/kJ, per100g/basis, non-finite, zero servings, known zero vs missing nutrient i coverage denominator unknown.
- [ ] Fake provider za 404/429/offline/stale dataset i potvrdu pogrešnog food match-a; bez stvarnog API ključa.
- [ ] Recipe serialization/migration + dva naloga RLS i prikaz masene naspram brojevne pokrivenosti.

**Detaljni dokazi:** [stream F](../research/streams/F.md).

## F047 — Dnevnik kuvanja

**Vlasnik:** stream E. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart: Ratings ima recipeId,stars,isComfortFood,comment,cookedAt,userId, ali nema cooking snapshot/result/photo. RecipeVersion u lib/domain/recipe_version.dart je stanje pre izmene, ograničeno na 30 verzija u RecipeRepository.maxVersions; nije dnevnik.

**Predložena izmena:**
[
  "CookingLog {id,userId,householdId,sessionId?,recipeId?,mealEntryId?,recipeSnapshot,servings,cookedAt,result,note,photoRefs,timingSummary?}; lični vlasnik, read/write samo vlasniku u prvoj verziji.",
  "Ratings ne duplirati: dodati optional cookingLogId uz postojeće polje ocene i definisati jedan autoritativni rezultat. Stare ocene ostaju ocene; ne predstavljati ih kao potpuno dokumentovano kuvanje. Brisanje recepta ne briše lični log bez eksplicitne odluke korisnika."
]

**Zavisnosti:** G-SYNC, F008

**Male vertikalne celine:**
1. Ručni log bez sesije i slika: datum, rezultat, napomena, snapshot.
2. Završetak sesije pravi najviše jedan log; optional veza na postojeću ocenu i plan.
3. Privatna fotografija i uredan delete/export; legacy rating prikaz sa jasnim poreklom.

**Kriterijumi prihvatanja:**
- [ ] Dva kuvanja istog recepta daju dva zapisa sa sopstvenim datumima; edit/restore recepta ne menja log.
- [ ] Offline save plus retry čuva jedan ID; novi uređaj preuzima isti zapis.
- [ ] Lična beleška nije vidljiva drugom članu po default-u; ne troši se ostava prilikom save-a.

**Verifikacija pri implementaciji:**
- [ ] Repository fake clock i outbox rollback; dupli completion, stara ocena bez sessionId, obrisan recept.
- [ ] Dva naloga + household peer RLS test: privatnost i grantovi.
- [ ] UI ručni unos/prošlost, photo failure, offline restart; regression RecipeRepository.delete i setCooked.

**Detaljni dokazi:** [stream E](../research/streams/E.md).

## F048 — Sezonski izbor

**Vlasnik:** stream A. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
No region/season ingredient calendar in lib/domain/recipe.dart or database.dart; mealPlanSystemPrompt broadly mentions Serbian supermarkets but has no seasonal evidence.

**Predložena izmena:**
SeasonCalendarV1(id, regionCode, publisher, sourceUrl, sourceRevision, license, reviewedAt, monthRanges, canonicalIngredientIds). Start manually curated and independently licensed Serbian region data; no claimed dataset collected in this pass. Seasonal scoring is a soft preference after hard rules, never availability or freshness fact. Preserve date and region of reason; offline uses last reviewed dataset.

**Zavisnosti:** F002, G-RULES, G-PROVENANCE

**Male vertikalne celine:**
1. Define versioned calendar and pure month-wrap lookup with synthetic data.
2. Validate a region-specific dataset license/source before shipping real entries.
3. Add opt-in regional preference, local cache and bounded scoring reason.

**Kriterijumi prihvatanja:**
- [ ] Fixture spanning Nov-Feb matches Nov/Jan but not June; unsupported region produces no seasonal bonus.
- [ ] Reason shows region, month and calendar version/source; missing data produces no invented claim.
- [ ] Seasonality never outranks a hard exclusion or substitutes for pantry stock.

**Verifikacija pri implementaciji:**
- [ ] Synthetic month/hemisphere/region tests and offline cache/version update.
- [ ] Data review checks licensing, source date, canonical mapping and no unsupported Serbian coverage claim.

**Detaljni dokazi:** [stream A](../research/streams/A.md).

## F049 — Sken i izdvojeni tekst uporedo

**Vlasnik:** stream F. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
FromPhotoScreen _pick smanjuje sliku u JPEG, RecipeAI.fromImage daje strukturisani Recipe, AiRecipePreview prikazuje PhotoScan i recept. Nema OCR raw teksta/spans. Čuva se resize JPEG, ne izvorni original; preview trenutno koristi BoxFit.cover.

**Predložena izmena:**
[
  "Proširiti postojeći preview sa ScanExtraction(imageAssetId, rawText?, rawLines, fieldBindings, parseIssues, provider, processedAt). originalImage i processedPreview moraju imati različite asset role; postojeće JPEG slike označiti kao processedSource, bez obećanja nepostojećeg originala.",
  "Prvo omogućiti contain/zoom fotografiju i uređivanje parsiranog recepta; opcioni extractedText preko postojeće RecipeAI/AIRouter fasade. Ako model ne daje tekst/koordinate prikazati \"Izdvojeni tekst nije dostupan\"; ne izmišljati bounding boxes ni confidence procenat.",
  "Issue sadrži ingredient ordinal/stableId, raw token, razlog missing/invalid/ambiguousQuantity, korisničko razrešenje. Parser ne sme tiho izgubiti raw \"1 1/2\" ili nečitko polje pretvarajući ga u null bez objašnjenja. Raw OCR nije dokaz tačnosti; compare/edit/save ostaje potvrda."
]

**Zavisnosti:** G-PROVENANCE, G-SCHEMA

**Male vertikalne celine:**
1. Postojeći photo preview -> contain/zoom + uporedni/switch prikaz na telefonu, bez novih AI poziva.
2. Proširiti extraction response sa raw lines i issues -> edit/confirm -> sačuvati kroz postojeći repository.
3. Asset role original/processed + opcioni izvornik uz izbor korisnika i migraciju.

**Kriterijumi prihvatanja:**
- [ ] Na 390 px dostupni su izvor i recept pre čuvanja; na 1000 px dve čitljive kolone; 2x tekst bez overflow.
- [ ] Ulaz "1 1/2 šolje" ili "? g" ima raw token i zahtev za proveru, nikad proizvoljnu ocenu 87%.
- [ ] Odbacivanje/ponovni AI odgovor ne čuva stari draft ili slike; potvrđene ispravke ostaju posle offline otvaranja.

**Verifikacija pri implementaciji:**
- [ ] Widget tests proširiti test/features/recipes/from_photo_screen_test.dart sa contain/zoom i edit/save/cancel, race stale request odgovorom.
- [ ] Domain extraction parse tests za missing/null/negative/NaN/fraction i synthetic OCR lines; fake AIRouter malformed JSON retry.
- [ ] Photo resize/recipe repository/photo sync regresije; potvrditi da stari JPEG nije označen kao original.

**Detaljni dokazi:** [stream F](../research/streams/F.md).

## F050 — Oprema koju posedujem

**Vlasnik:** stream B. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/domain/shopping_source.dart: RecipeSnapshot sadrži sastojke i tekstualne korake, bez strukturisanih resursa; PlanRequest nema opremu.

**Predložena izmena:**
HouseholdEquipment{equipmentType,count,capabilities,confirmedAt}; RecipeEquipmentRequirement{type,count,capability?,alternativeGroup?}. Evaluator required/optional/alternative sa unknown stanjem; ne pretpostavljati da reč rerna u tekstu znači potvrđenu opremu. Snapshot zamrzava odobrene zahteve; bez kontrole uređaja.

**Zavisnosti:** G-SYNC, G-EQUIPMENT-METADATA

**Male vertikalne celine:**
1. Ručno unesi kućnu opremu i zahteve jednog recepta.
2. Objasni nedostajuću opremu i alternative u detalju/pretrazi.
3. Primeni isti evaluator na PlanDraft i sačuvaj potvrđeni izbor alternative.

**Kriterijumi prihvatanja:**
- [ ] Rerna=0 blokira recept koji zahteva rernu; blender opciono ne blokira.
- [ ] Alternativa blender OR seckalica prolazi kad postoji jedan odgovarajući resurs; AND zahteva oba.
- [ ] Nepoznati zahtevi ne prikazuju Oprema proverena; promena opreme ponovo proverava nacrt.

**Verifikacija pri implementaciji:**
- [ ] Domain AND/OR, count 0/1/2, capability temperature nepoznata.
- [ ] Repository household izolacija i snapshot nakon izmene biblioteke.
- [ ] Widget bez opreme/unknown i pristupačno objašnjenje; nema Bluetooth/API poziva.

**Detaljni dokazi:** [stream B](../research/streams/B.md).

## F051 — Temperature i režim rerne

**Vlasnik:** stream E. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/domain/recipe.dart: Recipe.steps je tekst; nema strukturisanog oven mode ili jedinice temperature. RecipeView prikazuje tekst bez konverzije. lib/domain/shopping_demand.dart normalizuje mere sastojaka, nije temperaturni model.

**Predložena izmena:**
[
  "OvenSetting {sourceValue,sourceUnit,celsius,mode:static|fan|grill|unknown,confirmedByUser}; izvorna vrednost ostaje očuvana. Čista funkcija temperature conversion; režim nije isto što i jedinica.",
  "UI prikazuje izvor i opcionu konverziju; ventilator/statički režim se ne preračunava bez eksplicitnog izbora i prikaza promene. Parsiranje teksta daje samo draft."
]

**Zavisnosti:** G-STEP

**Male vertikalne celine:**
1. Pure conversion + value validation i prikaz uz tekst legacy koraka.
2. Ručno strukturisanje oven setting-a i source provenance.
3. Predlog iz parsera uz potvrdu i ugovor za F078.

**Kriterijumi prihvatanja:**
- [ ] 180 °C prikazuje 356 °F; 350 °F = 176.666… °C, prikaz 177 °C uz očuvan original.
- [ ] Prelaz °C/°F ne menja fan/static; nepoznat režim ostaje Nije naveden.
- [ ] Negativna/ne-finite temperatura ili van opsega izabranog uređaja ne može se poslati.

**Verifikacija pri implementaciji:**
- [ ] Unit test 0/32,100/212,180/356 i round-trip tolerancija 1e-9; zaokružiti samo UI.
- [ ] Parser fixtures 180°C ventilator, 350 F, broj bez jedinice i grill bez temperature.
- [ ] Widget potvrda izmene, očuvan original u snapshot-u i export round-trip.

**Detaljni dokazi:** [stream E](../research/streams/E.md).

## F052 — Paralelna priprema

**Vlasnik:** stream B. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
lib/domain/shopping_source.dart: RecipeSnapshot.steps je List<String>, bez trajanja pojedinačnih koraka/zavisnosti; MealPlan nema raspored resursa. Sam tekst nije dovoljan za pouzdan raspored.

**Predložena izmena:**
CookTask{id,preparationId,dependsOn[],durationMinutes?,attention=active|passive,resources[{type,quantity,capability}],earliest?,latest?}; PreparationSchedule{inputFingerprint,tasks,startTimes,conflicts,confirmedAt?}. Prvo DAG i deterministički bounded list scheduling, ne obećanje optimuma. Aktivni zadaci dele human-attention kapacitet; pasivni korak oslobađa pažnju ali može držati rernu. AI ekstrakcija ide samo u pregled.

**Zavisnosti:** F034, F050, F012, G-TIME

**Male vertikalne celine:**
1. Ručno potvrdi DAG i resurse za dva mala recepta.
2. Izračunaj predlog bez preklapanja i prikaži konflikte/unknown trajanja.
3. Potvrdi raspored i ručno pomeri korak uz revalidaciju zavisnika.

**Kriterijumi prihvatanja:**
- [ ] Dva zadatka rerne po 30 min sa kapacitetom 1 daju najmanje 60 min zauzeća; nema preklapanja.
- [ ] Dva aktivna zadatka po 10 min za jednog kuvara daju 20 min; pasivnih 30 može teći uz aktivnih 10.
- [ ] Ciklus ili nepoznato trajanje daju nepotpun predlog, bez poruke da je završetak garantovan; promena input-a uklanja staro odobrenje.

**Verifikacija pri implementaciji:**
- [ ] Domain topološki red/ciklus, resource interval disjointness, AND preduslovi i deadline nemoguć.
- [ ] Unapred izračunat primer A aktivno 10->rerna 30 i B aktivno 10: završetak 40 min sa B tokom rerne.
- [ ] Widget potvrda i pomeranje, fake clock; bez pokretanja pametnih uređaja.

**Detaljni dokazi:** [stream B](../research/streams/B.md).

## F053 — Glasovno vođenje kuvanja

**Vlasnik:** stream E. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
RecipeView nema aktivni korak ni govor. pubspec.yaml nema speech/TTS zavisnost. lib/features/recipes/keep_screen_on.dart je postojeći screen-only wake lock; ne održava mikrofon ili background izvršavanje.

**Predložena izmena:**
[
  "CookingSpeechController koristi isti SpeechInput kao F016, ali zasebnu gramatiku Command {next,previous,repeat,startTimer,pauseListening}; SpeechOutput.probe(sr) proverava TTS voice odvojeno od ASR.",
  "Push-to-talk, vidljiv indikator slušanja i ručna dugmad; TTS pauzira ASR da sopstveni glas ne postane komanda. Start timer bez jasnog trajanja/koraka otvara potvrdu; glas nikad ne šalje komande rerni."
]

**Zavisnosti:** F008, F009, F016, G-SPEECH

**Male vertikalne celine:**
1. Tekstualne command fixtures i controller nad cooking state machine.
2. Srpski TTS capability + ponovi; nezavisni fallback bez TTS.
3. Push-to-talk ASR, echo suppression, dupli callback i lifecycle otkazivanje.

**Kriterijumi prihvatanja:**
- [ ] Sledeći korak pomera tačno jedan korak; ponovi ne menja stanje.
- [ ] Pokreni tajmer uz dve moguće vrednosti pita koju; final callback replay ne pravi dva tajmera.
- [ ] Odlazak u background zaustavlja snimanje; ručna navigacija radi bez dozvola i bez mreže.

**Verifikacija pri implementaciji:**
- [ ] Fake speech/TTS loopback: dok se čita nema prijema komandi; generation/session token odbacuje stari rezultat.
- [ ] Corpus komandi: dijakritici, buka, prekid, nepoznata komanda, poslednji korak i nedostajući timer duration.
- [ ] Android/iOS/macOS probe na uređaju: locale/voice, audio interruption i hands busy; bez tvrdnje o stalnom slušanju u pozadini.

**Detaljni dokazi:** [stream E](../research/streams/E.md).

## F054 — Lično stvarno vreme pripreme

**Vlasnik:** stream E. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
Recipe.prepMinutes u lib/domain/recipe.dart je jedan opcioni broj; RecipeSnapshot ga kopira. Nema aktivnih intervala ili ličnih agregata u lib/data/database.dart. Ratings.cookedAt je datum, ne trajanje rada.

**Predložena izmena:**
[
  "CookingActivityInterval {id,sessionId,startElapsed,endElapsed?,kind:active|paused|unclassified,bootId}; zbir aktivnih intervala odvojiti od ukupnog trajanja i vremena čekanja.",
  "PersonalTimingSummary grupisati po userId + recipe fingerprint + servings band + equipment; tek od 3 potvrđene uporedive sesije prikazati min/max i N. Background interval je unclassified dok ga korisnik ne razvrsta."
]

**Zavisnosti:** F008, F047, F009

**Male vertikalne celine:**
1. Ručno Počni rad/Pauza i monotonic interval tests.
2. Resume review neklasifikovanih intervala i čuvanje uz log.
3. Agregat 3+ potvrđene sesije, raspon i izuzimanje nepotpunih.

**Kriterijumi prihvatanja:**
- [ ] Rad 10 min, pauza 5, rad 7 daje aktivno 17 i ukupno 22 min.
- [ ] Potvrđene sesije 17,20,25 min prikazuju 17–25 min (3 kuvanja); sa 2 nema ličnog raspona.
- [ ] Reboot/neklasifikovan background ne ulazi u aktivno vreme; promenjene porcije/oprema ostaju zasebna grupa.

**Verifikacija pri implementaciji:**
- [ ] Fake continuous clock sa wall-clock skokom i preklapanjem intervala; nijedan interval se ne broji dvaput.
- [ ] Query fixtures različitih users/fingerprints/servings i delete log invalidation.
- [ ] Device background/resume/process death + ekran za potvrdu intervala; ne porediti vreme UI tick-ova.

**Detaljni dokazi:** [stream E](../research/streams/E.md).

## F055 — Pomoć o tekućem koraku

**Vlasnik:** stream E. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
lib/ai/recipe_ai.dart: RecipeAI.refine pravi novi Recipe; lib/features/recipes/recipe_chat_screen.dart je uređivanje recepta, ne privremena cooking pomoć. lib/ai/ai_router.dart: AIRouter.run već obezbeđuje fallback i JSON parse/retry.

**Predložena izmena:**
[
  "CookingHelpAI.ask({snapshot,currentStepId,confirmedConstraints,question}) -> StepHelp {answerSr,clarification?,limits}; koristiti AIRouter i strict JSON parser koji baca FormatException.",
  "Odgovor ostaje u sesiji; nema RecipeRepository.update, promene ograničenja ili device komandi. Budući trajni izmeni tok mora zasebno kroz postojeći preview/refine. Šalju se samo potrebni podaci, bez BLE identifikatora/audio/log fotografija."
]

**Zavisnosti:** F008, F028, G-AI

**Male vertikalne celine:**
1. Context builder + JSON parsing tests i fake router.
2. Pitanje/odgovor u cooking ekranu bez trajne izmene.
3. Error/retry/cancel kada se promeni sesija ili korak; prikaz originalnog koraka uz odgovor.

**Kriterijumi prihvatanja:**
- [ ] Prompt sadrži tačan snapshot i tekući korak, ne kasnije izmenjen recept biblioteke.
- [ ] Nijedan uspeh/greška help-a ne pravi recipe version, outbox izmenu ili device write.
- [ ] Offline/pružalac nedostupan prikazuje Pomoć trenutno nije dostupna; cooking navigation/timers nastavljaju.

**Verifikacija pri implementaciji:**
- [ ] Fake ChatClient hvata kontekst; malformiran JSON, fallback exhaustion i format retry.
- [ ] Spy RecipeRepository/oven adapter potvrđuje nula write poziva.
- [ ] Late response za korak A posle prelaska u B označiti odgovor za A ili odbaciti; odjava briše transient context.

**Detaljni dokazi:** [stream E](../research/streams/E.md).

## F056 — Glasanje za predloge jela

**Vlasnik:** stream D. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/domain/meal_plan.dart i lib/data/meal_plan_repository.dart drže planove; lib/domain/account.dart i server household_members još nemaju višekorisnički tok. U lib/data/database.dart nema poll/ballot tabele.

**Predložena izmena:**
[
  "MealPoll(id,householdId,planId?,closesAt,status open|closed,revision), PollOption(id,pollId,recipeId?,recipeSnapshot,constraintVersion,eligibility), Ballot(pollId,voterUserId,optionId,revision), unique(pollId,voterUserId) za jedan glas. Autor plana potvrđuje izbor; nije automatska izmena zaključanog obroka. Eligibility se ponovo proverava po važećim obaveznim ograničenjima pre primene."
]

**Zavisnosti:** F011, G-SCHEMA, G-PLAN-CONSTRAINTS

**Male vertikalne celine:**
1. Otvoren poll sa snapshot opcijama i jednim glasom po članu.
2. Zatvaranje po serverskom vremenu i pregled rezultata.
3. Potvrđena primena uz ponovnu proveru ograničenja i zaključavanja.

**Kriterijumi prihvatanja:**
- [ ] Promena glasa zamenjuje prethodni; replay ne povećava broj glasova.
- [ ] Najviše glasova ne dozvoljava jelo koje krši obavezno ograničenje; nerešen rezultat traži odluku.
- [ ] Offline glas posle zatvaranja je odbijen uz vidljivo stanje, bez retroaktivne izmene rezultata.

**Verifikacija pri implementaciji:**
- [ ] Fake clock: tik pre/tačno na/posle closesAt; dva uređaja istog glasača i revizije.
- [ ] RLS član vidi samo poll svog domaćinstva, piše samo svoj ballot; test zaključanog plana i promene alergena nakon glasanja.
- [ ] Widget „Glasanje”, „Zatvoreno”, „Potvrdi izbor”; 3 člana, 2:1 rezultat, zatim nevažeća pobednička opcija.

**Detaljni dokazi:** [stream D](../research/streams/D.md).

## F057 — Ko jede obrok

**Vlasnik:** stream B. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/domain/meal_plan.dart: PlannedMeal.servings podržava broj porcija po unosu; MealPlan.defaultServings je podrazumevana vrednost. Ne postoje prisutni/gosti, niti pouzdan broj članova u ovom modelu.

**Predložena izmena:**
MealAttendance{entryId,memberIds[],guestCount,servingOverrides?,revision}; imena samo potvrđenih članova, gosti kao broj. Predložen broj porcija iz prisutnih uz eksplicitno prihvatanje; ne zaključivati privatne profile drugih članova. Uz F012 attendance menja konzumaciju, a ne automatski prinos već skuvane pripreme.

**Zavisnosti:** G-SYNC, F011, F012

**Male vertikalne celine:**
1. Ručno broj prisutnih i gostiju uz postojeće changeServings.
2. Izbor članova sa household proverom i pregledom novih porcija.
3. Raspodela na novu pripremu/ostatak uz proveru prinosa i stale revision.

**Kriterijumi prihvatanja:**
- [ ] 2 člana +1 gost predlažu 3 porcije; odbacivanje ostavlja stare porcije.
- [ ] Promena 2->3 za svežu pripremu sa 200 g za 2 daje 300 g; 0 prisutnih traži skip/away, ne nevažeće 0 servings.
- [ ] Dodavanje gosta uz ostatak bez viška označava nedostatak i ne pravi sirovinsku nabavku za već skuvan ostatak.

**Verifikacija pri implementaciji:**
- [ ] Domain attendance granice i eksplicitni serving override; bez automatskog čitanja privatnih profila.
- [ ] Repository bivši/tuđi član odbijen; konflikt istovremenog attendance i prinosa.
- [ ] Widget gosti bez naloga, prikaz ukupno/porcije i regresija changeServings zaštite skuvanog.

**Detaljni dokazi:** [stream B](../research/streams/B.md).

## F058 — Zašto je ovo predloženo

**Vlasnik:** stream A. **Faza:** P1. **Status:** planirano.

**Postojeće stanje:**
lib/ai/meal_plan_ai.dart constructs SlotProposal(title, libraryRecipeId/draftRecipeKey); lib/domain/meal_plan.dart:PlanDraft has no score evidence. AIResult.attempts tracks technical attempts, not user recommendation reasons.

**Predložena izmena:**
RecommendationEvidenceV1(ruleId, inputRevision, metric, value, unit, sourceIds, observedAt) and RecommendationScoreV1(components, rankKey, rulesVersion). Pure scorer emits typed evidence; Serbian formatter renders only present facts. Explain available amount, expiry, duration and cooked history using respective adapters. Technical provider attempts remain separate; model prose cannot become factual evidence.

**Zavisnosti:** F004, G-RULES

**Male vertikalne celine:**
1. Add score/evidence value objects and deterministic reason formatter.
2. Show a reason sheet for F004/F030; enrich with F005/F035/F048 as available.
3. Persist evidence with draft snapshot and revalidate on approval; show changed-input warning.

**Kriterijumi prihvatanja:**
- [ ] 400 g demand/250 g supply reason reports exactly 250 g covered and 150 g missing.
- [ ] No duration/expiry/history data yields no corresponding statement.
- [ ] Score order reconstructs exactly from components; stock edit marks evidence stale until refreshed.
- [ ] Explanations in Serbian Latin show reference date rather than unsupported „sveže” claims.

**Verifikacija pri implementaciji:**
- [ ] Hand-computed score golden, absent-field and rule-version tests.
- [ ] Widget stale evidence/refreshed rank; fake AI cannot inject new reason type or external URL.

**Detaljni dokazi:** [stream A](../research/streams/A.md).

## F059 — Widget Danas

**Vlasnik:** stream F. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
PlanScreen i shopping repositories postoje; native targeti imaju AppDelegate/MainActivity i manifests, ali nema widget extension/provider fajlova ni widget dependency u pubspec.

**Predložena izmena:**
[
  "Predložiti WidgetSnapshot(v1, accountScopeFingerprint, civilDate, timezone, meals[], remainingShoppingCount, generatedAt, lastSyncedAt, deepLink). Čita iz drift preko istih repositories, piše minimalnu projection u app-group/native shared storage; native widget ne dobija Supabase ni AI ključeve.",
  "WidgetProjectionService regeneriše posle potvrđene lokalne promene, sync download-a, timezone/date/resume i sign-out. Dati naslov \"Ažurirano …\"; generatedAt nije lastSyncedAt. Stari datum jasno označiti, bez lažne garancije minutnog realtime osvežavanja.",
  "Platform capability probe: target extension/provider registrovan, podržana OS verzija, shared container spreman; neuspeh -> \"Widget nije dostupan na ovom uređaju\" i in-app Danas. Početni widget read-only; tap otvara autorizovanu rutu, bez direktnog check/uncheck iz native skladišta."
]

**Zavisnosti:** G010, G-DEVICE

**Male vertikalne celine:**
1. Čista projection za jedan dan + fake native bridge -> local event refresh.
2. Android provider/Glance vertikala i deep link -> real-device test.
3. iOS/macOS WidgetKit zasebno po platformi -> timeline/entitlements -> signout purge.

**Kriterijumi prihvatanja:**
- [ ] Lokalna promena obroka daje novu projekciju i vreme osvežavanja bez interneta.
- [ ] Signout/switch account uklanja tuđe nazive iz shared storage; novi nalog ne vidi stari snapshot.
- [ ] Prelaz ponoći i Europe/Belgrade DST ne prikazuju jučerašnji dan kao današnji; OS odlaganje osvežavanja ima vidljiv timestamp.

**Verifikacija pri implementaciji:**
- [ ] Unit projection clock/timezone injection; count koristiti istu definiciju preostale nabavke kao ShoppingRepository, bez nove računice.
- [ ] Widget/deep-link test signed out, deleted meal i missing account; native bridge fake denied/unavailable.
- [ ] Ručni uređaj/emulator test svake omogućene platforme: pin, resize, OS process kill, restart, offline, midnight, signout; nije izvršen u istraživanju.

**Detaljni dokazi:** [stream F](../research/streams/F.md).

## F060 — Pretplata na kalendar

**Vlasnik:** stream B. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/domain/plan_calendar.dart: CivilDate čuva datum bez zone; lib/data/meal_plan_repository.dart: fingerprint je lokalni JSON plan+entries, ne ICS UID/revision; nema feed ugovora u pregledanim planning fajlovima.

**Predložena izmena:**
CalendarSubscription{id,householdId,tokenDigest,selectedPlanIds,fieldPolicy,enabled,createdAt}; odvojeni server read-only feed projektuje potvrđene sinhronizovane obroke. UID=opaque subscriptionId+stable entryId@tavli; SEQUENCE iz monotone eventRevision, ne fingerprint ili vreme poll-a. Podrazumevano celodnevni DATE, DTEND sledeći datum; vremenski događaj samo sa potvrđenim vremenom/zonom. Snimak odobrenog obroka je izvor naziva, ne promenljiv bibliotečki recept.

**Zavisnosti:** G-PLAN-REV, G-FEED, G-TIME

**Male vertikalne celine:**
1. Čista ICS projekcija i fixture serializer sa tačnim datumima/escaping/folding.
2. Autentifikovano kreiranje/rotacija/opoziv linka i scoped feed read sa ograničenim poljima.
3. Probe javnog HTTPS endpoint-a i korisnikovog kalendarskog klijenta; dokumentuj eventualno osvežavanje i tombstone politiku.

**Kriterijumi prihvatanja:**
- [ ] Dva poll-a istog obroka imaju isti UID i SEQUENCE; pomeranje datuma menja SEQUENCE, zadržava UID.
- [ ] Rotacija ili opoziv odmah odbija stare linkove na serveru; već preuzete kopije se ne mogu izbrisati sa tuđeg kalendara.
- [ ] Srpski UTF-8, zarez, tačka-zarez, kosa crta i newline se bezbedno serijalizuju; redovi najviše 75 okteta uz pravilno folding.
- [ ] Feed ne daje sastojke, privatne profile, attendee imena, backend credential ili pravo pisanja; offline nesinhronizovana izmena jasno čeka objavu.

**Verifikacija pri implementaciji:**
- [ ] Golden ICS i roundtrip nezavisnim parserom u budućim testovima; DATE 31.12->01.01, DST timed opciono.
- [ ] Local server test dva household-a, disabled/rotated/unknown digest, GET bez write efekta, bez URL tokena u logovima.
- [ ] Deletion tombstone STATUS:CANCELLED stabilan UID i veći sequence; stvarni Google/Apple klijenti uslovni smoke, ne tvrdnja implementirane integracije.

**Detaljni dokazi:** [stream B](../research/streams/B.md).

## F061 — Poređenje nacrta

**Vlasnik:** stream B. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/features/planning/plan_generation.dart: PlanGenerationState ima jedan draft; MealPlanAI.propose ne piše podatke; MealPlanRepository.approve već predstavlja tačku potvrde.

**Predložena izmena:**
PlanScenarioSet{requestSnapshot,baseFingerprint,inventoryFingerprint,priceSnapshotId,timingVersion,candidates[2..3]}; ScenarioMetrics{knownCost?,currency,coverage,activeMinutes?,shoppingTripsAssumptions}. Sve alternative koriste istu zalihu/cene/pravila kao nezavisne simulacije, bez rezervacija. Broj odlazaka nije broj artikala: zahteva eksplicitnu pretpostavku termina/prodavnica; bez nje Nepoznato.

**Zavisnosti:** G-PLAN-REV, G-DEMAND, F034, F018

**Male vertikalne celine:**
1. Dva ručno sastavljena nacrta i isti deterministički kalkulator metrika.
2. Poređenje pokrivenosti i pretpostavki na telefonu/široko; opcioni treći AI nacrt kroz AIRouter.
3. Izaberi jedan i pozovi postojeći approve jednom, ostale odbaci.

**Kriterijumi prihvatanja:**
- [ ] Tri scenarija rezervišu 0 zalihe i stvaraju 0 izvora pre potvrde; posle potvrde samo izabrani postoji.
- [ ] Scenariji sa 80% i 100% pokrivenosti cena ne prikazuju nepotpun niži zbir kao dokaz da je jeftiniji.
- [ ] Cena 2×100 RSD i 1×150 RSD daje 200 i 150 samo pod istim osnovama; RSD i EUR se ne sabiraju bez potvrđenog kursa.

**Verifikacija pri implementaciji:**
- [ ] Pure evaluator identični ulazi=>identične metrike; zaliha 100 g simulirana zasebno po scenariju.
- [ ] Repository stale plan/inventory/cene traže novi pregled; dupli confirm operationId stvara jedan plan.
- [ ] Fake AI failure zadržava spremne alternative; widget tabovi 2/3 scenarija i unknown vreme/odlasci.

**Detaljni dokazi:** [stream B](../research/streams/B.md).

## F062 — Poništi ceo plan

**Vlasnik:** stream B. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/meal_plan_repository.dart: approve/_edit/removeMeal rade transakciju i reconcile, fingerprint proverava lokalni plan+entries. Nema istorije agregata; lib/data/database.dart: ShoppingItems.purchaseProvenanceJson čuva poreklo kupovine.

**Predložena izmena:**
PlanOperation{id,planId,householdId,baseRevision,resultRevision,beforeImage,afterImage,undoOf?,status}; undoLatest(expectedRevision) pravi kompenzacionu komandu, ne vraća celu bazu. beforeImage obuhvata plan, entry identitete/snimke, pripreme i veze, pravila/attendance u agregatu. Ponovo izvedi otvorenu potražnju kroz reconcile; kupljene/ručne stavke, potvrđena potrošnja i istorija ostaju činjenice. Ne briši recepte automatski čak i ako ih je approve napravio.

**Zavisnosti:** G-PLAN-REV, G-SYNC, G-DEMAND

**Male vertikalne celine:**
1. Zabeleži before/after jedne zamene unosa u istoj lokalnoj transakciji.
2. Poništi poslednju odobrenu agregatnu izmenu uz pregled razlike i preuskladjivanje potražnje.
3. Proširi pokriće na batch/template/leftover operacije i server CAS/idempotentni replay.

**Kriterijumi prihvatanja:**
- [ ] Potreba 300->400 g, kupljeno 200 i ostava 100: undo na 300 daje 0 preostalo i zadržava kupovinu 200; pri ponovnom povećanju opet 100.
- [ ] Tuđa novija izmena ili potvrđeno jedenje/potrošnja posle operacije blokiraju automatsko vraćanje i nude pregled konflikta.
- [ ] Retry istog undo operationId ne pravi drugi undo niti novi izvor; revision monotono raste i pri undo-u.

**Verifikacija pri implementaciji:**
- [ ] Repository transaction fault između restore i reconcile vraća sve lokalne upise/outbox; istorija kupovine byte-identična.
- [ ] Dva uređaja undo expectedRevision=N: jedan uspeva, drugi dobija konflikt bez prepisivanja.
- [ ] Domain povezani ostaci ne postaju siročad; promena nedelje obnavlja logički isti izvor bez drugog pokrića.
- [ ] Regresije test/data/shopping_repository_test.dart i test/data/meal_plan_repository_test.dart; ne koristiti recipe-version undo kao zamenu.

**Detaljni dokazi:** [stream B](../research/streams/B.md).

## F063 — Više nezavisnih domaćinstava

**Vlasnik:** stream D. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/domain/account.dart::Account ima tačno jedno domaćinstvo; lib/account/account_api.dart::fetch limit(1), lib/account/auth_controller.dart::accountScopeProvider izvodi taj jedan scope. lib/data/database.dart::Accounts ima householdId a SyncCursors key je accountId+entity. lib/sync/sync_remote.dart::fetchSince se oslanja na RLS i ne filtrira aktivno domaćinstvo. Repozitorijumi već filtriraju householdId; to je osnova za proširenje.

**Predložena izmena:**
[
  "Account ostaje identitet, Membership list postaje zaseban cache, SelectedHousehold(userId,householdId) je korisnikov izbor. Postojeći AccountScope se rekreira sa epoch-om; sve async rezultate, odabrani plan i pretplate vezati za epoch, nikad za trenutno promenljivi scope.",
  "Odlučeno: download svih važećih domaćinstava po nalogu sa postojećim account-global cursor-om; pri novom članstvu obavezan poseban full bootstrap tog household-a i entiteta, jer stari updated_at ne bi prošao globalni cursor. UI bira samo aktivno. Ne prebacivati na household-filtered download bez particionisanja kursora.",
  "Outbox svaki nalog/operacija trajno vezuje originalno householdId, uključujući delete, i radi nezavisno od izabranog ekrana. Membership refresh pri reconnect-u uklanja pristup opozvanom prostoru i zaustavlja njegove upload-e."
]

**Zavisnosti:** F011, G-SCHEMA, G-SYNC

**Male vertikalne celine:**
1. Normalizovati account/membership cache i migrirati postojeće jedino članstvo bez novih praznih domaćinstava.
2. Switcher + reset scoped providera i zaštita od odgovora starog scope-a.
3. Bootstrap novog članstva, opoziv, offline switching i account deletion regresije.

**Kriterijumi prihvatanja:**
- [ ] A→B→A bez mešanja planova, ostave, lista, assets, glasova ili budžeta; ne poslati A pending write u B.
- [ ] Offline dozvoliti izbor ranije keširanog važećeg članstva sa oznakom poslednje provere; novo članstvo traži mrežu.
- [ ] Novo pridruženo domaćinstvo sa zapisima starijim od postojećeg kursora potpuno se preuzme.
- [ ] Brisanje naloga čuva zajednički prostor preostalih članova i rešava poslednjeg vlasnika pre uklanjanja članstva.

**Verifikacija pri implementaciji:**
- [ ] Migration fixture sa starim Accounts redom, starim cursor-om i pending delete; proveriti nepromenjene UUID-jeve i broj redova.
- [ ] Fake transport zadrži A odgovor do prebacivanja u B; potvrditi da se ne pojavi A sadržaj.
- [ ] Local pgTAP tri naloga/dva household-a, član oba, outsider, revoke; pregled supabase/migrations/20261030120700_delete_account.sql i Edge Function solo-household ponašanja.

**Detaljni dokazi:** [stream D](../research/streams/D.md).

## F064 — Privremeni opozivi link bez naloga

**Vlasnik:** stream F. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
Account-required routing i household RLS štite postojeće recepte; nema public share endpoint-a. Recipe source/version DTO uključuje podatke koji nisu automatski primereni javnom deljenju.

**Predložena izmena:**
[
  "Predlog ShareGrant(id, ownerUserId, householdId, recipeId, snapshotRevisionHash, tokenHash, expiresAt, revokedAt, createdAt). Random token >=256 bitova u URL-u prikazati samo pri stvaranju, u bazi hash; server vreme proverava expiry pri svakom zahtevu.",
  "ShareRecipeDTO je eksplicitna allowlist: naslov, potvrđene porcije, sastojci, koraci i posebno odabrana slika/source attribution. Zamrznut snapshot, bez istorije/instruction/answeredBy/email/ostalih recepata/household IDs. Kreiranje linka je online akcija tek po korisnikovom izboru; offline preview i save normalno rade.",
  "Serverse read-only endpoint proverava token+expiry+revocation i vraća samo share DTO; anon nema SELECT na public.recipes. Slike proxy kroz isti grant ili kratkotrajno potpisan URL sa TTL <= remaining grant TTL. No-store response/CDN bypass; stop current access on revoke. Nema automatskog follow/drugih recipe endpoints."
]

**Zavisnosti:** G-SERVER, G-PROVENANCE

**Male vertikalne celine:**
1. Offline pregled tačne allowlist projekcije -> online grant create i jedna read ruta.
2. Expiry/revoke i za sliku -> vlasničko upravljanje linkovima.
3. Anonymous web view bez naloga -> abuse limiting -> accessibility.

**Kriterijumi prihvatanja:**
- [ ] Anonymous token za A otvara samo A snapshot; pokušaj susednog ID/B istorije/household liste daje odbijanje.
- [ ] Tačno na expiresAt i neposredno posle revoke grant više ne vraća recept niti nove image bytes.
- [ ] Privatni recepti ostaju nedostupni anon role i nakon dodavanja share funkcije.
- [ ] UI kaže da ranije preuzetu kopiju nije moguće obrisati kod primaoca.

**Verifikacija pri implementaciji:**
- [ ] Local pgTAP: owner/member/unrelated account/anon za grant i original tables; endpoint clock frozen expired/revoked cases.
- [ ] Fake token store collision, tampering, rate limit i access logs redaction; test URL token se ne loguje.
- [ ] Integration fetch HTML/JSON/image posle revoke i proveriti cache headers; nema stvarnog backend-a u testovima.

**Detaljni dokazi:** [stream F](../research/streams/F.md).

## F065 — Potpuna rezervna kopija i obnova

**Vlasnik:** stream F. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
Drift schemaVersion=5 ima recipes/versions, plans/entries, shopping sources/contributions/allocations, pantry, personal ratings/profiles i lokalne sync tabele. syncEntities je topološki registar, ne backup format. PhotoSync._referenced obilazi recepte/verzije, ne kompletan graf svih snapshot slika.

**Predložena izmena:**
[
  "Predložiti BackupManifest(format=tavli-space, version, appSchemaVersion, exportId, createdAt, scope, completeness, entityCounts, files[path,size,sha256], references, minReaderVersion). ZIP sadrži manifest.json, typed data/*.json i assets/<contentHash>.jpg; nijedan SQL statement iz arhive se ne izvršava.",
  "Obuhvatiti sve korisničke domenske entitete i veze, sačuvanu istoriju do postojeće granice 30, snimke planova/samostalne nabavke, porcije/locked/cooked, pantry confirmations i purchase links/allocations. Lične ocene/profile izvoziti samo za tekućeg korisnika, podatke domaćinstva samo u okviru njegovih prava. \"Potpuna\" označava ovaj ovlašćeni prostor, ne tuđe profile niti ceo Supabase projekat. Lične preference uključuju samo potvrđeni sopstveni profileJson i bezbednu allowlist korisničkih podešavanja; ne eksportovati AppSettings wholesale jer nije klasifikovan kao trajni account format.",
  "Isključiti Auth identitete/sesije/AI i integracione ključeve, Accounts email cache, ModelStatuses, SyncCursors i stari outbox. Outbox se regeneriše iz obnovljenog stanja. Sve asset reference tražiti kroz recepte, verzije i sve ugnježdene snapshots, ne kopirati samo trenutni PhotoSync traversal.",
  "Consistent export barrier: zamrznuti lokalne writes/sync na kratko, uhvatiti snapshot+referentne asset hash-eve, nastaviti aplikaciju, završiti u staging-u. Ako cache nije kompletan, download/images nije gotov ili pending/rejected changes postoje, navesti completeness/pending summary i ponuditi dovršetak; nepotpun izvoz ne nazvati potpunim. Offline moguće arhivirati poznato stanje uz jasno incomplete.",
  "Restore plan(archive,target) radi checksum/version/schema/graph/path preflight pre upisa. Početni target novi prostor/import u ovlašćeno domaćinstvo sa novim ID-jevima i kompletnim ID mapiranjem uključujući JSON reference i personal owner map na tekućeg korisnika; nema reinstalacije tuđeg članstva ili automatskih grant-ova. Replace postojećeg prostora je kasniji eksplicitan destruktivan tok sa pre-backup-om, nikad default.",
  "Journal restoreId i deterministični ID mapping čine retry idempotentnim; staged photos pre transakcije, topološki domenski upisi+nov outbox u transakciji; pri neuspehu nijedan delimičan podatak ne postaje vidljiv. Nova schema zahteva adapter/migration chain; unknown future version -> bez upisa. Asset fajlove po content hash-u proveriti i finalizovati pre DB commit-a; DB transakcija objavljuje reference tek kad svi assets postoje. Failure ostavlja najviše nevidljive orphan assets za cleanup, bez poluobnovljenog vidljivog grafa. Reconcile restore ne sme automatski stvoriti nove plan.confirmed događaje iz F088: event emission se eksplicitno isključuje za restore/import, uz audit restore operacije."
]

**Zavisnosti:** G010, G-PORTABLE, G-SCHEMA, G-SERVER

**Male vertikalne celine:**
1. Versioned manifest i full graph/asset inventory -> export synthetic account -> offline inspect.
2. Preflight dry-run -> novi destination scope -> atomic local restore/outbox i photo staging.
3. Resumable upload/download, completeness i future schemas -> failure recovery.
4. Tek zasebnom specifikacijom dodati replace target i korisnički izbor arhiviranja/enkripcije.

**Kriterijumi prihvatanja:**
- [ ] Fixture sa 2 recepta, 3 verzije, obrokom čiji je recipe obrisan, slikom samo u snapshot-u, pantry receipt vezom i allocation-om vraća iste count-ove i izračun nabavke.
- [ ] Pre/posle restore broj nedostajućih sastojaka isti; primer potreba 300 g, pantry 100 g, kupljeno 200 g ne stvara novu potrebu ni dvostruko pokriće.
- [ ] Truncated/hash mismatch/future version/dangling link/..//symlink prekidaju pre bilo kakvog domenskog upisa.
- [ ] Ponovljeni restoreId ne stvara duplikate; archive ne sadrži auth/API secrets, sync outbox ni tuđe lične profile.
- [ ] Nijedan nepotpun skup assets ne dobija completeness=complete.

**Verifikacija pri implementaciji:**
- [ ] Test-first backup encode/decode/migration sintetičke verzije, assert counts, referential closure i snapshot content hash.
- [ ] Failure injection na svakoj fazi stage/transaction/outbox/upload i retry; fake backend + temp directory, bez hosted backend-a.
- [ ] Local pgTAP sa 2 korisnika i dva domaćinstva: owner mapping, import permissions, anonymous denied; real file ZIP validation i zip bomb.
- [ ] Proširiti test/data/migration_test.dart, test/sync/entities_test.dart, test/data/shopping_repository_test.dart; ne koristiti postojeći toRemote direktno kao trajni format.

**Detaljni dokazi:** [stream F](../research/streams/F.md).

## F066 — Razduživanje zajedničkih troškova

**Vlasnik:** stream D. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart nema Expense/Settlement; lib/data/shopping_repository.dart::_buy čuva kupljene potrebe, bez platioca, učesnika i iznosa. F043 je predložena osnova računa korpe, ne gotov ledger.

**Predložena izmena:**
[
  "Expense(id,householdId,purchaseEventId?,currency,totalMinor,paidBy,revision,status draft|posted|void), ExpenseLine(totalMinor,beneficiaryWeights[]), Share(userId,amountMinor), Settlement(id,from,to,currency,amountMinor,confirmedAt). Lične stavke dodeliti samo tom korisniku; ne bacati ih iz ukupnog plaćenog iznosa. Za više platioca zasebne Payment reda sa sum(payment)=expense total.",
  "Posted dokument je nepromenljiv; ispravka pravi storno/replacement sa sourceExpenseId. Balance=payments-shares+outgoingSettlements-incomingSettlements. Predlog transfera je informativan i nije bankovno plaćanje. Svaka valuta ima zaseban ledger; odlazak člana ne briše dug ili menja istorijske udela."
]

**Zavisnosti:** F011, F043, G-MONEY, G-SCHEMA

**Male vertikalne celine:**
1. Draft trošak sa platiocem, izuzimanjem ličnih stavki i tačnom raspodelom.
2. Posted ledger, saldo i predlog transfera.
3. Potvrđeno poravnanje, storno i audit/idempotency.

**Kriterijumi prihvatanja:**
- [ ] A plati 10001 minor: lično A 2000, zajedničko 8001 sa jednakim težinama A/B/C; shares su A=4667,B=2667,C=2667 po stabilnom member-ID poretku, A saldo +5334, B/C -2667.
- [ ] Svaki događaj ima sum(payments)=sum(shares); suma salda domaćinstva po valuti je 0.
- [ ] Kada B plati A 2667, B saldo je 0, A +2667 i C -2667; duplirani settlementId ništa ne menja.

**Verifikacija pri implementaciji:**
- [ ] Test-first parser i allocator; random/property fixtures: konzervacija minor jedinica, stabilnost pri drugačijem input poretku, nulte težine i rejected all-zero/negative weights.
- [ ] Golden 10001 primer iznad, refund/storno i više platioca; ne izvršavati upstream kod.
- [ ] Local RLS čitanje/sopstvena izmena draft-a/posted zabrana, rollback i replay; widget „Ko je platio”, „Lična stavka”, „Potvrdi poravnanje”.

**Detaljni dokazi:** [stream D](../research/streams/D.md).

## F067 — Slanje korpe online prodavnici

**Vlasnik:** stream D. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/shopping_repository.dart i lib/features/shopping/shopping_screen.dart završavaju na lokalnoj/sinhronizovanoj nabavci. Nema retailer adapter-a, merchant productId ili checkout ugovora u lib/data/database.dart.

**Predložena izmena:**
[
  "RetailerAdapter.probe() vraća unavailable|exportText|exportLink|cartApi sa region, storeBranch, checkedAt, limits i reasons; zahteva dokumentovan podržan interfejs i prava. MerchantMapping(ingredient/productRef,merchantSku,packSize,confidence,confirmedByUser). CartDraft(id,listSnapshotHash,merchantId,branchId,lines,substitutions,quoteExpiresAt,feesMinor?,currency,capabilityVersion).",
  "Najpre prikaži SKU, pakovanja, zamene, cenu i naknade; prenos zahteva izričitu radnju nad pregledanom korpom. submitExport sa idempotencyKey gde ugovor trgovca to podržava; unknown delivery status se proverava pre ponavljanja. Izvoz nije potvrda porudžbine; ne označava isBought ni dopunu ostave. Nema podržanog trgovca potvrđenog u ovom istraživanju."
]

**Zavisnosti:** F018, G-CAPABILITY, G-SCHEMA

**Male vertikalne celine:**
1. Deterministički lokalni tekst/CSV izvoz i ručni product mapping.
2. Fake adapter sa capability probe, preview i zamenama.
3. Jedan stvarni adapter tek kada su prava/API ugovor dokazani; finalni checkout kod trgovca potvrđuje korisnik.

**Kriterijumi prihvatanja:**
- [ ] Nepokriveni artikli i nepoznate naknade su eksplicitni; nepodržan trgovac daje „Izvoz za ovu prodavnicu nije dostupan”.
- [ ] Promena liste ili istek quote-a obavezno poništava staru potvrdu pregleda.
- [ ] Izvoz ili timeout ne menja bought/expense/pantry; nijedna porudžbina nije automatski postavljena.

**Verifikacija pri implementaciji:**
- [ ] Fake probe disabled/region mismatch/auth required; unit map 1200 g potrebe na 500 g SKU daje 3 pakovanja i 300 g viška.
- [ ] Widget potvrda tačnog snapshot-a, unavailable zamena, quote expiry i naknade.
- [ ] Contract fixtures za export payload; request timeout nakon slanja i sigurni replay/query status bez produkcijskih API poziva.

**Detaljni dokazi:** [stream D](../research/streams/D.md).

## F068 — Kartice lojalnosti

**Vlasnik:** stream D. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart nema loyalty card, a lib/features/shopping/shopping_list_view.dart nema kasni prikaz kartice. Barcode namirnice F017 nije isto što i sačuvana članska kartica.

**Predložena izmena:**
[
  "LoyaltyCard(id,ownerUserId,retailerId,label,symbology,valueAsString,expiresAt?,status,sharePolicy=personal). Kod je string radi vodećih nula. Prvo podržati dokumentovane statične code128/EAN/QR formate kroz renderer iza interfejsa; dinamičke/rotirajuće kartice unavailable. Program eligibility token za F071 je samo tvrdnja da kartica postoji/da korisnik ispunjava uslov, ne dokaz da će kasa odobriti popust.",
  "Lične kartice sinhronizovati kao privatne korisničke podatke uz RLS, nikad automatski članovima domaćinstva ili u javni dokaz računa. Izbor da li deljenje program dozvoljava ostaje gate pre eksplicitnog opt-in deljenja."
]

**Zavisnosti:** G-SCHEMA, G-CAPABILITY

**Male vertikalne celine:**
1. Ručni unos i privatno čuvanje koda sa validacijom symbology.
2. Offline prikaz iz nabavke i tekstualni fallback.
3. Provider/program capability i opcioni datum isteka; deljenje tek posle potvrđenih pravila programa.

**Kriterijumi prihvatanja:**
- [ ] Kod 0012345678905 roundtrip čuva obe vodeće nule; renderer generiše isti payload.
- [ ] Drugi član domaćinstva ne može čitati ličnu karticu direktnim upitom.
- [ ] Nepodržana/dinamička kartica prikazuje „Ova vrsta kartice nije podržana” i ne prikazuje lažno važeći statični kod.

**Verifikacija pri implementaciji:**
- [ ] Barcode encode/decode fixture i checksum validacija gde format to zahteva; Unicode/dužina/leading-zero slučajevi.
- [ ] Local RLS isti household različiti user-i; offline cold start i sign-out session isolation.
- [ ] Fizički skener i osvetljenje uređaja samo sa sintetičkim test kodom, bez tvrdnje da trgovac prihvata karticu.

**Detaljni dokazi:** [stream D](../research/streams/D.md).

## F069 — Podsetnik blizu prodavnice

**Vlasnik:** stream D. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
Nema geofence modela u lib/data/database.dart niti lokacijskog toka u lib/features/shopping/shopping_screen.dart. Postojeći AccountScope i lokalne otvorene ShoppingItems su tačke vezivanja, ne postojeća device capability podrška.

**Predložena izmena:**
[
  "StoreReminder(id,userId,householdId,branchId,center,radiusMeters,enabled,listIds,cooldownSeconds) je sinhronizovana preferenca; GeofenceRegistration i poslednja obaveštenja su lokalni po uređaju. DeviceCapability probe platformSupported/locationServices/preciseLocation/backgroundPermission/notificationPermission/registrationQuota; dozvole tražiti tek po uključivanju.",
  "Dwell/enter → ponovo proveri aktivno članstvo i lokalnu otvorenu stavku → dedupe po reminder+visit+cooldown → lokalno obaveštenje. Nema upload-a istorije kretanja. Opoziv dozvole/članstva i odjava uklanjaju registracije; desktop unavailable daje ručni podsetnik. Android pozadinski događaji nisu trenutni; Apple adapter zahteva zaseban platform spike."
]

**Zavisnosti:** G-CAPABILITY, F041, F063

**Male vertikalne celine:**
1. Model podsetnika i fake geofence/notifier adapter.
2. Android permission/register/unregister lifecycle i cooldown.
3. iOS capability spike i real-device verifikacija; macOS ručni fallback dok podrška nije dokazano završena.

**Kriterijumi prihvatanja:**
- [ ] Sa otvorenim artiklom jedan dwell daje najviše jedno obaveštenje u 4 h; sve bought daje 0.
- [ ] Denied/restricted/unsupported ne blokira Nabavku i jasno prikazuje „Podsetnik na lokaciji nije dostupan”.
- [ ] Odjava ili uklanjanje iz household-a briše registracije tog scope-a i ne otkriva naziv liste na zaključanom ekranu po default-u.

**Verifikacija pri implementaciji:**
- [ ] Fake clock i event fixture: dupli enter/dwell, enter posle cooldown-a, buy pre dwell-a, revoke pre callback-a, restart i reboot re-registration.
- [ ] Device matrix Android/iOS: deny→grant→revoke, battery saver i notifications denied; dokumentovati izmerena kašnjenja umesto obećanja.
- [ ] Test offline stale-list notification wording i tap otvara tačnu household/list scope uz novu proveru članstva.

**Detaljni dokazi:** [stream D](../research/streams/D.md).

## F070 — Stvarna isplativost obilaska prodavnica

**Vlasnik:** stream D. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
lib/domain/shopping_demand.dart računa potrebe i uporedive jedinice, ali nema route/store/Money model. ShoppingRepository.planTotals daje količine, ne trošak puta. F018 i F071 su predloženi podaci za cene i uslovne ponude.

**Predložena izmena:**
[
  "RouteScenario(currency,storeAssignment,packCounts,goodsTotalMinor,transportTotalMinor,feesMinor,travelSeconds,shoppingSeconds,unknownItems,priceCoverage,assumptions,dataVersion). Objective=goods+transport+fees; hard constraint travel+shopping <= maxDurationSeconds. Vrednost vremena je opcioni odvojeni scenario, ne skriveni trošak.",
  "DistanceMatrixProvider sa mode/checkedAt/source/errors; bez njega korisnik unosi povratni put i trošak, a heuristika je označena kao procena. Prvo ograničiti na najviše 3 radnje i enumerisati sve dopuštene raspodele/pakovanja; ne obećavati globalni optimum van tog skupa. Haversine blizina nije dužina puta. Nepokriveni artikli sprečavaju tvrdnju da je jedna korpa ukupno jeftinija."
]

**Zavisnosti:** F018, F043, F071, G-MONEY, G-CAPABILITY

**Male vertikalne celine:**
1. Ručni troškovi i vremena: jedna naspram dve radnje sa jednakom pokrivenošću.
2. Ograničen egzaktan optimizer i prikaz pretpostavki/nesigurnosti.
3. Distance provider tek uz dokazanu mogućnost, prava i quote/freshness invalidaciju.

**Kriterijumi prihvatanja:**
- [ ] Korpa A 100000 minor + put 10000 = 110000; A+B roba 90000 + put 25000 = 115000: jedna radnja je povoljnija za 5000 minor uprkos nižim cenama robe.
- [ ] Scenario 50 min ne ulazi u rezultat kad je limit 40 min.
- [ ] Nedostajuća cena ili matrica udaljenosti daje nepotpun scenario, ne 0 troška ili garantovanu uštedu.

**Verifikacija pri implementaciji:**
- [ ] Golden ručni primer i brute-force oracle za <=3 radnje/<=6 artikala, MOQ/pakovanja i neispunjena promocija.
- [ ] Test dateline/straight-line map podatak ne glumi voznu distancu; deterministic tie storeId i isti snapshot.
- [ ] Widget prikaže prevoz, robu, naknade, vreme i pokrivenost; fake route provider unavailable/rate-limited/offline.

**Detaljni dokazi:** [stream D](../research/streams/D.md).

## F071 — Kuponi i uslovne akcije

**Vlasnik:** stream D. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
ShoppingItems i supabase/migrations/20261030120200_household_data.sql nemaju promotion model. Open Prices Price.discount_type je kategorizacija ponude, bez izvršivog predicate ugovora za količinu, vremenski interval i članstvo.

**Predložena izmena:**
[
  "Promotion(id,retailerId,branchScope,productScope,currency,validFrom,validUntilExclusive,storeTimeZone,predicateAST,effect,stackGroup,priority,maxUses,source,sourceVersion). Predicate je tipiziran allowlist AST: All/Any, QuantityAtLeast, QualifyingSpendAtLeast, HasLoyaltyProgram, CouponActivated, StoreIn, ProductIn i WithinWindow; bez eval teksta ili AI generisanog izvršnog koda.",
  "Evaluator vraća eligible|ineligible|unknown sa reason codes i trace-om; efekat fixedBundlePrice/buyNPayM/percentOffBasisPoints/fixedOff ima limit i eksplicitno pravilo kombinovanja. Unknown predicate se ne primenjuje kao popust. Redemption rezervacija nije ostvarena ušteda, a ista couponId se ne troši dvaput."
]

**Zavisnosti:** F018, G-MONEY, G-SCHEMA

**Male vertikalne celine:**
1. Quantity/validity/loyalty predicate i obrazloženje za jednu ponudu.
2. Bundle/percentage effects, zaokruživanje i eksplicitna ekskluzivnost.
3. Aktivacija kupona, use-limit ledger i pregled kombinovanih ponuda.

**Kriterijumi prihvatanja:**
- [ ] Jedinica 10000 minor, buy2 bundle 15000: qty1 = 10000 bez popusta, qty2 = 15000, qty3 = 25000; ne primeniti 7500 na qty1.
- [ ] Loyalty potrebna + status unknown daje unknown i osnovnu cenu; interval [start,end) isključuje tačno end.
- [ ] 10% na 19999 minor daje discount 2000 i net 17999 po half-up pravilu; dva exclusive kupona ne sabiraju uštede.

**Verifikacija pri implementaciji:**
- [ ] Truth table svih predicate čvorova i All(false,unknown)=false, Any(true,unknown)=true; ostalo po tri-state ugovoru.
- [ ] Fake clock/store time zone: UTC offset, DST i datum isteka; qty 1/2/3, pogrešna poslovnica i pakovanje.
- [ ] Golden cent/minor zaokruživanje, bundle remainder, cap, stacking, replay redemption i nedozvoljeni AST; svi podaci sintetički bez trgovca.

**Detaljni dokazi:** [stream D](../research/streams/D.md).

## F072 — Povratna ambalaža i kaucije

**Vlasnik:** stream C. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::ShoppingItems/PantryItems have no deposit, container-return or currency ledger; existing shopping provenance is food purchase only.

**Predložena izmena:**
[
  "Add ReturnableType and ReturnableMovement with units signed by issue/return, depositMinor, currency, purchaseOperationId, returnedAt and expectedRevision. Track container count separately from edible stock and from tare.",
  "Receipt classification can link a deposit line to container issue; partial return decreases held count and records actual refund, without pretending the food was returned. No assumed Serbian national scheme, retailer support or refund amount."
]

**Zavisnosti:** GTX, F073

**Male vertikalne celine:**
1. Manual issue/return model and balance screen with currency tests.
2. Atomic ledger and compensation with household RLS.
3. Optional receipt classification after F073; no retailer integration promised.

**Kriterijumi prihvatanja:**
- [ ] Buy six bottles at 20 RSD deposit => held 6/paid120 RSD; return four and receive80 => held2/net deposit40; duplicate return operation has no effect.
- [ ] Mixed currencies never sum; deposit-only receipt line contributes zero grams to pantry.

**Verifikacija pri implementaciji:**
- [ ] Known integer minor-money/count fixtures and partial-return/over-return/reversal.
- [ ] Fake-backend two-account isolation; receipt duplicate and offline conflict tests.

**Detaljni dokazi:** [stream C](../research/streams/C.md).

## F073 — Poravnanje kupovine sa računom

**Vlasnik:** stream C. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. ShoppingRepository.setBought/_buy freezes purchaseProvenanceJson; receivePurchases keys by shopping item; no receipt document, OCR rows or actual-quantity reconciliation.

**Predložena izmena:**
[
  "ReceiptDraft(documentHash, merchantText, purchasedAt, currency, parserVersion, rows) is private and separate from confirmed stock. Row includes source row ordinal, raw label, parsed quantity/unit/price, classification(food/deposit/discount/return), candidate matches and review status.",
  "AI/OCR through AIRouter proposes only. ConfirmReconciliation(operationId, expectedDraftRevision, accepted mappings) posts actual purchased quantities and receipt links, then receives the same physical supply in one transaction/outbox group. Unique household+receiptId+rowId+action prevents retry duplicates; document hash warns about possible duplicate, never auto-merges legitimate identical receipts.",
  "A bought row can span several lots/receipts: use explicit purchase/receipt lines and root conservation (F038). Preserve original demand and frozen purchase history; corrections after confirmation use compensating differences, not delete/recreate. Receipt image private and optional; no automatic public Open Prices upload."
]

**Zavisnosti:** GTX, GQ, F038, GADAPTER

**Male vertikalne celine:**
1. Manual receipt draft and row matching UI with no stock writes; pure parsing tests.
2. Confirm single-line receipt using existing setBought/receive identity and operation id.
3. Add multiline/split/partial reconciliation and corrections with transactional outbox and concurrency constraints.
4. Optional photo/text extraction through AIRouter only after manual confirmation flow passes.

**Kriterijumi prihvatanja:**
- [ ] List asks750 g; receipt confirms2x500 g: demand stays750 g, actual supply1000 g, remainder250 g; confirming/replaying twice creates one purchase and one receipt supply.
- [ ] Already marked bought then receipt reconciliation does not add a second1000 g; ambiguous kg/kom/price line stays unposted until reviewed.
- [ ] Food, deposit, discount, unlisted product and returned item are reviewed separately; declining draft writes no purchase/stock.

**Verifikacija pri implementaciji:**
- [ ] Fake AI and malformed OCR fixtures, decimal comma, weighed produce, multipack, duplicate scan, same-content different receipt and mixed units.
- [ ] Repository atomic failure injection before/after each row and retry; existing bought->received path; concurrent same-operation unique-key race; exact 750/1000/250 fixture.
- [ ] Widget editable matching preview, rejection/manual rows and private image access; local Supabase two-account RLS, no external API.

**Detaljni dokazi:** [stream C](../research/streams/C.md).

## F074 — Težina posude i neto sadržaj

**Vlasnik:** stream C. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. No container/tare/gross fields; current normalizeUnit keeps mass separate from volume.

**Predložena izmena:**
[
  "Container(id, householdId, label, tareMicros, massUnit, verifiedAt) is distinct from product, returnable deposit type and food lot. Measurement(id, containerId, lotId, grossMicros, tareSnapshotMicros, measuredAt, expectedRevision) proposes net=gross-tare.",
  "Confirm replaces remaining mass by a correction movement, never adds the net as a new receipt. Reject gross<tare and unknown tare; manual entry always available without Bluetooth. Tare snapshot preserves history when empty jar mass changes."
]

**Zavisnosti:** GTX, F039, F038

**Male vertikalne celine:**
1. Pure mass-only tare calculator and editable container profile.
2. Confirm measurement onto one existing lot with atomic correction and outbox.
3. Optional container label lookup; device input belongs F076 and is not required.

**Kriterijumi prihvatanja:**
- [ ] Gross842 g minus tare312 g =530 g net (530000000 micros); if prior600 g, correction is-70 g; repeated operation remains530 g.
- [ ] Gross300<tare312 rejected; volume lot cannot silently become mass; editing container later does not rewrite measurement history.

**Verifikacija pri implementaciji:**
- [ ] Pure gross/net validation fixtures including zero/unknown and precision boundaries.
- [ ] Repository correction invalidates over-reservation; fake clock, stale revision, duplicate command; widget manual measurement and undo.

**Detaljni dokazi:** [stream C](../research/streams/C.md).

## F075 — Stvarni prinos nakon kuvanja

**Vlasnik:** stream C. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
lib/domain/shopping_demand.dart::scaleQuantity/demandFor scale raw input to servings; lib/domain/meal_plan.dart::RecipeSnapshot and lib/data/meal_plan_repository.dart::setCooked do not measure final mass.

**Predložena izmena:**
[
  "Extend CookedBatch (F013 shared contract) with yieldMeasurementId, finalNetMicros, measuredAt, recipeSnapshot, cookedOperationId. Gross yield can use F074 tare; measured water loss does not rewrite raw ingredient purchase demand.",
  "Portion allocations consume confirmed cooked mass; equal portions use integer quotient/remainder with visible final residual. Label serving count approximate when uneven; nutrition is a separate F046 estimate and cannot infer mass from energy."
]

**Zavisnosti:** GTX, F013, F074, F012

**Male vertikalne celine:**
1. Manual finished net mass entry on the shared CookedBatch model.
2. Mass-based portion allocation with conservation and optional F074 gross/tare.
3. Plan-linked servings and later read-only yield comparisons for same recipe version.

**Kriterijumi prihvatanja:**
- [ ] 1800 g finished batch into six equal portions =>300 g each; allocate2 portions600 g ->1200 g remains; new meal using these portions creates no raw demand.
- [ ] 1000 g/3 stores333333333,333333333,333333334 micros (sum1000000000); reweigh remaining is explicit correction, not a second batch.

**Verifikacija pri implementaciji:**
- [ ] Known yield/tare and integer residual fixtures; no sum drift on split/recombine.
- [ ] Repository cook once -> record yield twice -> freeze -> reserve -> eat; raw-input demand never doubles, recipe source deletion keeps snapshot.

**Detaljni dokazi:** [stream C](../research/streams/C.md).

## F076 — Kompatibilna Bluetooth vaga

**Vlasnik:** stream E. **Faza:** P3 conditional. **Status:** planirano.

**Postojeće stanje:**
pubspec.yaml nema BLE/scale zavisnost; lib/domain/shopping_demand.dart ima normalizeUnit/toMicros i kompatibilne grupe količina. Nema device adapters u lib/. Acaia MainActivity.onWeightEvent pokazuje masu i jedinicu, a pravi SDK je app/libs/acaiaSDKAndroid-release.aar sa custom licencom.

**Predložena izmena:**
[
  "ScaleAdapter.probe/connect/read/disconnect -> DeviceCapabilities i WeightReading {value,unit,receivedElapsed,deviceKey,stable:bool?,sequence?}; preciznost/stabilnost mogu biti unknown. Normalizovati samo potvrđenu masu u grams/micros.",
  "Manuelni target/reading rade bez BLE; potvrda koristi reading tek kada je fresh. Tare je zasebna dostupna komanda sa potvrdom; nije automatski subtraction iz F074. Acaia implementacija je pravni/SDK gate, bez dekodiranja AAR-a."
]

**Zavisnosti:** G-DEVICE, G-ACAIA-LICENSE, F028, F074

**Male vertikalne celine:**
1. Fake/manual adapter i poređenje target-a sa masom sastojka.
2. Proveriti aktuelnu SDK licencu, dozvole i test uređaj/model/firmware; Android bridge samo nakon gate-a.
3. Fizička validacija, disconnect/stale/reconnect i iOS/macOS feasibility posebno.

**Kriterijumi prihvatanja:**
- [ ] Target 500 g, reading 0.4 kg daje nedostaje 100 g; 1 oz = 28.349523125 g; zapremina l ne poredi se sa masom bez potvrđene gustine.
- [ ] Nepoznat unit, disconnected ili staro očitavanje ne dobija status dostignut cilj.
- [ ] Nepodržan model i odbijena dozvola otvaraju ručni unos; nijedna vaga nije podržana samo zato što BLE scan vidi ime.

**Verifikacija pri implementaciji:**
- [ ] Adapter contract fixtures: g/kg/oz, negativna masa, overload, NaN, out-of-order i stable unknown; freshness fake clock.
- [ ] Fizički model/firmware i poznati tegovi; meriti odstupanje i zakasnela očitavanja bez opšteg obećanja tačnosti.
- [ ] Lifecycle scan timeout, reconnect, Bluetooth off, odjava i dispose release; testirati moderni Android permission flow nezavisno od starog primera.

**Detaljni dokazi:** [stream E](../research/streams/E.md).

## F077 — Kompatibilni termometar

**Vlasnik:** stream E. **Faza:** P3 conditional. **Status:** planirano.

**Postojeće stanje:**
Nema BLE thermometer ili temperature reading modela u Tavli. Combustion Android DeviceManager.probeFlow/connect i ProbeTemperatures.coreTemperatureCelsius razlikuju fizičke/virtuelne senzore; iOS Device.updateDeviceStale koristi 15 s timeout. To nije dokaz podrške Flutter/macOS aplikacije.

**Predložena izmena:**
[
  "ThermometerAdapter -> TemperatureReading {celsius,sensorRole,probeKey,receivedElapsed,sequence?,quality}; DeviceCapabilities navodi readCore/readAmbient/stream, model i firmware. Biranje sonde i role pre alarma.",
  "TemperatureTarget {id,sessionId,probeKey,role,thresholdC,direction,hysteresisC,armed}; alarm na prelasku svežih uzoraka, dedupe; prekid očitavanja prikazati kao Veza prekinuta, ne kao nastavak merenja.",
  "Prvi adapter samo očitavanje potvrđenog Combustion modela; nema automatskog kuvanja, procene bezbednosti hrane ili upravljanja drugim uređajem."
]

**Zavisnosti:** G-DEVICE, F009, F051

**Male vertikalne celine:**
1. Manual/fake očitavanje + target crossing i stale state.
2. Android native SDK bridge sa lifecycle ownership i senzor role mapping.
3. iOS bridge i fizički background alarm test; macOS ostaje unavailable dok se posebno ne potvrdi.

**Kriterijumi prihvatanja:**
- [ ] Target 75 °C; 74,75,76 emituje jedan alarm; ponovljena sekvenca i 75.1 ne stvaraju nove.
- [ ] Staro očitavanje i pogrešna sonda/ambient senzor ne aktiviraju core target.
- [ ] Nestanak novih uzoraka prelazi u stale najkasnije 15 s + jedan UI tick u prvoj politici; manual entry je jasno označen.

**Verifikacija pri implementaciji:**
- [ ] Fake streams: 8 senzora i promena virtualCoreSensor, nevalidni paketi, out-of-order, disconnect/reconnect, reset alarm.
- [ ] Known temperature reference/test probe simulator bez pokretanja upstream app-a u ovoj fazi; implementacija kasnije potvrđuje real hardware.
- [ ] Real Android/iOS lock/background/permission revoked/Bluetooth off; u stanju bez background stream-a ne obećavati obaveštenje.

**Detaljni dokazi:** [stream E](../research/streams/E.md).

## F078 — Slanje postavki pametnoj rerni

**Vlasnik:** stream E. **Faza:** P3 conditional. **Status:** planirano.

**Postojeće stanje:**
Tavli nema oven network adapter, autorizaciju proizvođača ili strukturisane oven settings; steps su tekst. SmartThings javni capability API opisuje komande, ali dostupnost konkretne rerne/regiona i remote-enable nije utvrđena.

**Predložena izmena:**
[
  "OvenAdapter.probe(deviceId) -> capabilities {setTemperature,setMode,temperatureUnit,range,supportedModes,remoteEnabled,reachable,reason}; prepare(setting) -> CommandPreview; send(preview,userConfirmation) -> CommandReceipt {requestId,acceptedAt,observedState?,status}.",
  "Ručno podešavanje ostaje osnovni tok. Samo aktuelna potvrda uređaja/režima/temperature šalje komandu; timeout je unknown, ne uspeh. Bez auto-retry van online sesije; nijedna komanda kroz Supabase outbox, voice ili AI. Prva verzija ne uključuje remote start/preheat."
]

**Zavisnosti:** G-DEVICE, G-OVEN-API, F050, F051

**Male vertikalne celine:**
1. Manual preview koji prikazuje uređaj, režim, temperaturu i source; fake adapter.
2. Sandbox zvaničnog API-ja i eligibility/OAuth/token isolation provera bez pravih ključeva u istraživanju.
3. Jedan potvrđeni model/region sa command/readback i eksplicitnim klikom; ostalo unsupported.

**Kriterijumi prihvatanja:**
- [ ] Bez supportedModes ili temperature range nema slanja; fan nije tiho mapiran na static.
- [ ] Otkazivanje potvrde daje nula komandi; retry posle timeout-a zahteva novu proveru stanja i novi klik.
- [ ] API accepted nije isto što i uređaj postavljen: prikaz Poslato / Potvrđeno / Ishod nepoznat odvojeno.
- [ ] Offline/revoked/remote-disabled prikazuje ručna uputstva; reconnect ne izvršava staru komandu.

**Verifikacija pri implementaciji:**
- [ ] Fake API: 401,403,429,timeout, accepted bez readback-a, različit unit, zastareo preview, dupli tap.
- [ ] Contract test official capabilities + allowed modes/ranges; lokalna fiktivna OAuth stanja, bez produkcije.
- [ ] Fizička rerna samo u implementacionom pilotu sa potvrdom; zabeležiti model/firmware/region i remote-enable ponašanje.

**Detaljni dokazi:** [stream E](../research/streams/E.md).

## F079 — Kalkulator geometrije kalupa

**Vlasnik:** stream F. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
Postoji scaleQuantity(quantity, baseServings, servings), što linearno skalira po porcijama. Nema geometrije/visine kalupa; time se ne može odrediti isti nivo testa u drugom obliku.

**Predložena izmena:**
[
  "Pure PanGeometry.round(diameterCm)|rectangle(lengthCm,widthCm), PanScaleRequest(from,to,sourceFillHeightCm,targetFillHeightCm,countFrom,countTo), result(factor,assumptions,warnings). V=area*fillHeight*count; faktor=targetV/sourceV. Podržati prvo ravne vertikalne zidove; tapered/bundt/custom zahteva poznat volumen ili unavailable.",
  "Preview primenjuje faktor na poznate ingredient quantities bez izmene base servings. Sačuvati kao novu verziju samo nakon potvrde uz calculation metadata; ordinary serving scaling i geometry mode su odvojene akcije. Korake/vreme/temperaturu ne množiti i ne obećavati isti rezultat pečenja.",
  "Prikazati pretpostavku iste gustine/visine i stvarnu visinu kalupa kao granicu, ne popuniti kalup do vrha. NaN/inf/zero/negative dimenzije i targetFillHeight>panHeight -> blokiran izračun."
]

**Zavisnosti:** G-PROVENANCE

**Male vertikalne celine:**
1. Test-first round/rectangle volumes -> standalone kalkulator iz recepta.
2. Ingredient preview sa null količinama -> potvrda postojeće update istorije.
3. Broj kalupa i eksplicitni volumen za nepravilan oblik -> warnings i metadata.

**Kriterijumi prihvatanja:**
- [ ] Okrugao 20 cm -> 25 cm pri istoj visini daje 1.5625; 200 g postaje 312.5 g.
- [ ] Pravougaoni 20x30 cm -> okrugao 24 cm pri istoj visini daje 0.24*pi ≈0.7539822369.
- [ ] Dvostruka target visina daje dvostruki faktor; unknown quantities ostaju unknown; 30 minuta ostaje 30 minuta uz upozorenje da vreme treba proveriti.

**Verifikacija pri implementaciji:**
- [ ] Domain test-first unapred navedeni rezultati uz tolerance 1e-9, unit mm/cm conversion, count, invalid input/overflow.
- [ ] Widget preview/cancel/save -> jedna RecipeVersion i isti source recipe bez upisa pri cancel.
- [ ] Regresija test/domain/shopping_demand_test.dart potvrđuje da standardno skaliranje porcija nije promenjeno.

**Detaljni dokazi:** [stream F](../research/streams/F.md).

## F080 — Pekarski procenti

**Vlasnik:** stream F. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
Ingredient nema flour/water/starter role ni starter hydration; masa i zapremina odvojene su u normalizeUnit. Obično scaleQuantity nema pojam ukupnog brašna.

**Predložena izmena:**
[
  "DoughFormula(recipeRevisionHash, components[ingredientId, role, massG, starterHydrationPercent?], flourBasis, targetDoughMassG?, targetHydrationPercent?). Rola korisnički potvrđena; ne zaključivati tip brašna/udeo vode iz naziva ili AI-ja.",
  "Za starter S i h=hydrationPercent/100: starterFlour=S/(1+h), starterWater=S*h/(1+h). Ftotal=directFlour+starterFlour, Wtotal=directWater+starterWater, hydration=100*Wtotal/Ftotal; svaki bakers%=100*ingredientMass/Ftotal. Starter uneti kao fizičku komponentu u dough mass samo jednom, njegove izvedene flour/water redove ne sabirati ponovo.",
  "Prvi režim prikazuje procente i skalira poznatu kompletnu formulu na targetMass=sum(physical masses)*factor. Kasnije solve target hydration uz fiksno ukupno brašno/starters i ostale mase -> direct water = Htarget*Ftotal-starterWater; negativna voda -> nemoguće. Volumeni/unknown hydration/unknown sastojak daju partial/unavailable, bez pretpostavke 100%."
]

**Zavisnosti:** F002, G-PROVENANCE

**Male vertikalne celine:**
1. Role picker + poznate mase -> bakers% i ukupna hidratacija.
2. Poznata starter hydration i target total mass -> preview -> potvrđena verzija.
3. Zaseban režim target hydration sa eksplicitnim fiksnim veličinama -> constrained solve.

**Kriterijumi prihvatanja:**
- [ ] 500 g flour + 300 g water + 100 g starter pri 100% hydration + 10 g salt: F=550 g, W=350 g, H=63.6363636%, salt=1.8181818%, physical mass=910 g.
- [ ] Target mass=1820 g udvostručuje sve fizičke komponente i čuva hidrataciju.
- [ ] Za 70% hydration uz F=550 g, starter 100 g/100%, voda direktno=335 g; starter unknown hydration onemogućava precizan zbir.
- [ ] Starter 200 g pri 50% hydration daje 133.3333 g flour i 66.6667 g water; nema dupliranja u target dough mass.

**Verifikacija pri implementaciji:**
- [ ] Domain test-first navedene ručno izračunate formule, više brašna/startera, 0 flour, negative/NaN, ml bez density i nepoznata hydration.
- [ ] Mass conservation: sum samo fizičkih komponenti = target, derive starter sum = S, rounding poslednji korak.
- [ ] Widget role confirmation/cancel i repository version regression; ordinary servings scaling ostaje odvojeno.

**Detaljni dokazi:** [stream F](../research/streams/F.md).

## F081 — Put učenja kuvanja

**Vlasnik:** stream E. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
lib/domain/recipe.dart sadrži Recipe/Ingredient, lib/data/database.dart nema skill/curriculum/progress tabelu. RecipeView i budući cooking log daju moguću osnovu praktičnog zadatka; nema dokaza o isporučenom učenju.

**Predložena izmena:**
[
  "Curated Skill {id,revision,titleSr,prerequisiteIds,lessonSr,taskSr,rubric,glossaryIds,recipeSuggestions}; SkillAttempt {id,userId,skillId,skillRevision,cookingLogId?,evidenceNote,criterionChecks,result,completedAt?}.",
  "Sopstveni urednički sadržaj; napredak znači korisnik potvrđene kriterijume, ne sertifikat ili dokaz stručnosti. Kurikulum radi offline; reference na spoljne škole samo link, bez kopiranja njihovog sadržaja."
]

**Zavisnosti:** F047, F082, G-SYNC

**Male vertikalne celine:**
1. Jedna sopstvena lekcija + proverljiv zadatak/rubrika i ručni pokušaj.
2. Verzionisano lokalno izdanje sadržaja i lični progress/outbox.
3. Preduslovi i povezivanje sa cooking log-om; opcione recipe suggestions bez preusmeravanja aktivne sesije.

**Kriterijumi prihvatanja:**
- [ ] Za zadatak ravnomerno iseckati 10 komada korisnik proverava objavljenu rubriku; samo završavanje recepta ne označava veštinu kao stečenu.
- [ ] Promena revizije lekcije čuva pokušaj stare revizije; reset pokušaja ne briše cooking log.
- [ ] Drugi nalog ne vidi lični napredak; offline završetak jednom se sinhronizuje.

**Verifikacija pri implementaciji:**
- [ ] DAG fixtures: ciklus se odbija; nedostajući prerequisite ne otključava naredni nivo.
- [ ] Repository migration, user-scope RLS i dva naloga; idempotentni completion.
- [ ] Widget offline lekcija, dostupnost teksta/tastature i rubrika; urednička provera originalnog srpskog sadržaja.

**Detaljni dokazi:** [stream E](../research/streams/E.md).

## F082 — Kulinarski rečnik

**Vlasnik:** stream E. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
RecipeView u lib/features/recipes/recipe_view.dart koristi Text(step), nema definicije/linkove pojmova. Postojeći ingredientKey/normalizeUnit u lib/domain/shopping_demand.dart rešavaju identitet namirnice i mere, ne stručne kulinarske pojmove.

**Predložena izmena:**
[
  "GlossaryEntry {id,revision,termSr,aliases,definitionSr,exampleSr,relatedIds,provenance,rights}; kuriran verzionisan lokalni asset, ne AI odgovor.",
  "Deterministički matcher Unicode/case/word-boundary + najduža fraza; označava poznate pojmove u koraku i otvara accessible sheet bez izmene teksta. Ručna pretraga uvek dostupna; višeznačne termine izabrati, ne nagađati."
]

**Zavisnosti:** G-CONTENT

**Male vertikalne celine:**
1. Sopstvene definicije za deglazirati/blanširati i offline search.
2. Text span matcher i sheet u RecipeView/cooking ekranu uz accessibility.
3. Verzionisanje/urednička kontrola aliases i povezivanje sa F081.

**Kriterijumi prihvatanja:**
- [ ] Deglazirati otvara tačan srpski opis i primer bez mreže; close vraća isti korak/scroll/timer.
- [ ] Termini ne hvataju podniz unutar druge reči; duža fraza ima prednost i nema preklapajućih linkova.
- [ ] Izvor/rights postoje za svaki unos; nema kopiranja školskog/proprietary teksta.

**Verifikacija pri implementaciji:**
- [ ] Matcher fixtures dijakritici, različito veliko slovo, interpunkcija, duža fraza, višeznačni alias i nepodudaranje.
- [ ] Widget semantics/tastatura/screen reader, 200% text scale, narrow/wide i active timer bez reset-a.
- [ ] Urednički pregled definicija i sadržaja; integritet glossary ID veza i revizija offline asset-a.

**Detaljni dokazi:** [stream E](../research/streams/E.md).

## F083 — Dostupnost konkretnih proizvoda

**Vlasnik:** stream C. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
No retailer stock adapter in lib/data; OFF product metadata and Open Prices historical observations are external sources, neither is household Supply nor proof of live shelf stock.

**Predložena izmena:**
[
  "RetailAvailabilityAdapter.probe(country, retailer, branch, fulfillmentSlot) reports supported/unsupported/authRequired/temporarilyUnavailable with capabilities. AvailabilityObservation(productCode, retailerSku, branchId, slot, status[inStock,outOfStock,unknown], observedAt, expiresAt, source, evidence) is cached separately.",
  "Only authorized documented retailer data with actual branch/slot semantics can produce inStock. Price history or OFF stores/countries tags remain metadata; stale result becomes unknown. No Serbian retailer is confirmed supported in this research; ship manual dated observation plus unavailable state until a lawful adapter is verified."
]

**Zavisnosti:** GADAPTER, F017, F018, F067

**Male vertikalne celine:**
1. Define availability contract and manual dated observation, default unknown.
2. Add isolated cache and fake adapter test suite; no production integration claim.
3. Enable one Serbian retailer only after capability/terms/data validation, with feature flag and expiry policy.

**Kriterijumi prihvatanja:**
- [ ] Open Prices price from yesterday yields unknown availability; branch A inStock cannot satisfy branch B or a different slot.
- [ ] Timeout, unsupported Serbia retailer, missing SKU and expired observation show „Dostupnost nije proverena” with last checked time; household stock and shopping quantities do not change.

**Verifikacija pri implementaciji:**
- [ ] Fake adapters for supported, denied, stale, branch mismatch and late/out-of-order response.
- [ ] Future capability audit: official API terms/endpoint/branch identity/slot semantics, sample freshness SLA and Serbian test branch evidence before enabling retailer.
- [ ] Widget source/date display and manual observation correction; never use a live retailer in unit tests.

**Detaljni dokazi:** [stream C](../research/streams/C.md).

## F084 — Unutrašnja doslednost recepta

**Vlasnik:** stream F. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
Ingredient.fromJson proverava naziv i parsira količinu, Recipe.fromAiJson proverava naziv/listu; steps su stringovi. Nema semantičkih veza ingredient-step ni lint izveštaja.

**Predložena izmena:**
[
  "RecipeConsistencyService.analyze(revisionHash)->ConsistencyReport(issues[code,severity,stepIndex,ingredientId?,evidenceSpan,expected?,actual?,origin], analyzerVersion). Deterministička pravila prvo: eksplicitno povezani sastojci, kompatibilne jedinice, split quantities i ingredient identity/sinonimi.",
  "Heuristike teksta prijavljuju candidateMissingIngredient/candidateAmountMismatch sa citiranim span-om; ne proglašavati odsustvo dok nemamo pouzdano mapiranje. Neupotrebljen sastojak može biti garnitura, pa warning. \"pola mleka\"/\"ostatak\" ne tretirati kao novu punu količinu; range/optional i različite faze odvojiti.",
  "AI opcioni dodatni pregled isključivo preko AIRouter, origin=aiSuggestion; nema automatskog uređivanja niti safety/verified badge-a. Prihvati ispravku otvara postojeći editor/AI preview i čuva RecipeVersion; dismissed issue vezan za revision+rule version."
]

**Zavisnosti:** F002, F028, G-PROVENANCE

**Male vertikalne celine:**
1. Pure lint sa eksplicitnim ingredient-step refs i sintetičkim primerima -> issue panel.
2. Text candidate rules sa dokaznim span-om i dismiss/resolve -> postojeći editor.
3. Opcioni AI suggestions -> odvojena oznaka/preview -> regression corpus.

**Kriterijumi prihvatanja:**
- [ ] Lista sadrži 100 g šećera, dva eksplicitno povezana koraka koriste 60 g i 60 g: issue ukupno 120 g >100 g.
- [ ] 60 g +40 g prolazi; "dodaj ostatak" se ne prijavljuje kao dodatnih 100 g.
- [ ] "Dodaj 2 jaja" bez egg ingredient daje kandidat sa tačnim korakom; izveštaj ne menja recept.
- [ ] Promena verzije briše oznaku da je stari lint rezultat aktuelan; AI issue vidljivo je predlog.

**Verifikacija pri implementaciji:**
- [ ] Test-first corpus minimalnih srpskih parova: optional garnitura, synonyms, g/kg, ml/g unknown, split/ranges/remainder, korak bez mera.
- [ ] Measure precision/recall na ručno označenom sintetičkom/regresionom skupu; target >=95% precision za deterministic rules, heuristike ne blokiraju čuvanje.
- [ ] Widget resolve/dismiss i stale revision; repository update/undo tests; fake AI parser retry.

**Detaljni dokazi:** [stream F](../research/streams/F.md).

## F085 — Status testiranog recepta

**Vlasnik:** stream F. **Faza:** P2. **Status:** planirano.

**Postojeće stanje:**
RecipeSource photo/ai/manual i answeredBy opisuju nastanak/poslednji model, ne stvarno kuvanje. RecipeVersion čuva prethodno stanje, Ratings ima cookedAt/stars ali ne snapshot revision/porcije/opremu.

**Predložena izmena:**
[
  "Predložiti RecipeTrial(id, recipeId, revisionHash, testerUserId, testedAt, servings, equipmentSnapshot, outcome, notes?, evidenceAssetIds?, visibility). Canonical revision hash stabilno kodira kuvarski sadržaj i opremu/yield koji su deo same formule; trial servings/equipment su zaseban uslov isprobavanja, ne updatedAt/local imagePath/model label. Hash nije current row ID.",
  "Badge izveden iz trial-a sa pozitivnim korisnički potvrđenim ishodom za tačan revision i uslove: \"Isprobano: 4 porcije, rerna …\"; AI, import i ocena zvezdicama ne stvaraju trial automatski. Posle promene recepta prikazati \"Prethodna verzija je isprobana\". Vraćanje identičnog sadržaja može ponovo povezati postojeći trial; promenjena oprema/servings prikazuje drugačije uslove.",
  "Privatni dnevnik/ocene (F047) odvojeni su od eksplicitno deljene tvrdnje o isprobavanju. Trial personal owner RLS; household badge samo uz visibility=household i minimalne podatke. Brisanje recepta/istorije ne sme tiho pretvoriti tvrdnju u dokaz druge verzije; sačuvati trial content hash i potreban snapshot ili ukinuti prikaz."
]

**Zavisnosti:** G-PROVENANCE, G-SCHEMA, F047

**Male vertikalne celine:**
1. Revision hash i ručno potvrđen trial za jedan recept -> read-only badge.
2. Promena/restore recepta -> aktuelan/prethodni status + uslovi.
3. Eksplicitna visibility kontrola i veze sa opcionalnim dnevnikom -> sync/RLS.

**Kriterijumi prihvatanja:**
- [ ] AI-generisan recept ima status "Nije označen kao isproban" i ne dobija badge iz source/modela.
- [ ] Trial za 2 porcije u kalupu 20 cm ne dokazuje 8 porcija/30 cm; UI navodi tačne uslove.
- [ ] Izmena 100 g->120 g menja hash i aktuelni badge nestaje, original trial ostaje vezan za stari sadržaj.
- [ ] User B ne može dodati/izmeniti trial kao user A; privatne notes nisu u javnom F064 DTO.

**Verifikacija pri implementaciji:**
- [ ] Test-first canonicalization hash za semantic changes naspram updatedAt/model/imagePath, ordering i Unicode normalizaciju po definisanom pravilu.
- [ ] Repository trial creation/update/undo/restore i pruned history slučaj; test ličnog visibility-a.
- [ ] Local pgTAP dva korisnika: owner create/update, household projection allowlist i share leak regression.

**Detaljni dokazi:** [stream F](../research/streams/F.md).

## F086 — Procena ekološkog uticaja sa poreklom

**Vlasnik:** stream F. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
Recipe/Ingredient nemaju environment facts, region, proizvodni metod ni mass binding. Količine bacanja iz F040 nisu environmental impact metod.

**Predložena izmena:**
[
  "EnvironmentalFactor(dataset, datasetVersion, factorId, foodState, geography, productionSystem, functionalUnit, indicator, amount, unit, lifecycleBoundary, methodVersion, sourceUrl, license, retrievedAt). IngredientImpactBinding korisnik potvrđuje; čuvati assumptions i match quality kategorički, ne izmišljeni confidence broj.",
  "Početni indikator climate kgCO2e/kg food sa kompatibilnim boundary i istom metodom. result=Σ massKg*factor; per-serving deli potvrđenim servings. Nepoznat sastojak ili geografsko nepoklapanje -> partial/assumption vidljivo. Ne mešati upstream farm-gate sa retail/plate faktorom; ne sabirati već zbirni prepared-dish faktor sa njegovim sastojcima.",
  "RecipeImpactEstimate(revisionHash, indicator, totalKnownImpact, coverageCount, knownMassCoverage?, unknownMassIds, factors[], assumptions[], computedAt). Poznati subtotal nije total cele hrane kad nedostaje pokrivenost. AGRIBALYSE LCA dokumentacija je kandidat za metod/provenance, dataset i reuse prava tačnog izdanja tek proveriti; u ovom prolazu nisu preuzeti faktori niti implementiran servis."
]

**Zavisnosti:** F046, F002, G-PROVENANCE, G-DATA-LICENSE

**Male vertikalne celine:**
1. Sintetički mass factors -> tačna suma/coverage -> read-only prikaz.
2. Dataset license/version/boundary review -> jedan eksplicitno podržan dataset adapter i lokalni cache.
3. User-confirmed ingredient bindings + stale/method change invalidation -> poređenje samo uporedivih procena.

**Kriterijumi prihvatanja:**
- [ ] 0.2 kg A sa 5 kgCO2e/kg +0.3 kg B sa 1 kgCO2e/kg daju 1.3 kgCO2e poznatog subtotala, 0.65 za 2 porcije.
- [ ] Dodatni nepoznat sastojak označava partial; unknown masa sprečava lažan 100% maseni coverage.
- [ ] Faktori sa različitim boundary/method nemaju jednu zbirnu ocenu; datasetVersion i geography vidljivi su korisniku.
- [ ] Offline bez faktora daje unavailable, bez AI izmišljenih brojeva.

**Verifikacija pri implementaciji:**
- [ ] Domain test-first kg/g, factor functional units, mismatched boundaries, missing mass, zero vs absent factor i double-count prepared food.
- [ ] Fake adapter za missing ID/version/license i cache age; snapshot invalidation pri izmeni recepta.
- [ ] UX test izvor/metod/pokrivenost i comparing partial vs complete upozorenje; bez stvarnih podataka tvrdnje o Srbiji.

**Detaljni dokazi:** [stream F](../research/streams/F.md).

## F087 — Ponudi višak hrane

**Vlasnik:** stream C. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. Household-scoped sync exists in lib/sync/entities.dart::EntityScope; no public offer/claim or external transfer model.

**Predložena izmena:**
[
  "FoodOffer(id, ownerHouseholdId, lotId, quantityMicros/unitGroup, confirmedDescription, ingredients/allergensAsDeclared, preparation/storage facts, pickupWindow, state, revision) exposes only explicitly chosen facts. Unknown remains unknown; do not label food safe from date alone.",
  "Offer reservation removes offered amount from planner-available capacity without consuming it. Claim/withdraw/expire do not transfer stock. Owner confirms handover -> single transfer-out movement; recipient can independently confirm receipt under a new household root linked by opaque handover reference, not access donor inventory.",
  "First slice private revocable unguessable link to named recipient; no public discovery/location feed. Exact address/contact shared only explicitly; auth/authorization for claiming and atomic single-winner transfer gate required online. Offline supports draft and queued owner correction, not two conflicting successful claims."
]

**Zavisnosti:** GTX, F038, F039, F064, GSHARE

**Male vertikalne celine:**
1. Private offer draft and local quantity reservation only, no external publish.
2. Revocable minimal projection and online atomic claim; permission/RLS tests.
3. Owner-confirmed handover movement and optional independent recipient receipt; no automatic chat/email sent.

**Kriterijumi prihvatanja:**
- [ ] Offer300 g from500 g leaves200 g available; withdraw/expire restores500 g; confirmed handover leaves200 g and retry does not subtract again.
- [ ] Two claimants racing produce one accepted claim; recipient reads no other pantry row; link revocation removes offer access; exact pickup location absent from public payload.

**Verifikacija pri implementaciji:**
- [ ] State machine fixtures draft->offered->claimed->handedOver and cancel/expire; reservation conservation and handover retry.
- [ ] Local backend RLS/public-projection tests for owner, recipient, stranger and expired/revoked token; concurrency test one winner.
- [ ] Widget offline draft/unavailable claim, explicit owner handover confirmation, unknown allergen data and injected clock pickup expiry.

**Detaljni dokazi:** [stream C](../research/streams/C.md).

## F088 — Lične automatizacije, ograničen API i webhooks

**Vlasnik:** stream F. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
SyncedWriter outbox je account-scoped klijentski sync red, ne stabilan domen event stream; čita sadržaj u trenutku slanja. Nema integration credentials/subscriptions/event delivery tabele. UI ne sme direktno komunicirati sa n8n.

**Predložena izmena:**
[
  "Predlog IntegrationGrant(id, ownerUserId, householdId, tokenHash, scopes, resourceIds, expiresAt, revokedAt). Početno scopes plan:read, events:plan.confirmed; bez write/admin/ostava/profil sadržaja. Opaque token vezan za tačne resurse i aktivno članstvo proveravati pri svakom zahtevu; token nije Supabase user session.",
  "DomainEvent(id, type, schemaVersion, resourceId, revision, occurredAt, payloadProjection) stvara server tek po uspešnom autorizovanom potvrđivanju plana, u istoj transakciji sa zapisom i UNIQUE idempotency key. Uploader retry ne pravi novi događaj. Offline odobrenje stiže do servera kasnije; payload nosi occurredAt i acceptedAt. Klijentski mutable outbox ne koristiti za istorijski payload.",
  "WebhookSubscription(events, endpoint, allowedFields, grantId), Delivery(eventId, subscriptionId, attempt, nextAttemptAt, status). Slati minimalni snapshot izabranih polja; at-least-once, stabilan eventId, exponential backoff+jitter, max attempts/dead-letter, pregled statusa i izričit replay. Order po resource revision, ne obećavati globalni exactly-once.",
  "Signature HMAC-SHA256 nad stabilnim eventId.timestamp.rawBody; verzionisani secret uz rotaciju, constant-time receiver verification i vremenski replay prozor. Delivery endpoint zahteva https, server SSRF/public-address proveru posle DNS resolution-a i svakog redirekta (ili zabranu redirect-a), size/time limits. n8n private LAN nije podrazumevano dostupan cloud dispatcher-u; nuditi read-only polling sa ograničenim tokenom kad inbound endpoint nije moguć.",
  "Revoke/expiry/uklonjeno članstvo proveriti neposredno pre dispatch i svakog API read-a; pending delivery stop, nema daljeg čitanja. Secrets prikazati jednom; ne logovati URL auth/token/payload; audit samo bezbedni identifikatori/status. Capability probe endpoint handshaking/test event bez privatnih podataka; offline čuva nacrt konfiguracije, ne tvrdi uspešnu integraciju."
]

**Zavisnosti:** G010, G-SERVER, F064

**Male vertikalne celine:**
1. Read-only ograničen grant + minimalni API projection -> manual token revoke.
2. Server transaction event plan.confirmed + idempotency -> webhook test receiver.
3. Retry/dedup/replay/signature rotation i field selection -> n8n ili polling capability probe.

**Kriterijumi prihvatanja:**
- [ ] Token za plan A ne čita plan B, recepte van A ni profile; read-only token ne menja ništa.
- [ ] Jedno offline odobrenje uz 3 upload retry-a daje jedan DomainEvent; neuspešna transakcija daje 0.
- [ ] Receiver dobija isti eventId pri retry-u; tampered body/stari timestamp/unknown key odbijeni su u lokalnom receiver testu.
- [ ] Grant revoke i uklanjanje iz domaćinstva zaustavljaju sledeći API read i pending dispatch; endpoint koji resolve-uje na 127.0.0.1/link-local/private odbija se.
- [ ] UI status pending/retrying/failed/delivered razlikuje prihvatanje događaja od potvrđenog prijema kod primaoca.

**Verifikacija pri implementaciji:**
- [ ] Local DB transaction tests i dva naloga RLS za grants/subscriptions/events; unique idempotency/revision.
- [ ] Fake HTTP receiver: 2x500 pa 200, timeout, 429 retry-after, redirect-to-private, DNS rebinding simulation i response size limit.
- [ ] Known signature test vector nad tačnim bytes bez stvarnih secret-a; rotation overlap, time injection, replay rejection.
- [ ] Uploader/meal plan repository regression i signed-out/revoked token tests; n8n workflow demo tek posle capability probe, nije izveden ovde.

**Detaljni dokazi:** [stream F](../research/streams/F.md).

## F089 — Determinističko novo planiranje offline

**Vlasnik:** stream A. **Faza:** P2-foundation-first. **Status:** planirano.

**Postojeće stanje:**
lib/features/planning/plan_generation.dart orchestrates MealPlanAI; lib/ai/meal_plan_ai.dart:propose needs network. Existing lib/domain/meal_plan.dart:PlanDraft and MealPlanRepository.approve already support review, snapshots, protected entries and transactional shopping reconciliation.

**Predložena izmena:**
LocalPlanEngineV1(input: PlanRequest + typed rules + recipe/stock/history snapshots + today + rulesVersion; output: existing PlanDraft plus diagnostics/evidence). Strict candidate filter -> deterministic scorer -> bounded beam search across slots with shared allocateSupply ledger. Stable recipe IDs/slots break ties; no random UUID/time calls in engine. Search caps and deterministic node count provide partial/unsatisfiable diagnostics, not an optimality claim. Existing approve remains sole plan/shopping write path.

**Zavisnosti:** F003, F004, F058, G-RULES, G-PLANNER, G-PANTRY

**Male vertikalne celine:**
1. Add pure single-slot candidate chooser returning existing SlotProposal/library snapshot.
2. Extend to chronological multi-slot bounded search with shared stock and protected slots.
3. Connect offline option to existing preview/approve; add F005/F035/F048 scoring only as each lands.
4. Benchmark fixed node budget and expose unresolved constraints/unsupported free-text wishes.

**Kriterijumi prihvatanja:**
- [ ] Same serialized inputs/rulesVersion yield byte-equivalent normalized draft/evidence in 100 runs regardless recipe insertion order.
- [ ] All hard rules hold for every filled slot; no solution yields explicit empty slots/reasons, never unsafe fallback.
- [ ] Single 250 g stock across two 200 g slots records 150 g total shortfall, with no repeated stock allocation.
- [ ] Network-disabled generation makes zero AI/backend calls and persists nothing until approval.
- [ ] Target <=2 s for 31 days x3 slots x1,000 candidates with declared node cap/device; if unmet reduce candidate cap transparently without dropping hard rules.

**Verifikacija pri implementaciji:**
- [ ] Tiny exhaustive oracle verifies hard constraints and expected ranking; infeasible and locked/cooked replacement cases.
- [ ] Permutation/property tests for determinism, quantity conservation, unknowns and cancellation/node cap.
- [ ] Offline widget generation/edit/approve, stale fingerprint and outbox idempotency regression; measured benchmark.

**Detaljni dokazi:** [stream A](../research/streams/A.md).

## F090 — Zauzetost iz kalendara

**Vlasnik:** stream B. **Faza:** P3. **Status:** planirano.

**Postojeće stanje:**
lib/domain/plan_calendar.dart: CivilDate i PlanRequest nemaju instant intervale; postojeći generation koristi ručne izbore. Nema calendar availability gateway-a u pregledanim planning fajlovima.

**Predložena izmena:**
AvailabilityGateway.probe()->supported|permissionRequired|unavailable i query(window,calendarSelection)->BusySnapshot{intervals[startUtc,endUtc),zoneId,fetchedAt,expiresAt,coverageErrors}; samo zauzetost, bez naslova/opisa/lokacije/ucesnika. Lokalni algoritam oduzima uniju intervala od ručnog prozora, predlaže raspored uz aktivno/ukupno vreme. Provider dozvole ostaju zasebne od ICS bearer linka; ručni prozori ostaju dostupan fallback.

**Zavisnosti:** F034, G-TIME, G-AVAILABILITY

**Male vertikalne celine:**
1. Fake gateway i ručni prozor sa intervalnim algoritmom.
2. Jedan uslovni provider adapter sa najmanjim dokazano dovoljnim freebusy scope-om i eksplicitnim izborom kalendara.
3. Preview predloga, svežina/greške i potvrda novog termina; offline koristi označen cache ili ručni prozor.

**Kriterijumi prihvatanja:**
- [ ] Prozor 17:00–20:00 i busy [18:00,19:00) daju slobodno [17,18) i [19,20); recept 45 min nudi 17:00 ili 19:00, 90 min ne staje.
- [ ] Interval koji se završava u 18:00 ne blokira start 18:00; preklopljeni busy intervali se spajaju.
- [ ] 403, nepoznata parcijalna greška, denied/unsupported i istekao cache ne znače Slobodno; korisnik vidi Zauzetost nije proverena.
- [ ] Nijedan detalj spoljnog događaja ne ulazi u PlanDraft, AI prompt, telemetry ili household sync; potvrda ne piše u spoljni kalendar.

**Verifikacija pri implementaciji:**
- [ ] Domain prazni/dupli/prekonoćni intervali, granice, DST u Europe/Belgrade i conversion UTC->lokalni dan.
- [ ] Fake adapter delimičan calendar error, revoke, token expiry, stale TTL i offline; isključenje briše cache i prekida refresh.
- [ ] Contract fixture samo busy start/end; capability test na svakoj ciljnoj platformi pre javnog obećanja podrške.

**Detaljni dokazi:** [stream B](../research/streams/B.md).
