# Stream C — ostava, količine i računi

Datum: 9. novembar 2026. Status: proverljiv blueprint, bez implementacije novih funkcija. Osnova: Tavli `1eca2c3d14fb5dd9b25a42958aa018c8d8dfbb94`. Ovaj izveštaj pokriva tačno 15 ID-jeva iz streams.json. Ne tvrdi da je cilj 010 već završen.

## Posmatrano postojeće stanje

- `lib/app/router.dart` ruta `/pantry` vraća `EmptyStateScreen`; `lib/features/shopping/shopping_providers.dart` izričito opisuje repo kao „za sada samo prijem kupljenog”. Ostava nije završen inventar.
- `lib/data/database.dart::PantryItems` ima količinu kao nullable REAL, jedinicu, expiresAt, confirmedAt, sourceShoppingItemId, householdId; schemaVersion=5. Nema lokacija, tare, otvorenih pakovanja, računa, kaucija ni gotovih tura.
- `lib/data/pantry_repository.dart::receivePurchases` prima samo kupljene stavke u odgovarajućem domaćinstvu; ponovni prijem preskače postojeći sourceShoppingItemId u lokalnoj transakciji. `watchReceivedItemIds` pokreće prikaz prijema. Ovo samo po sebi nije dokazana server-side zaštita od istovremenog prijema na dva uređaja.
- `lib/domain/shopping_demand.dart::demandFor/toMicros/normalizeUnit` poredi u milionitim delovima g/ml/kom; g↔kg i ml↔l su poznate konverzije. Nepoznate mere/količine ne pretvarati u numeričku pokrivenost. Fiksna preciznost je u obračunu; postojeća skladišna polja nisu sva integer — ne prepisivati istoriju kao da jesu.
- `lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply` spaja kupovinu i prijem kao isti kapacitet, raspoređuje potražnju hronološki i zatim zalihe po ID-ju. Nema FEFO izbora.
- `lib/data/shopping_repository.dart::_reconcile` učitava potvrđene količine ostave, isključuje istekle redove, zatim kupljene stavke; `_buy` zamrzava purchaseProvenanceJson. Postojeće validne raspodele se čuvaju koliko kapacitet dopušta.
- Važan rizik za ciljane funkcije: kada primljena zaliha istekne ili dobije nepoznatu količinu, filter može izbaciti njen pantry red, a stari bought red ostaje kandidat. Novi inventar mora eksplicitno potisnuti taj fallback za potrošen/istekao/nepoznat fizički koren. Ovo je uočeni rizik iz čitanja koda, nije ovde reprodukovan testom niti popravljen.
- `lib/data/meal_plan_repository.dart::setCooked`, `lib/domain/meal_plan.dart::RecipeSnapshot`, `MealPlanEntries.recipeSnapshotJson` nose kuvanje/snimak recepta, ali ne stvarnu masu skuvanog jela. `lib/sync/entities.dart::SyncEntity/EntityScope` i `lib/sync/synced_writer.dart::SyncedWriter` ostaju jedini put korisničkih upisa.
- Postojeće polazište provera: `test/data/pantry_repository_test.dart` (ponovni prijem i izolacija), `test/domain/supply_allocation_test.dart` (jednokratna raspodela/nepoznata količina), `test/data/shopping_repository_test.dart`, `test/domain/shopping_demand_test.dart`. Nisu pokrenuti u ovom istraživanju.

## Zajednički ugovori i redosled

**G010:** završiti osnovni pantry UI/CRUD i postojeći plan→nabavka scenario pre naprednih slojeva. Ne graditi drugu ostavu. Novi UI nazivi: „Lokacija”, „Proveri količinu”, „Količina nije poznata”, „Otvoreno”, „Dopuni zalihu”, „Pregled računa”, „Potvrdi kupljeno”, „Težina posude”, „Neto sadržaj”, „Gotovo jelo”, „Ponudi višak”; svi tekstovi na srpskoj latinici.

**GQ — quantity contract:** jedan iznos je `{micros:int, unitGroup, baseUnit}`; null ostaje nepoznat. Decimalni tekst parser ne koristi binarni floating point za nova merna/računska polja. Postojeća REAL polja mapirati kroz postojeći toMicros, uz migracione round-trip fixture; eventualna migracija skladištenja je zaseban pregledan korak. Postaviti bezbedne opsege i proveriti overflow za množenje/rounding. Bez gustine nema g↔ml; broj pakovanja nije sadržaj pakovanja.

**GTX — fizički kapacitet i transakcije:** nadograditi PantryRepository i ShoppingRepository, ne paralelni inventar. `StockOperation(operationId, householdId, kind, expectedRevision, occurredAt, physicalRootId, signedMicros, reason, evidenceRef)` ima idempotentni ključ na serveru i u drift-u. Trenutni PantryItems ostaje projekcija preostalog kapaciteta; postojeće primljene količine se backfill-uju kao početno stanje, ne kao nova kupovina. Isti command transakciono menja stanje, rezervacije i outbox. Korekcije su kompenzacije sa vezom na original. Server mora atomarno proveriti reviziju/kapacitet; konflikt prikazati kao „Stanje je u međuvremenu promenjeno. Proveri količinu.” Lokalni outbox sam ne rešava dve istovremene potrošnje. Ako budu potrebne server komande/RPC, schema/RLS/grants i retry-ack ugovor su obavezni pre objave.

Fizički koren kupovine ima jedan ukupan kapacitet. Jednostavan prijem zadržava postojeći sourceShoppingItemId/samePhysicalAs. Više lotova istog prijema zahteva eksplicitne porcije fizičkog korena; trenutni canonicalId algoritam bi sve identične korene kolabirao na jedan red. Ne dodavati takve child redove bez novog konzervacionog modela i regresija. Iste grame ne smemo sabrati kao kupovinu+prijem+otvoreni paket+premeštenu zalihu. Nepovratno potrošeni/istekli koren ne oživljava kroz staru kupovinu.

**GADAPTER:** mreža samo u data adapteru; cache UI čita iz drift-a. Razdvojiti `found/notFound/unavailable/unsupported/stale`, vremenske oznake i poreklo. Dohvat nikad ne potvrđuje količinu niti pravi upis ostave. Testovi imaju fake Dio i ne idu na mrežu. Ne čuvati podatke dobavljača pomešane sa ručno potvrđenom kućnom zalihom.

**GSHARE:** deljenje hrane traži minimalnu posebnu projekciju, opoziv i atomsko preuzimanje, ne proširenje opšteg pantry RLS na strance. Prvo privatni nacrt; bez javnog feed-a ili slanja poruka u ovom zadatku.

Predloženi redosled: G010/GQ/GTX → F039+F036 → F038 → F006/F037/F040 → F042 i F017 (ručno pakovanje radi bez OFF) → F073 → F074 → zajednički CookedBatch F013/F012/F075 → F072 → F083/F087 uslovno. Feature faze P1/P2/P3 su predložene; zavisnosti imaju prednost nad fazom. F013 može prvo ručne porcije bez merenog prinosa; F075 zatim dodaje masu istom modelu. Stream B poseduje F012; D poseduje F018/F067; E poseduje F076; F poseduje F064. Uskladiti ugovore pre implementacije, bez menjanja njihovih fajlova.

## Javne integracije i Srbija

OFF adapter je za identitet/katalog proizvoda. Open Prices adapter je za zabeležene cene, dokaz, datum i poslovnicu. Nijedan nije proverena zaliha prodavnice. SDK podržava rs/SRB, RSD i srpski jezik u kodu; to nije empirijska pokrivenost tržišta. Ovo istraživanje nije pozivalo njihove produkcijske API-je, trgovce niti Tavli backend. Zato nema izmišljenog broja srpskih proizvoda, procenta pokrivenosti korpe ili obećanja o aktuelnoj dostupnosti u Srbiji.

Budući dobrovoljni probe: OFF najmanje 30 stvarnih lokalnih barkodova, found/total i potvrđeno pakovanje/found; Open Prices filtriranje country/location i currency RSD pa datumi/sveža opažanja, bez tvrdnje da je currency=RSD dokaz zemlje. Zabeležiti prazne rezultate i nazivnik. F083 dodatno zahteva zvanično dozvoljen retailer API, mapu SKU→poslovnica→termin, vreme opažanja i SLA isteka; u suprotnom „Dostupnost nije proverena”. Ručni unos ostaje koristan. Ne slati privatne račune u Open Prices bez zasebne izričite korisničke akcije.

Zvanična dokumentacija: [OFF API](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/), [OFF Dart](https://openfoodfacts.github.io/openfoodfacts-dart/), [Open Prices](https://openfoodfacts.github.io/open-prices/). Licenca koda ne daje automatski dozvolu za redistribuciju baze/fotografija: OFF navodi ODbL za podatke i posebne uslove za slike. Za runtime adapter ograničiti cache, pripisati izvor i proveriti konkretan režim ponovne upotrebe pre distribucije; ovaj paket ne kopira dataset ili slike.

## Plan po predlogu

### F006 — Minimalna zaliha (P2)

**Postojeće stanje:** lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. No threshold or replenish policy; lib/app/router.dart /pantry is EmptyStateScreen.

**Ugovor / predložena izmena:**

- Add household ReplenishmentPolicy(id, ingredientKey, unitGroup, minimumMicros, targetMicros, active); require target >= minimum >= 0.
- Build a read-only replenish proposal using canonical confirmed usable stock, unresolved reservations, bought-not-received supply and compatible open shopping coverage. Desired total demand = max(existing recipe demand, target stock gap) under a stated policy, never blindly add recipe demand plus gap. Explicit approval creates a stable replenish source, reused on retry; no automatic purchase.

**Zavisnosti:** G010, GQ, GTX, F039.

**Male vertikalne celine, redom:**

1. Read-only minimum/target editor and preview with deterministic domain tests.
2. Approve into current ShoppingRepository contribution/source model; sync policy and source with RLS.
3. Add pantry low-stock filter and user-controlled reminders only after proposal behavior is stable.

**Merljivo prihvatanje:**

- Stock 200 g, minimum 300 g, target 1000 g produces 800 g proposal; compatible unbought coverage 500 g leaves 300 g additional.
- Equality with minimum creates no prompt; unknown stock asks for review; repeated approval creates one source and preserves bought items.

**Konkretne buduće provere:**

- Domain fixtures for threshold equality, two equivalent units, unknown quantity, expired lot, shared purchase/receipt identity and existing shopping.
- Repository fake-backend test: approve twice, receive once, reconcile twice; no duplicate source or capacity.

### F013 — Zamrznuti gotovi obroci (P2)

**Postojeće stanje:** lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. lib/data/meal_plan_repository.dart::setCooked only changes cooked state; MealPlanEntries has recipeSnapshotJson but no cooked-batch inventory.

**Ugovor / predložena izmena:**

- Use cooked PantryItems with supplyKind=cooked and CookedBatch metadata (batchId, recipeSnapshot, preparedAt, frozenAt, confirmed portions or mass, thawReminderAt). Do not match cooked food to raw ingredients by name.
- Meal entry can draw portions from one batch using CookedBatchAllocation; reserving/reheating never generates raw demand again. Cooking consumes ingredients only after explicit confirmation; recording batch output uses the same operation id.

**Zavisnosti:** G010, GTX, F012, F038.

**Male vertikalne celine, redom:**

1. Manual cooked-batch creation and listing linked to PantryItems; no automatic ingredient decrement.
2. Link batch reservations to plan and remove duplicate raw demand in explicit batch mode.
3. Add optional local thaw reminder capability gate and snapshot-preserving sync.

**Merljivo prihvatanje:**

- Cook six portions once, freeze four, reserve two on each of two future meals: cooked available=0 and raw demand occurs once.
- Declining notifications or offline operation still allows manual frozenAt/thaw preparation; recipe deletion preserves batch snapshot.

**Konkretne buduće provere:**

- Domain batch conservation fixtures; repository test cooking retry and reserve/cancel/reheat.
- Widget test list frozen batches, edit portions, select meal; fake clock notification deny/unavailable test.

### F017 — Barkod i pakovanje (P2)

**Postojeće stanje:** lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. No barcode/catalog adapter observed; camera/AI recipe import is not a product scanner.

**Ugovor / predložena izmena:**

- Introduce ProductLookup.lookupBarcode(code) -> found/notFound/unavailable/invalid with CatalogProduct(source, sourceId, barcode, names, brand, quantityText, parsedPackage?, fetchedAt). Cache external responses separately from pantry.
- OpenFoodFactsAdapter selects name/quantity/product_quantity fields, identifies app User-Agent, times out and respects rate limits; supported Serbian language/country tags do not guarantee coverage. User confirms ingredient identity and package amount before supply creation; allow manual entry without camera or network.

**Zavisnosti:** GADAPTER, GQ, F039.

**Male vertikalne celine, redom:**

1. Pure barcode/result/parser contract and manual input, with tests.
2. Read-only OFF adapter/cache and preview; record attribution/data-license boundary.
3. Optional device scanner capability and explicit confirmed product-to-ingredient mapping.

**Merljivo prihvatanje:**

- A found 500 g package shows editable proposal without pantry write until confirmation; 404, 429, malformed quantity and offline cache miss all retain manual flow.
- Barcode leading zeros survive; volume and mass cannot be interchanged; country rs filter is not a local-stock claim.

**Konkretne buduće provere:**

- Fake Dio fixtures for found/missing/429/timeout, multipack 6x125 g and unparsed labels; no live network tests.
- Camera capability/permission-denied widget tests on phone and desktop; duplicate scan event creates no duplicate receipt.
- Future Serbia pilot: user-consented basket of at least 30 local products; report found/30, correct package/found, missing translation and observed date; no coverage claim until measured.

### F036 — Lokacije namirnica (P1)

**Postojeće stanje:** lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. No location field/table; /pantry remains placeholder.

**Ugovor / predložena izmena:**

- Add PantryLocation(id, householdId, name, active) and nullable locationId on PantryItems. Unknown location remains null; default labels Frižider/Zamrzivač/Ostava are editable.
- Move whole lot updates the same pantry id and canonical physical identity. A partial move requires split children and conservation under GTX; do not create extra capacity.

**Zavisnosti:** G010, GTX.

**Male vertikalne celine, redom:**

1. Add nullable location metadata with migration and sync/RLS.
2. Whole-lot move and filtered pantry UI.
3. Only then partial move with split transaction and 200+300=500 g fixture.

**Merljivo prihvatanje:**

- Move 500 g pantry lot from Ostava to Frižider: global stock remains 500 g, existing allocations remain valid, sourceShoppingItemId unchanged.
- Cross-household location rejected; deleting location reassigns to unknown and retains food.

**Konkretne buduće provere:**

- Repository move+retry and location filter tests; two-account RLS and outbox replay.
- Phone/wide widget tests null/renamed/archived location and offline move.

### F037 — Otvoreno pakovanje (P2)

**Postojeće stanje:** lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. expiresAt is single date; no openedAt or opened-use-by provenance.

**Ugovor / predložena izmena:**

- Add lot openedAt, labelUseByAt, openedUseByAt, dateEvidence and dateKind. Opening alone does not change mass; effective usable date is the earliest applicable confirmed date.
- User enters/confirms after-opening date from declaration. Never infer safety interval from barcode/name or AI. Keep original manufacturer date and disclose unknown date.

**Zavisnosti:** F038, F039, GTX.

**Male vertikalne celine, redom:**

1. Model separate dates/evidence and migration without populating invented dates.
2. Manual opening preview and confirmation; reconcile stock eligibility.
3. Optional reminders from effective confirmed date with permission-denied fallback.

**Merljivo prihvatanje:**

- Original date 20 Nov, confirmed after-opening 12 Nov => effective 12 Nov; opening twice preserves original openedAt unless explicitly corrected.
- Missing after-opening rule remains unknown, not a calculated safe lifetime; mass unchanged.

**Konkretne buduće provere:**

- Injected-clock unit tests before/equal/after dates and timezone civil date handling.
- Repository stale edit conflict and widget user-confirmed label evidence, no-date flow.

### F038 — Odvojene ture iste namirnice (P2)

**Postojeće stanje:** lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. PantryItems IDs can already represent separate rows; allocateSupply currently sorts supply canonical IDs, not expiry; receipts assume at most one pantry row per shopping item in receivePurchases.

**Ugovor / predložena izmena:**

- Treat existing PantryItems as lots, add lot metadata only; same ingredient can have multiple lots. Add expiry-priority selection after demand ordering: confirmed earliest eligible expiry first, unknown last, stable id tie-break; preserve valid historical reservations until user requests rebalance.
- For splitting a received purchase create PhysicalSupply root plus portions or explicit receipt-line children. Replace one-to-one receipt lookup only with defined migration/unique operation key; sum children <= root remaining. Never set every split child samePhysicalAs to the whole root because current canonical dedupe would collapse them.

**Zavisnosti:** G010, GQ, GTX.

**Male vertikalne celine, redom:**

1. Document and test physical-root/portion representation against existing canonical algorithm before schema changes.
2. Add lot dates and FEFO proposal while retaining current single-row receipts.
3. Add optional split/merge with root conservation, unique operation keys and outbox atomicity.

**Merljivo prihvatanje:**

- Lots 300 g expiring 12 Nov and 400 g expiring 20 Nov cover demand 500 g as 300+200 on a new allocation; remaining 200 g.
- Split purchased 1000 g into 400+600 g, repeat operation and receive retry: confirmed total stays 1000 g, never 2000 g; expired received lot must not reappear through bought fallback.

**Konkretne buduće provere:**

- Extend test/domain/supply_allocation_test.dart for FEFO, unknown expiry, ties, retained reservation and split conservation.
- Repository fixture purchase->receipt->split->expire->reconcile; sync replay and two-device identical operation conflict.

### F039 — Brza provera inventara (P1)

**Postojeće stanje:** lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. confirmedAt exists; no general pantry CRUD/inventory workflow. ShoppingRepository._reconcile checks non-null confirmation, but does not enforce a freshness age.

**Ugovor / predložena izmena:**

- Extend PantryRepository confirmQuantity/markEmpty/markUnknown with operation id, clock and expected revision. Known uses micros; empty is confirmed zero; unknown is null with a separate checkedAt and confidence state.
- Keep checkedAt distinct from quantityConfirmedAt. Define explicit user-configurable freshness policy rather than silently invalidating old stock. A received purchase marked unknown/empty must suppress bought-item fallback for the same physical root.

**Zavisnosti:** G010, GQ, GTX.

**Male vertikalne celine, redom:**

1. Add pure confidence/freshness contract and regression tests for received-root fallback.
2. Implement repository commands with transactional reconcile and outbox.
3. Replace pantry placeholder with list and quick confirm editor.

**Merljivo prihvatanje:**

- Known 250 g -> unknown results in no numeric allocation; empty gives zero; repeating confirmation never increases stock.
- With bought 250 g received and then marked empty, 100 g new demand remains 100 g, rather than being covered by the old bought record.

**Konkretne buduće provere:**

- Repository fixtures known/unknown/empty across purchase receipt aliases, stale revision and fake clock.
- Widget quick inventory offline, undo explicit correction, phone/wide, text 2x; RLS two households.

### F040 — Dnevnik bačene hrane (P2)

**Postojeće stanje:** lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. No food movement/waste reason log; isCooked is not a waste entry.

**Ugovor / predložena izmena:**

- Add stock movement reason waste and immutable WasteDetail(movementId, lotId, amountMicros, unitGroup, reason, occurredAt, optional amountMinor/currency). Waste and eaten movements remain distinct; no inferred monetary value.
- Approval subtracts confirmed capacity and recalculates affected reservations atomically; reversal creates compensating movement. Unknown quantity may be logged as qualitative but never used in numeric waste totals.

**Zavisnosti:** GTX, F038, F039.

**Male vertikalne celine, redom:**

1. Add typed reason and confirmed waste preview with numeric tests.
2. Post atomic movement and recompute reservations; sync and RLS.
3. Read-only monthly totals by compatible unit and cost currency with unknown coverage.

**Merljivo prihvatanje:**

- 500 g lot - 120 g waste = 380 g; retry same operation remains 380 g; reversal restores 500 g once.
- Report displays 120 g waste independently from consumption and excludes missing price from cost sum with coverage count.

**Konkretne buduće provere:**

- Domain conservation and negative/overflow tests; repository rollback on outbox error.
- Widget reason/amount review, compensation and fake clock monthly boundary.

### F042 — Kupovina celih pakovanja (P2)

**Postojeće stanje:** lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. ShoppingNeed/micros summarize compatible demand; no package-size or rounding model; shopping row quantity currently doubles as purchase quantity.

**Ugovor / predložena izmena:**

- PackageOption(productId, contentMicros, unitGroup, packCount, confirmedAt) feeds pure PackageProposal. n=(need+pack-1)~/pack, surplus=n*pack-need for positive integer pack; zero need ->0 packs. Keep exact recipe demand separate from proposed/actual purchase.
- Only confirmed actual bought content becomes supply; surplus may enter pantry once through existing receipt link. Unknown size/dimension mismatch retains exact need and asks for package confirmation.

**Zavisnosti:** GQ, F017, F038.

**Male vertikalne celine, redom:**

1. Pure integer rounding preview with a manually entered package size (F017 optional).
2. Persist proposal separate from frozen purchase provenance; confirm actual bought amount.
3. Catalog-assisted package choice and optional multiple-size optimization only as later separate slice.

**Merljivo prihvatanje:**

- 750 g need with 500 g package proposes 2 packages/1000 g and 250 g surplus; 1000 g need proposes 2/0 surplus.
- 100 g pantry plus 2 bought 500 g packs can cover at most 1100 g across plans and preparations; receipt creates no additional capacity; reject zero package.

**Konkretne buduće provere:**

- Integer fixtures 0,1 micro,exact multiples, huge safe bounds, unknown and mass/volume mismatch.
- Repository buy actual quantity different from proposal then receive twice, edit plan, preserve purchase history.

### F072 — Povratna ambalaža i kaucije (P3)

**Postojeće stanje:** lib/data/database.dart::ShoppingItems/PantryItems have no deposit, container-return or currency ledger; existing shopping provenance is food purchase only.

**Ugovor / predložena izmena:**

- Add ReturnableType and ReturnableMovement with units signed by issue/return, depositMinor, currency, purchaseOperationId, returnedAt and expectedRevision. Track container count separately from edible stock and from tare.
- Receipt classification can link a deposit line to container issue; partial return decreases held count and records actual refund, without pretending the food was returned. No assumed Serbian national scheme, retailer support or refund amount.

**Zavisnosti:** GTX, F073.

**Male vertikalne celine, redom:**

1. Manual issue/return model and balance screen with currency tests.
2. Atomic ledger and compensation with household RLS.
3. Optional receipt classification after F073; no retailer integration promised.

**Merljivo prihvatanje:**

- Buy six bottles at 20 RSD deposit => held 6/paid120 RSD; return four and receive80 => held2/net deposit40; duplicate return operation has no effect.
- Mixed currencies never sum; deposit-only receipt line contributes zero grams to pantry.

**Konkretne buduće provere:**

- Known integer minor-money/count fixtures and partial-return/over-return/reversal.
- Fake-backend two-account isolation; receipt duplicate and offline conflict tests.

### F073 — Poravnanje kupovine sa računom (P2)

**Postojeće stanje:** lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. ShoppingRepository.setBought/_buy freezes purchaseProvenanceJson; receivePurchases keys by shopping item; no receipt document, OCR rows or actual-quantity reconciliation.

**Ugovor / predložena izmena:**

- ReceiptDraft(documentHash, merchantText, purchasedAt, currency, parserVersion, rows) is private and separate from confirmed stock. Row includes source row ordinal, raw label, parsed quantity/unit/price, classification(food/deposit/discount/return), candidate matches and review status.
- AI/OCR through AIRouter proposes only. ConfirmReconciliation(operationId, expectedDraftRevision, accepted mappings) posts actual purchased quantities and receipt links, then receives the same physical supply in one transaction/outbox group. Unique household+receiptId+rowId+action prevents retry duplicates; document hash warns about possible duplicate, never auto-merges legitimate identical receipts.
- A bought row can span several lots/receipts: use explicit purchase/receipt lines and root conservation (F038). Preserve original demand and frozen purchase history; corrections after confirmation use compensating differences, not delete/recreate. Receipt image private and optional; no automatic public Open Prices upload.

**Zavisnosti:** GTX, GQ, F038, GADAPTER.

**Male vertikalne celine, redom:**

1. Manual receipt draft and row matching UI with no stock writes; pure parsing tests.
2. Confirm single-line receipt using existing setBought/receive identity and operation id.
3. Add multiline/split/partial reconciliation and corrections with transactional outbox and concurrency constraints.
4. Optional photo/text extraction through AIRouter only after manual confirmation flow passes.

**Merljivo prihvatanje:**

- List asks750 g; receipt confirms2x500 g: demand stays750 g, actual supply1000 g, remainder250 g; confirming/replaying twice creates one purchase and one receipt supply.
- Already marked bought then receipt reconciliation does not add a second1000 g; ambiguous kg/kom/price line stays unposted until reviewed.
- Food, deposit, discount, unlisted product and returned item are reviewed separately; declining draft writes no purchase/stock.

**Konkretne buduće provere:**

- Fake AI and malformed OCR fixtures, decimal comma, weighed produce, multipack, duplicate scan, same-content different receipt and mixed units.
- Repository atomic failure injection before/after each row and retry; existing bought->received path; concurrent same-operation unique-key race; exact 750/1000/250 fixture.
- Widget editable matching preview, rejection/manual rows and private image access; local Supabase two-account RLS, no external API.

### F074 — Težina posude i neto sadržaj (P2)

**Postojeće stanje:** lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. No container/tare/gross fields; current normalizeUnit keeps mass separate from volume.

**Ugovor / predložena izmena:**

- Container(id, householdId, label, tareMicros, massUnit, verifiedAt) is distinct from product, returnable deposit type and food lot. Measurement(id, containerId, lotId, grossMicros, tareSnapshotMicros, measuredAt, expectedRevision) proposes net=gross-tare.
- Confirm replaces remaining mass by a correction movement, never adds the net as a new receipt. Reject gross<tare and unknown tare; manual entry always available without Bluetooth. Tare snapshot preserves history when empty jar mass changes.

**Zavisnosti:** GTX, F039, F038.

**Male vertikalne celine, redom:**

1. Pure mass-only tare calculator and editable container profile.
2. Confirm measurement onto one existing lot with atomic correction and outbox.
3. Optional container label lookup; device input belongs F076 and is not required.

**Merljivo prihvatanje:**

- Gross842 g minus tare312 g =530 g net (530000000 micros); if prior600 g, correction is-70 g; repeated operation remains530 g.
- Gross300<tare312 rejected; volume lot cannot silently become mass; editing container later does not rewrite measurement history.

**Konkretne buduće provere:**

- Pure gross/net validation fixtures including zero/unknown and precision boundaries.
- Repository correction invalidates over-reservation; fake clock, stale revision, duplicate command; widget manual measurement and undo.

### F075 — Stvarni prinos nakon kuvanja (P2)

**Postojeće stanje:** lib/domain/shopping_demand.dart::scaleQuantity/demandFor scale raw input to servings; lib/domain/meal_plan.dart::RecipeSnapshot and lib/data/meal_plan_repository.dart::setCooked do not measure final mass.

**Ugovor / predložena izmena:**

- Extend CookedBatch (F013 shared contract) with yieldMeasurementId, finalNetMicros, measuredAt, recipeSnapshot, cookedOperationId. Gross yield can use F074 tare; measured water loss does not rewrite raw ingredient purchase demand.
- Portion allocations consume confirmed cooked mass; equal portions use integer quotient/remainder with visible final residual. Label serving count approximate when uneven; nutrition is a separate F046 estimate and cannot infer mass from energy.

**Zavisnosti:** GTX, F013, F074, F012.

**Male vertikalne celine, redom:**

1. Manual finished net mass entry on the shared CookedBatch model.
2. Mass-based portion allocation with conservation and optional F074 gross/tare.
3. Plan-linked servings and later read-only yield comparisons for same recipe version.

**Merljivo prihvatanje:**

- 1800 g finished batch into six equal portions =>300 g each; allocate2 portions600 g ->1200 g remains; new meal using these portions creates no raw demand.
- 1000 g/3 stores333333333,333333333,333333334 micros (sum1000000000); reweigh remaining is explicit correction, not a second batch.

**Konkretne buduće provere:**

- Known yield/tare and integer residual fixtures; no sum drift on split/recombine.
- Repository cook once -> record yield twice -> freeze -> reserve -> eat; raw-input demand never doubles, recipe source deletion keeps snapshot.

### F083 — Dostupnost konkretnih proizvoda (P3)

**Postojeće stanje:** No retailer stock adapter in lib/data; OFF product metadata and Open Prices historical observations are external sources, neither is household Supply nor proof of live shelf stock.

**Ugovor / predložena izmena:**

- RetailAvailabilityAdapter.probe(country, retailer, branch, fulfillmentSlot) reports supported/unsupported/authRequired/temporarilyUnavailable with capabilities. AvailabilityObservation(productCode, retailerSku, branchId, slot, status[inStock,outOfStock,unknown], observedAt, expiresAt, source, evidence) is cached separately.
- Only authorized documented retailer data with actual branch/slot semantics can produce inStock. Price history or OFF stores/countries tags remain metadata; stale result becomes unknown. No Serbian retailer is confirmed supported in this research; ship manual dated observation plus unavailable state until a lawful adapter is verified.

**Zavisnosti:** GADAPTER, F017, F018, F067.

**Male vertikalne celine, redom:**

1. Define availability contract and manual dated observation, default unknown.
2. Add isolated cache and fake adapter test suite; no production integration claim.
3. Enable one Serbian retailer only after capability/terms/data validation, with feature flag and expiry policy.

**Merljivo prihvatanje:**

- Open Prices price from yesterday yields unknown availability; branch A inStock cannot satisfy branch B or a different slot.
- Timeout, unsupported Serbia retailer, missing SKU and expired observation show „Dostupnost nije proverena” with last checked time; household stock and shopping quantities do not change.

**Konkretne buduće provere:**

- Fake adapters for supported, denied, stale, branch mismatch and late/out-of-order response.
- Future capability audit: official API terms/endpoint/branch identity/slot semantics, sample freshness SLA and Serbian test branch evidence before enabling retailer.
- Widget source/date display and manual observation correction; never use a live retailer in unit tests.

### F087 — Ponudi višak hrane (P3)

**Postojeće stanje:** lib/data/database.dart::PantryItems stores nullable REAL quantity/unit, expiresAt, confirmedAt and sourceShoppingItemId; lib/data/pantry_repository.dart::PantryRepository.receivePurchases is transactional/idempotent locally; lib/domain/shopping_demand.dart::toMicros/normalizeUnit and lib/domain/supply_allocation.dart::Supply.canonicalId/allocateSupply preserve confirmed compatible capacity. Household-scoped sync exists in lib/sync/entities.dart::EntityScope; no public offer/claim or external transfer model.

**Ugovor / predložena izmena:**

- FoodOffer(id, ownerHouseholdId, lotId, quantityMicros/unitGroup, confirmedDescription, ingredients/allergensAsDeclared, preparation/storage facts, pickupWindow, state, revision) exposes only explicitly chosen facts. Unknown remains unknown; do not label food safe from date alone.
- Offer reservation removes offered amount from planner-available capacity without consuming it. Claim/withdraw/expire do not transfer stock. Owner confirms handover -> single transfer-out movement; recipient can independently confirm receipt under a new household root linked by opaque handover reference, not access donor inventory.
- First slice private revocable unguessable link to named recipient; no public discovery/location feed. Exact address/contact shared only explicitly; auth/authorization for claiming and atomic single-winner transfer gate required online. Offline supports draft and queued owner correction, not two conflicting successful claims.

**Zavisnosti:** GTX, F038, F039, F064, GSHARE.

**Male vertikalne celine, redom:**

1. Private offer draft and local quantity reservation only, no external publish.
2. Revocable minimal projection and online atomic claim; permission/RLS tests.
3. Owner-confirmed handover movement and optional independent recipient receipt; no automatic chat/email sent.

**Merljivo prihvatanje:**

- Offer300 g from500 g leaves200 g available; withdraw/expire restores500 g; confirmed handover leaves200 g and retry does not subtract again.
- Two claimants racing produce one accepted claim; recipient reads no other pantry row; link revocation removes offer access; exact pickup location absent from public payload.

**Konkretne buduće provere:**

- State machine fixtures draft->offered->claimed->handedOver and cancel/expire; reservation conservation and handover retry.
- Local backend RLS/public-projection tests for owner, recipient, stranger and expired/revoked token; concurrency test one winner.
- Widget offline draft/unavailable claim, explicit owner handover confirmation, unknown allergen data and injected clock pickup expiry.

## Migracije, kompatibilnost i test gate

Svaka funkcija ide kao zaseban spec/branch sa malim koracima. Novi nullable metadata može prvo bez promene postojećih količina. Ne backfill-ovati izmišljeni datum, količinu, lokaciju, masu ili rok posle otvaranja. Nove tabele/kolone traže drift schemaVersion bump, generated kod samo build_runner-om, novu Supabase migraciju, household-scoped RLS i authenticated grants. SyncEntity mora znati roditelje, redosled, nullable legacy podatke i toRemote/fromRemote; brisanje/preimenovanje lokacije ne briše fizičku hranu. Inicijalne stock-operation projekcije moraju imati isti kapacitet kao pre migracije i ne praviti nove prijeme.

Receipt root/lot i pokrivenost nabavke su najrizičniji deo: migraciona fixture treba da sadrži kupljeno ali neprimljeno, kupljeno+primljeno, dve pripreme istog recepta, isteklo, null količinu, skuvan obrok sa zadržanom rezervacijom i dve nedelje istog plana. Pre/posle porediti ukupnu fizičku količinu i preostalu nabavku. Server zaštita od dve istovremene akcije mora biti proverena u lokalnoj bazi; last-write-wins nije prihvatljivo za transfere/količine.

Pri stvarnoj implementaciji: test-first domen i parseri, relevantni repository/widget testovi, lokalni Supabase testovi sa dva naloga i replay/race fixture, formatter/analyze, puna Flutter suite i macOS smoke kada se menja zajednički kod. Telefon/široko/tekst2x, offline i denied permission su kriterijumi. Ove provere ovde nisu pokretane: nema izmena aplikacije.

## Izvorni kod — tačni pinovi i odluke

### https://github.com/grocy/grocy

Commit `41206cb90154e0d17d3e108cc1f182b94fdb465d`; licenca MIT.

- [`LICENSE.md`](https://github.com/grocy/grocy/blob/41206cb90154e0d17d3e108cc1f182b94fdb465d/LICENSE.md), `MIT license grant`: Copyright (c) 2017-2026 Bernd Bestel; permissive with preserved notice.
- [`services/StockService.php`](https://github.com/grocy/grocy/blob/41206cb90154e0d17d3e108cc1f182b94fdb465d/services/StockService.php), `AddMissingProductsToShoppingList/GetMissingProducts`: Missing stock creates/updates shopping amount rather than blindly appending; uses float/round two decimals, so accounting must not be ported over Tavli micros.
- [`services/StockService.php`](https://github.com/grocy/grocy/blob/41206cb90154e0d17d3e108cc1f182b94fdb465d/services/StockService.php), `AddProduct/ConsumeProduct/InventoryProduct`: Tare modifies gross/net booking; InventoryProduct treats input as new gross total, posts correction. ConsumeProduct records spoiled distinct from ordinary consume and transaction_type.
- [`services/StockService.php`](https://github.com/grocy/grocy/blob/41206cb90154e0d17d3e108cc1f182b94fdb465d/services/StockService.php), `OpenProduct/GetProductStockEntries`: Opening uses stock_next_use, records open transition and caps new after-open date at original due date; tare-enabled opening explicitly unsupported.
- [`services/StockService.php`](https://github.com/grocy/grocy/blob/41206cb90154e0d17d3e108cc1f182b94fdb465d/services/StockService.php), `TransferProduct/UndoBooking/UndoTransaction`: Correlated transfer and undo entries; transfers of tare-enabled products explicitly rejected. Not evidence of Tavli offline or idempotent receipt behavior.
- [`helpers/Grocycode.php`](https://github.com/grocy/grocy/blob/41206cb90154e0d17d3e108cc1f182b94fdb465d/helpers/Grocycode.php), `Grocycode.Validate/setFromCode`: Compact typed local label identity; optional later lot-label pattern; no code copied because not necessary for minimum pantry slices.

Odluka: Source patterns only; implement fixed-point Dart domain contracts independently. MIT allows copying but large service is tightly coupled to PHP DB/service globals and float accounting.

### https://github.com/openfoodfacts/openfoodfacts-dart

Commit `64237b8c7c69dabb17fc1c894ab11dedec5bd1c4`; licenca Apache-2.0.

- [`LICENSE`](https://github.com/openfoodfacts/openfoodfacts-dart/blob/64237b8c7c69dabb17fc1c894ab11dedec5bd1c4/LICENSE), `Apache-2.0 grant`: License copied unchanged; no repository NOTICE found.
- [`lib/src/open_food_api_client.dart`](https://github.com/openfoodfacts/openfoodfacts-dart/blob/64237b8c7c69dabb17fc1c894ab11dedec5bd1c4/lib/src/open_food_api_client.dart), `OpenFoodAPIClient.getProductV3/getProductString`: Typed product response parsing; explicit 404 allowed and TooManyRequestsException check. Keep missing distinct from transport unavailable.
- [`lib/src/model/product.dart`](https://github.com/openfoodfacts/openfoodfacts-dart/blob/64237b8c7c69dabb17fc1c894ab11dedec5bd1c4/lib/src/model/product.dart), `Product.quantity/productQuantity/productNameInLanguages`: Label quantity string and numeric product quantity are nullable; do not treat arbitrary string or returned name as confirmed pantry amount/identity.
- [`lib/src/open_prices_api_client.dart`](https://github.com/openfoodfacts/openfoodfacts-dart/blob/64237b8c7c69dabb17fc1c894ab11dedec5bd1c4/lib/src/open_prices_api_client.dart), `OpenPricesAPIClient.getPrices/getLocations`: Public read adapter with typed MaybeError response; useful contract for separate observations, not retailer live stock.
- [`lib/src/prices/get_prices_parameters.dart`](https://github.com/openfoodfacts/openfoodfacts-dart/blob/64237b8c7c69dabb17fc1c894ab11dedec5bd1c4/lib/src/prices/get_prices_parameters.dart), `GetPricesParameters.getQueryParameters`: Product code, currency, dates and branch/location filters are explicit.
- [`lib/src/prices/get_locations_parameters.dart`](https://github.com/openfoodfacts/openfoodfacts-dart/blob/64237b8c7c69dabb17fc1c894ab11dedec5bd1c4/lib/src/prices/get_locations_parameters.dart), `GetLocationsParameters.getQueryParameters`: Country/city/name filters for observed locations, not coverage guarantee.
- [`lib/src/utils/country_helper.dart`](https://github.com/openfoodfacts/openfoodfacts-dart/blob/64237b8c7c69dabb17fc1c894ab11dedec5bd1c4/lib/src/utils/country_helper.dart), `OpenFoodFactsCountry.SERBIA`: rs/SRB and Currency.RSD are representable; not a count of Serbian products, prices or retailer inventory.
- [`lib/src/utils/language_helper.dart`](https://github.com/openfoodfacts/openfoodfacts-dart/blob/64237b8c7c69dabb17fc1c894ab11dedec5bd1c4/lib/src/utils/language_helper.dart), `OpenFoodFactsLanguage.SERBIAN`: Serbian language option exists; actual per-product translation may be missing.
- [`lib/src/utils/open_food_api_configuration.dart`](https://github.com/openfoodfacts/openfoodfacts-dart/blob/64237b8c7c69dabb17fc1c894ab11dedec5bd1c4/lib/src/utils/open_food_api_configuration.dart), `OpenFoodAPIConfiguration.userAgent`: Identify calling app; avoid global authenticated user/config leakage in Tavli adapter.
- [`lib/src/utils/barcodes_validator.dart`](https://github.com/openfoodfacts/openfoodfacts-dart/blob/64237b8c7c69dabb17fc1c894ab11dedec5bd1c4/lib/src/utils/barcodes_validator.dart), `_EANValidator._isDigitsOnly`: Rejected for copying: character range condition uses <zero AND >nine, which cannot both hold. Also unsupported length may throw. Write independently tested validation boundary.
- [`lib/src/utils/unit_helper.dart`](https://github.com/openfoodfacts/openfoodfacts-dart/blob/64237b8c7c69dabb17fc1c894ab11dedec5bd1c4/lib/src/utils/unit_helper.dart), `UnitHelper.stringToUnit`: Complete small tagged external-unit mapper copied with dependency. Handles unknowns and alternate spelling; not a pantry quantity conversion engine.
- [`lib/src/model/off_tagged.dart`](https://github.com/openfoodfacts/openfoodfacts-dart/blob/64237b8c7c69dabb17fc1c894ab11dedec5bd1c4/lib/src/model/off_tagged.dart), `OffTagged.fromOffTag`: Complete dependency of UnitHelper; copied unchanged.

Odluka: Two small complete dependency-closed files plus exact LICENSE copied for reference only. No SDK installed; no runtime changes. Data ODbL and image terms are separate from Apache SDK code license.

### https://github.com/openfoodfacts/open-prices

Commit `ecb334d80083908cabd372df04121314d628af8c`; licenca AGPL-3.0-only.

- [`LICENSE`](https://github.com/openfoodfacts/open-prices/blob/ecb334d80083908cabd372df04121314d628af8c/LICENSE), `GNU Affero General Public License v3`: Study/citation only; no code copied.
- [`open_prices/prices/models.py`](https://github.com/openfoodfacts/open-prices/blob/ecb334d80083908cabd372df04121314d628af8c/open_prices/prices/models.py), `Price.set_is_duplicate_of (and Price fields)`: Price fields include product_code, currency, date, location, proof and receipt_quantity; duplicate logic uses location/date/currency. These are observations, not stock.
- [`open_prices/proofs/models.py`](https://github.com/openfoodfacts/open-prices/blob/ecb334d80083908cabd372df04121314d628af8c/open_prices/proofs/models.py), `ReceiptItem/ReceiptItem.get_predicted_price/get_predicted_product_name`: Raw predicted_data, schema_version, status and links to proof/prediction/price are distinct; useful review-before-confirmation pattern, not automatic pantry receipt.
- [`open_prices/api/prices/views.py`](https://github.com/openfoodfacts/open-prices/blob/ecb334d80083908cabd372df04121314d628af8c/open_prices/api/prices/views.py), `PriceViewSet.get_authenticators/get_queryset`: GET public read path; mutations authenticated and owner/moderator guarded.
- [`open_prices/api/prices/filters.py`](https://github.com/openfoodfacts/open-prices/blob/ecb334d80083908cabd372df04121314d628af8c/open_prices/api/prices/filters.py), `PriceFilter.Meta`: Filter by product/location/currency/date/proof; no live branch availability field in inspected contract.
- [`open_prices/api/locations/filters.py`](https://github.com/openfoodfacts/open-prices/blob/ecb334d80083908cabd372df04121314d628af8c/open_prices/api/locations/filters.py), `LocationFilter`: Country/city/name/price_count filters support later coverage probe, not retailer stock API.

Odluka: No AGPL code copied. Independently implement adapter/result and review-state patterns. Never auto-upload private receipt proof.

## Prikupljeni referentni fajlovi

Kompletan mali par `lib/src/utils/unit_helper.dart` i `lib/src/model/off_tagged.dart` iz Apache-2.0 OFF Dart je kopiran bajt-po-bajt u `research/reference-code/C/openfoodfacts-dart/` uz ceo originalni LICENSE i PROVENANCE.md. Koristan je za normalizaciju oznaka jedinica na granici adaptera; nije zamena za Tavli količinski engine. Nema dodatnih zavisnosti između ovog para izvan standardnog Dart jezika. Nije ugrađen u runtime. Tačni SHA-256 i upstream linkovi su u C.json (uključujući hash licence).

Grocy veliki servis nije kopiran: PHP DB/global service zavisnosti i float obračun nisu odgovarajući mali Dart paket. Rezultat za stock/tare/transakcije je obrazac za sopstvenu implementaciju. AGPL Open Prices nije kopiran. Jedan pokušani permissive kandidat `dnfield/dart_fraction` vratio je repository-not-found; ništa nije preuzeto ili citirano iz njega. OFF barcode validator je pregledan ali odbijen za preuzimanje zbog navedenog range-check problema; original nije menjan niti pokretan.

## Otvorena pitanja

- Serbian product/package/name coverage and recent RSD/location price counts were NOT measured; no public production API calls or retailer production checks were made. SDK enum support is not local market support.
- No documented authorized Serbian live branch/slot inventory API was established. F083 must remain unsupported/manual until capability evidence exists.
- Physical root/lot split representation and unique receipt-line keys require integration review with stream D before any implementation; existing samePhysicalAs canonical dedupe cannot represent arbitrary split children unchanged.
- Cross-device stock compare-and-set/atomic command application is a new foundation gate; local transaction/outbox alone does not ensure server-side no overspend.
- Receipt OCR model quality for Serbian fiscal receipts, numeral formatting and multipack labels is unknown; manual review is mandatory and OCR remains optional.
- Pantry confirmedAt currently has no age threshold; decide user-visible freshness policy rather than silently inventing one.
- Data/image licensing and any derived database redistribution need explicit implementation-stage review; code license is not dataset license.
- No upstream software/install scripts, Flutter tests or backend tests were run. Only output JSON/hash/coverage checks described in validation were performed.

## Provera ovog paketa

Izvršena je lokalna provera JSON parsiranja, tačnog skupa 15 stream-C ID-jeva, obaveznih polja po šemi, postojanja svih kopiranih fajlova, njihovih SHA-256, identičnosti sa cache upstream bajtovima i prisustva originalnog LICENSE. Nije pokrenut izvorni upstream kod, install skripta, Flutter test ili produkcijski backend. Završni rezultat je plan i referentni materijal, bez implementiranih Fnnn funkcija.
