# D — Nabavka, domaćinstva i trgovina

Datum istraživanja: 2026-11-09. Osnova je Tavli `1eca2c3d14fb5dd9b25a42958aa018c8d8dfbb94` iz `https://github.com/anjahubac/tavli`. Ovo je blueprint za 15 predloga, ne implementacija. Pregledani su stvarni Flutter/Dart, SQL, Python backend i TypeScript izvori; ništa iz upstream-a nije pokrenuto ili instalirano. Nema produkcijskih API poziva, pristupa ključevima ili tajnama. Izmenjeni su isključivo D izveštaj, manifest i D reference-code direktorijum. P1/P2/P3 su predložene faze ovog plana, ne status isporuke.

## Provereno postojeće stanje

- `lib/data/database.dart::AppDatabase.schemaVersion` je 5. `ShoppingLists`, `ShoppingItems`, `ShoppingSources`, `ShoppingContributions` i `SupplyAllocations` već čine povezan model nabavke. `ShoppingItems` ima ručne/kupljene redove i `purchaseProvenanceJson`; nema finansijskih kolona, SKU, dodeljenog kupca, kartica, poslovnice ili promocije. `ShoppingContributions.notesJson` već postoji i ne treba ga pogrešno tretirati kao prazno mesto za kupčevu napomenu.
- `lib/data/shopping_repository.dart::addManual`, `weekList`, `addRecipePreparation`, `_reconcile`, `setBought`, `_buy` i `_unbuy` već upravljaju listama, poreklom potražnje i kupovinom. `_reconcile` sabira kompatibilne potrebe, raspoređuje potvrđenu zalihu i čuva ručne/kupljene stavke. Ne praviti drugi sistem listi. Kupovina je povezana sa raspodelom zalihe, pa finance/claim/promotion nikad ne smeju direktno menjati količine iz demand modela.
- `lib/domain/shopping_demand.dart::normalizeUnit`, `toMicros`, `demandFor` koriste milionite delove osnovne jedinice za račun količina. To nije monetarna preciznost i nije proizvod/pakovanje. `lib/domain/shopping_sync.dart` ima logiku shopping spajanja, ne protokol višekorisničkog mrežnog konflikta.
- `lib/features/shopping/shopping_providers.dart::ShoppingViewController` i postojeći Riverpod stream-ovi čitaju drift; `lib/features/shopping/shopping_list_view.dart::ShoppingItemsList` grupiše otvorene stavke i odvaja kupljene. Nadograditi te providere/poglede bez izbacivanja postojećih efekata i animacija. UI ostaje srpska latinica.
- `lib/domain/account.dart::Account`, `lib/account/account_api.dart::SupabaseAccountApi.fetch` i `lib/account/auth_controller.dart::accountScopeProvider` modeluju jedno izabrano domaćinstvo, a fetch ima `limit(1)`. `supabase/migrations/20261030120100_accounts.sql` ograničava role na `owner`. To što SQL tabele već imaju household_id ne znači da pozivnice, članovi, više domaćinstava i uloge već rade.
- `lib/sync/synced_writer.dart::SyncedWriter` zapisuje identitet promene u istoj drift transakciji; `lib/sync/uploader.dart::_send` sadržaj čita iz aktuelnog reda i šalje ceo red putem `lib/sync/sync_remote.dart::SupabaseSyncRemote.upsert`. Nema expected-revision uslova. `lib/sync/downloader.dart::_applyRow` čuva lokalni red dok ima outbox, `_applyTombstone` primenjuje delete-wins. `SyncCursors` su account+entity, a remote fetch se oslanja na RLS za sve dostupne redove. `lib/sync/sync_engine.dart::onStart/onResume` šalje/preuzima, bez dokazane realtime pretplate.
- `supabase/migrations/20261030120200_household_data.sql` i `20261102120000_plan_and_shopping.sql` već imaju složene FK sa household_id; zadržati taj obrazac. `20261030120500_rls_and_grants.sql` koristi member proveru, dok `20261030120700_delete_account.sql::solo_households/delete_account_data` čuva nesolo domaćinstva. Owner transfer i očuvanje finansijske istorije pri brisanju člana ipak nisu rešeni sadašnjim jednočlanim modelom.

## Zajednički ugovori i foundation gates

Svi nazivi novih modela u nastavku su predlozi. Svaka implementacija ostaje feature po feature: zaseban Spec Kit spec/branch iz latest main, mali vertikalni koraci i provera pre sledećeg. Ne primenjivati sve kao jedan veliki rewrite.

**G-SCHEMA — proširenje postojeće šeme.** Svaka nova tabela/kolona ima drift version bump + migracioni test iz v5, novi Supabase migration fajl, RLS, eksplicitne authenticated grants i pgTAP sa najmanje dva naloga. Svi household roditelj/deca parovi imaju složeni FK `(id,household_id)`. Personal loyalty kartica ima `owner_user_id` i sopstveni RLS. Svaki repo upisuje lokalni red i postojeći outbox u jednoj transakciji; UUID nastaje na klijentu. Podaci za UI dolaze iz drift-a. Novi paketi tek uz razlog u aktivnom plan.md. Ne menjati ili ponovo praviti osnovne tabele i stare UUID-jeve. `test/data/migration_test.dart`, `test/data/shopping_repository_test.dart`, `test/sync/*` i `supabase/tests/07_plan_shopping_test.sql` su polazni regression skupovi.

**G-SYNC — evolucija postojećeg outbox-a.** Proširiti postojeći SyncOutbox sa opcionim verzionisanim command payload-om, operation UUID-om, original household_id i expectedRevision; ne uvoditi paralelni red promena. Snapshot command-a je nepromenljiv dok je sending; nova izmena dobija novu komandu. Server u jednoj transakciji proverava auth uid, aktuelno članstvo/ulogu, household na parent i child, tombstone i očekivanu reviziju, pa menja red, zapisuje dedupe operation receipt i vraća canonical row/revision. Operation UUID je jedinstven unutar household-a, vezan za actor i hash payload-a: isti UUID/drugi sadržaj je greška; retry istog sadržaja vraća isti rezultat. Revizije su serverovi monotoni celi brojevi, ne klijentski satovi. Acknowledged receipt čuvati dovoljno dugo da pokrije podržani offline period; istekla dedupe istorija zahteva eksplicitni resync, ne slepo ponovno izvršenje.

Kupovina je agregatna komanda: bought promena, purchase provenance, raspodele i posledice koje danas radi `_buy/_reconcile` moraju se atomarno potvrditi na serveru ili deterministički rekonstruisati iz jedne potvrđene operacije. Slanje više redova iz više nezavisnih REST zahteva nije distribuirana transakcija. Za reconciliation koristiti server household/list revision i canonical rezultat, ili precondition bundle za sve zavisne redove; pre puštanja više članova testirati dva paralelna `_reconcile` poziva da ne proizvedu duple izvore, preostale potrebe ili dvostruko iskorišćenu zalihu. Ovo je gate F011, ne tvrdnja da lokalna transakcija rešava mrežnu konkurentnost.

Conflict policy je eksplicitan:

| Operacije | Pravilo |
|---|---|
| Detail note naspram claim/bought | Različiti komponentni redovi/revizije; potvrditi obe bez whole-row overwrite-a. |
| Dva claim-a | CAS: prvi server commit dobija claim; drugi je konflikt, njegov provisional prikaz se ispravlja. |
| Dva edit-a iste napomene | Ne automatski tekst merge; sačuvati lokalni predlog i canonical verziju, korisnik bira novu potvrđenu komandu. |
| bought naspram unbuy | Ista purchase revizija; stale operacija konflikt. Unbuy ne poništava tuđu novu kupovinu i poštuje postojeći prijem u ostavu. |
| delete naspram edit/claim | Server tombstone pobeđuje; nema upsert vaskrsavanja; prikaži odbijenu lokalnu promenu. |
| revoke membership naspram pending write | Server zabrani write; karantin sa razlogom, nikad preusmeravanje na aktivno drugo domaćinstvo. |

Realtime prenosi invalidaciju/small IDs sa revizijom; sve se proverava pull-om, kroz isti Downloader i drift transakciju. Debounce invalidacije, idempotentno dupliranje, reconnect/resume full catch-up i povremeni bounded pull za propuštene event-e. Pretplata je vezana za membership/scope epoch i mora se ugasiti na odjavi/opozivu. Postojeći pending/rejected status proširiti conflict stanjem: „Čeka slanje”, „Sačuvano”, „Izmena nije prihvaćena”, „Potrebno je rešiti konflikt”. Member/viewer prava proverava server, nikad samo sakriveno dugme. Stariji klijent koji šalje whole-row upsert ne sme zaobići nove revizije: rollout treba command-only grants za zaštićene kolone/operacije i vidljiv zahtev za update, uz test starih payload-a.

**G-MONEY — finansijska aritmetika.** `Money(currency: ISO code, minor: signed integer, exponentVersion)`; na serveru bigint uz ograničenja, u Dart domenu int uz proverene granice i BigInt intermediate za proizvode/deljenja. Wire amount je string decimalnog celog broja, bez JSON/JS preciznosnog gubitka. Limit za v1: apsolutni iznos <= 9,000,000,000,000 minor i kontrolisani proizvodi; prekoračenje je greška. RSD/EUR primeri koriste exponent=2, ali model ima verzionisan registar i ne pretpostavlja 2 za svaku valutu. Parser prihvata kontrolisan lokalizovan input, uklanja odobrene separatore tek nakon validacije i nikad ne prolazi kroz double. Valute se nikad tiho ne sabiraju ili konvertuju.

Cena po kg/pakovanju može imati više decimalnih mesta od novčanog exponent-a: `DecimalQuote(unscaled: integer string, scale: 0..6, currency, basis, sourceDecimal)` čuva tačan podatak (Open Prices model ima 3 decimale). Množenje quote sa racionalnom količinom/pakovanjem ide exact integer/rational putem; zaokruži HALF_UP za nenegativnu line vrednost u minor jedinice tek na granici obračuna. Storno koristi tačne negirane originalne line/share iznose, bez novog zaokruživanja. Gotovinski total rounding, porez, depozit i prodavčev cent discrepancy su posebna eksplicitna pravila; ne menjaju tihi line rounding. Korisnik potvrđuje actual receipt total ako odstupa od procene. F072 depozit iz C dobija posebnu line vrstu i beneficiary politiku pre F066 knjiženja.

Za deljenje troška uzeti nenegativne integer težine sa sum>0, izračunati floor(totalMinor*weight/sum), a preostale jedinice dodeliti po opadajućem razlomljenom ostatku, uz stabilan userId pri jednakosti. Predloženi Tavli algoritam je largest fractional remainder, eksplicitno različit od kopiranog Dinero algoritma koji ostatak dodeljuje po veličini težine. Nulte težine dobijaju 0; all-zero/prazan/negativan skup se odbija. Primer 100 minor / 3 jednaka člana A<B<C daje 34/33/33, nezavisno od redosleda ulaza. Lična stavka A ne učestvuje u zajedničkoj raspodeli, ali se uračunava u ukupno plaćanje i A udeo. Ledger je append-only nakon posting-a, sa audit actor-om i operation UUID-om. Novac u ovom planu predstavlja evidenciju, ne transfer prema banci.

**G-CAPABILITY — uslovne integracije.** Čisti interfejsi odvajaju device/retailer/price/route provider od domena i widgeta; svi imaju `probe`, `checkedAt`, mogućnosti i reason code. Unconfigured/unsupported/denied/offline/stale su različita stanja. Nema izmišljene prodavnice, cene, raspoloživosti, checkout-a ili garantovane device podrške. Raspoloživost F083, potvrđivanje računa F073 i identitet proizvoda F017 su veze sa C; osnovni ručni tok ne zavisi od toga da se sve implementira prvo. `G-ASSETS` je postojeći PhotoSync obrazac proširen za dozvoljene privatne asset vrste. `G-PLAN-CONSTRAINTS` je ugovor sa A/B da vote rezultat nikad ne zaobiđe obavezno ograničenje, snapshot ili is_locked.

**Promocije — izvršiv ugovor F071.** Predicate AST je verzionisan JSON sa allowlist tag-ovima i ograničenom dubinom/brojem čvorova. `all` i `any` koriste tri-state logiku: all sa false je false, bez false uz unknown je unknown; any sa true je true, bez true uz unknown je unknown. `not` u v1 izostaviti radi jednostavnije validacije. Context sadrži potvrđene quantities/packages, qualifying subtotal pre te promocije, branch/retailer ID, loyalty program eligibility, coupon activation, server/injected clock i store timezone. Datumsko „do 10.11” normalizovati u ekskluzivni početak sledećeg lokalnog dana, sa UTC instant granicom. Nepoznat program status nije false niti pravo na popust, već unknown sa redovnom cenom i objašnjenjem.

Efekat navodi qualifyingUnits i rewardUnits, fixed bundle ili bps procenat, cap, maksimalan broj ponavljanja i allocation po linijama. Za buyNpayM sa istom SKU jedinicom q: floor(q/N)*M plaćenih + q mod N redovnih jedinica; mešane SKU/besplatna najjeftinija jedinica nisu automatski podržane istim efektom. Preporuka v1: jedan najbolji efekat po exclusive group uz determinističan promotionId tie; „stackable” samo ako eksplicitni redosled i osnova postoje u ugovoru. Za mali bounded skup enumerisati dozvoljene kombinacije; ne obećavati optimalnost generičkom greedy procedurom. Ušteda = validna redovna uporediva cena - potvrđena eligible quote cena, nikad pretpostavka iz discount_type oznake. Loyalty barcode nije potvrda eligibility-ja ni dokaz ostvarene uštede na kasi.

## Redosled isporuke

1. P1 nezavisne vertikale: F041, F045, zatim tekstualni F010; svaku zasebno verifikovati. Dodati G-MONEY pre F043 i početnog ručnog F018. F010 slika ide tek uz G-ASSETS.
2. G-SYNC/F011 članstvo i revizije pre više kupaca; F063 stabilan scope i bootstrap pre širenja na više prostora; F044, F056 i F066 nad tim ugovorom. F043 može početi solo, ali shared posting čeka F011.
3. F068 privatna statična kartica i F071 izvršiva pravila; F067 prvo ručni izvoz, pa dokazani provider. F069/F070 su P3 zbog device/route zavisnosti i potrebe za relevantnim cenama.

Svaka vertikala ima: pure-domain failing tests → repository/outbox/migration → local RLS → postojeći widget tok → susedni regression. Pri budućem production code PR-u traže se format/analyze, affected testovi, full Flutter suite i macOS debug smoke po AGENTS.md. Te provere nisu pokrenute ovde jer ovaj stream ne menja aplikaciju.

## Petnaest predloga

### F010 — Fotografija, brend i napomena uz nabavku (P1)

**Ciljni moduli (plan, ne napravljeni fajlovi):** `lib/domain/shopping_item_details.dart (new)`; `lib/data/shopping_repository.dart (extend)`; `lib/sync/photo_sync.dart (extend)`; `lib/features/shopping/shopping_list_view.dart (extend)`.

**Postojeće:** lib/data/database.dart::ShoppingItems ima name/quantity/unit/category/isBought/isManual i purchaseProvenanceJson, bez fotografije, brenda i korisničke napomene. ShoppingContributions.notesJson čuva napomene sastojaka, nije isto što i kupčeva napomena. lib/data/shopping_repository.dart::_reconcile spaja potrebe; lib/features/shopping/shopping_list_view.dart::ShoppingItemTile prikazuje postojeću stavku. lib/sync/photo_sync.dart::PhotoSync je obrazac za slike recepata, ne gotova podrška za slike artikala.

**Predloženi ugovor/model:**
- Dodati ShoppingItemDetails(itemId, householdId, brand?, shopperNote?, photoAssetId?, revision); polja u zasebnom zavisnom redu čuvaju nezavisne revizije od isBought i reconciliation količine.
- Asset ima UUID, relativnu lokalnu putanju, privatni objectKey household/item/asset, mime, size i uploadState. Bez javnog URL-a; brisanje i retry prate isti outbox. Snapshot detalja ide u potvrđenu kupovinu; pri nestanku automatske stavke unapred definisati obrisati detalje ili prikazati predlog za novu stavku, bez tihog prenošenja na drugi proizvod.

**Zavisnosti:** G-SYNC; G-SCHEMA; G-ASSETS.

**Male vertikale, redom:**
1. Tekstualna napomena i brend offline kroz postojeći repository/writer.
2. Privatna slika, ograničenje veličine i retry bez dupliranja.
3. Prikaz detalja pri kupovini i snapshot istorije.

**Merljivo prihvatanje:**
- Izmena napomene ne menja quantity, isBought ili potražnju iz recepta.
- Slika radi offline posle preuzimanja; drugi član istog domaćinstva je vidi, drugi nalog van domaćinstva dobija zabranu.
- Brisanje slike i ponovljeno slanje ne ostavljaju vidljiv duplikat.

**Konkretne provere koje implementacija mora da izvrši:**
- Dopuniti test/data/shopping_repository_test.dart: promena plana, spajanje iste namirnice i kupovina zadržavaju predviđene detalje.
- Faked PhotoRemote: prekid posle upload-a, retry istog asset UUID-a; lokalni pgTAP sa dva domaćinstva za Storage/RLS.
- Widget: telefon i širok ekran, tekst „Napomena za kupovinu”, „Brend”, „Slika proizvoda”.

### F011 — Zajednička lista, članstvo i brze izmene (P2)

**Ciljni moduli (plan, ne napravljeni fajlovi):** `lib/domain/account.dart (extend)`; `lib/account/account_api.dart (extend)`; `lib/sync/synced_writer.dart (extend)`; `lib/sync/uploader.dart (extend)`; `lib/sync/downloader.dart (extend)`; `lib/sync/sync_remote.dart (extend)`; `lib/sync/sync_engine.dart (extend)`.

**Postojeće:** lib/domain/account.dart::Account nosi jednu householdId i role; lib/account/account_api.dart::SupabaseAccountApi.fetch koristi limit(1). supabase/migrations/20261030120100_accounts.sql::household_members dozvoljava samo owner. lib/sync/uploader.dart::_send šalje ceo red upsert-om; lib/sync/downloader.dart::_hasLocalChange preskače remote red dok postoji lokalni outbox, a _applyTombstone briše lokalnu promenu. lib/sync/sync_engine.dart::onStart/onResume su pull okidači, bez realtime pretplate.

**Predloženi ugovor/model:**
- Membership(householdId,userId,role owner|admin|member|viewer,status,revision). Owner prenosi vlasništvo i briše domaćinstvo; owner/admin upravljaju običnim članovima i pozivnicama; member menja zajedničku nabavku i svoje glasove; viewer samo čita. Niko ne može sebi podići ulogu. Poslednji owner ne može otići bez transfera ili brisanja solo domaćinstva.
- Invitation(id,householdId,hashedToken,expiresAt,revokedAt,maxUses=1); server proverava auth i uslove pri prihvatanju u jednoj transakciji. Raw token nije u logu ni običnom kešu.
- Operacije sa operationId, actor, boundHouseholdId, expectedRevision i patch ostaju u postojećem outbox-u sa opcionim payload-om; server RPC atomarno proverava članstvo, reviziju, idempotency i tombstone. Realtime je invalidacija sa naknadnim pull-om, ne izvor istine. Detaljan conflict ugovor je ispod.

**Zavisnosti:** G-SCHEMA; G-SYNC.

**Male vertikale, redom:**
1. Pozivnica, role RLS i prikaz članstva, bez realtime-a.
2. Server revizije i idempotentne komande u postojećem outbox-u, zatim lokalni conflict UI.
3. Realtime invalidacija, reconnect pull i prikaz pending/rejected/conflict.

**Merljivo prihvatanje:**
- Dva člana u kontrolisanom lokalnom testu vide potvrđenu promenu za najviše 2 s pri dostupnom realtime transportu; prekid prelazi na pull bez gubitka.
- Dve operacije nad istom revizijom ne mogu obe uspeti; različita nezavisna polja ne prepisuju jedno drugo.
- Viewer ne piše ni direktnim REST/RPC pozivom; opozvana pozivnica i uklonjeni član ne mogu slati nove operacije.
- Offline izmena je odmah vidljiva lokalno, uz „Čeka slanje”; konflikt ne pokazuje lažno „Sačuvano”.

**Konkretne provere koje implementacija mora da izvrši:**
- Local Supabase pgTAP: owner/admin/member/viewer plus outsider, self escalation, replay invite, expiry tačno na granici, paralelno prihvatanje, last-owner transfer.
- Dve fake replike: kupi/poništi, napomena/kupi, obriši/izmeni, duplirani event i operationId, offline 24 h, reconnect i izmenjen sat.
- Regression: test/sync/downloader_test.dart, uploader_test.dart i test/data/shopping_repository_test.dart; provera reconciliation veza i prijema u ostavu.

### F018 — Cene, prodavnica, datum i dokaz (P2)

**Ciljni moduli (plan, ne napravljeni fajlovi):** `lib/domain/price_observation.dart (new)`; `lib/data/price_repository.dart (new)`; `lib/data/shopping_repository.dart (extend)`; `lib/features/shopping/price_history_sheet.dart (new)`.

**Postojeće:** lib/data/database.dart::ShoppingItems nema cenu, valutu, proizvod ili poslovnicu; lib/domain/shopping_demand.dart::normalizeUnit poznaje uporedive jedinice hrane, ne pakovanja proizvoda. lib/data/shopping_repository.dart::setBought/_buy zamrzava poreklo nabavke, ne novčani iznos. Postojeći supabase/migrations/20261030120200_household_data.sql nema price tabelu.

**Predloženi ugovor/model:**
- ProductRef(id,barcode?,name,brand?,packageQuantityMicros?,unitGroup,source,sourceId) je odvojen od ingredientKey; potvrđen IngredientProductMapping nije automatski jednak barkodu.
- PriceObservation(id,householdId,productRefId,storeBranchId,observedOn,recordedAt,currency,rawDecimal,scale,priceBasis package|kg|l|unit,proofAssetId?,source,sourceRecordId?,promotionId?,qualityFlags). Exact decimal/rational quote čuva se bez float-a; Money nastaje tek po izračunatoj stavci i pravilu zaokruživanja.
- PriceProvider.capabilities i import javno dozvoljenih fixture podataka; ručni unos radi bez provajdera. Pokrivenost = broj stavki sa uporedivom dovoljno svežom cenom / broj traženih stavki, uz nepoznate količine odvojeno. Nijedan API nije pozvan; pokrivenost Srbije ostaje nepoznata.

**Zavisnosti:** G-MONEY; G-SCHEMA; F017 (optional barcode input from C); F073 (optional confirmed receipt evidence from C).

**Male vertikale, redom:**
1. Ručna cena, poslovnica i datum sa privatnim dokazom.
2. Istorija i poređenje iste jedinice/pakovanja, prikaz zastarelosti i pokrivenosti.
3. Provider adapter tek posle provere uslova podataka i relevantnosti Srbije na odobrenim offline uzorcima.

**Merljivo prihvatanje:**
- Dve cene za 500 g i 1 kg porede se po kg; nepoznata masa ne daje lažnu najnižu cenu.
- Iznos 1.235 iz izvora sa tri decimale zadržava se tačno; total se zaokružuje samo jednom po definisanom obračunu.
- Od 10 redova sa 6 uporedivih svežih cena prikaz je 6/10 uz 4 nepoznate, bez izmišljene ukupne uštede.
- Dokaz računa ostaje privatan dok korisnik posebno ne odluči o eventualnom javnom doprinosu.

**Konkretne provere koje implementacija mora da izvrši:**
- Offline fixture parser za decimalni string, null datum, nedostajući proof, 3-decimalnu cenu i valutu koja nije RSD.
- Ručni proračun: 500 g za 15000 minor = 30000 minor/kg; 1 kg za 28000 je jeftiniji za 2000 minor/kg.
- Repository/migration roundtrip, local RLS isolation, fake provider denied/rate-limited/unconfigured bez mreže.

### F041 — Redosled kategorija prema prodavnici (P1)

**Ciljni moduli (plan, ne napravljeni fajlovi):** `lib/domain/store_layout.dart (new)`; `lib/data/store_repository.dart (new)`; `lib/features/shopping/shopping_list_view.dart (extend)`.

**Postojeće:** lib/features/shopping/shopping_list_view.dart::ShoppingItemsList koristi byCategory(open,...); nema izabrane poslovnice ni StoreLayout u lib/data/database.dart. Postojeće kategorije i ShoppingItemTile treba zadržati.

**Predloženi ugovor/model:**
- StoreBranch i StoreLayout(householdId,branchId,revision,categoryOrder[]) sa jedinstvenim category ključevima; opciona pozicija artikla kasnije. Sort ključ = poznata pozicija kategorije, postojeći redosled nepoznatih kategorija, stabilni itemId. To je pogled, ne promena identiteta ili potražnje stavke.

**Zavisnosti:** G-SCHEMA.

**Male vertikale, redom:**
1. Ručni izbor/profil poslovnice i sačuvan raspored.
2. Determinističko sortiranje otvorenih stavki u postojećoj listi.
3. Uređivanje redosleda i offline sync rasporeda.

**Merljivo prihvatanje:**
- Isti spisak pri promeni prodavnice menja samo redosled; bought status i izvori ostaju isti.
- Nepoznate kategorije se pojavljuju posle uređenih i nijedna stavka nije izgubljena.
- Kupljene stavke ostaju u postojećoj odvojenoj sekciji.

**Konkretne provere koje implementacija mora da izvrši:**
- Pure sorter fixture: voće/mlečno/hleb i nepoznata kategorija, jednaki rangovi i prazan layout.
- Widget promena A→B→A na telefonu/široko; repository roundtrip i regression setBought/receivePurchases.

### F043 — Budžet tokom kupovine (P2)

**Ciljni moduli (plan, ne napravljeni fajlovi):** `lib/domain/money.dart (new, shared finance)`; `lib/domain/shopping_budget.dart (new)`; `lib/data/shopping_repository.dart (extend)`; `lib/features/shopping/shopping_list_view.dart (extend)`.

**Postojeće:** lib/data/shopping_repository.dart::setBought/_buy i lib/features/shopping/shopping_list_view.dart::ShoppingItemsList razlikuju kupljeno/otvoreno, bez novčanog modela. ShoppingItems.purchaseProvenanceJson zamrzava izvor, ne cenu.

**Predloženi ugovor/model:**
- ShoppingBudget(listId,currency,limitMinor?); PurchaseLine(itemId,purchaseEventId,quantityMicros,actualLineTotalMinor?,currency,source,confirmedAt); EstimateLine ima observationId i freshness. Odvojiti confirmedBoughtTotal, estimatedOpenTotal i unknownLineCount; null nije nula. Snapshot stvarne kupovine ne zavisi od kasnije promene kataloške cene.

**Zavisnosti:** G-MONEY; G-SCHEMA; F018 (optional estimates).

**Male vertikale, redom:**
1. Potvrđena cena cele kupljene stavke i zbir.
2. Budžetski limit i odvojena procena preostalog.
3. Cena po jedinici, potvrđene količine i ispravka računa kao nova revizija.

**Merljivo prihvatanje:**
- Kupljene stavke 12345 i 20000 minor daju 32345; procena otvorene 5000 i jedna nepoznata daju prikaz 32345 potvrđeno + 5000 procenjeno + 1 bez cene.
- Mešane valute se ne sabiraju; nedostajuća cena nije 0.
- Označavanje bought bez cene radi kao danas i dodaje nepoznatu vrednost.

**Konkretne provere koje implementacija mora da izvrši:**
- Test-first money parser/sum i boundary overflow; negativni račun kroz refund događaj, ne negativnu cenu artikla.
- Repository buy/unbuy/rebuy sa dva uređaja; povratak iz ostave po postojećim ograničenjima i ispravka cene ne menjaju zalihu.
- Widget „Potvrđeno”, „Procena preostalog”, „Bez cene: 1”, „Budžet”.

### F044 — Preuzimanje stavki od strane članova (P2)

**Ciljni moduli (plan, ne napravljeni fajlovi):** `lib/domain/item_claim.dart (new)`; `lib/data/shopping_repository.dart (extend)`; `lib/features/shopping/shopping_list_view.dart (extend)`.

**Postojeće:** lib/data/database.dart::ShoppingItems ima isBought, nema assignedTo; lib/data/shopping_repository.dart::setBought potvrđuje kupovinu. Osnovno članstvo trenutno podržava samo owner u 20261030120100_accounts.sql.

**Predloženi ugovor/model:**
- ItemClaim(itemId,householdId,assigneeUserId?,claimedAt,revision). claim(itemId,expectedRevision) je CAS komanda u postojećem outbox-u; assignment i bought su nezavisni. Sam član preuzima/oslobađa svoje; owner/admin mogu preraspodeliti uz vidljiv trag. Offline preuzimanje je provisional do server potvrde, nikad obećanje ekskluzivnosti.

**Zavisnosti:** F011; G-SCHEMA.

**Male vertikale, redom:**
1. Prikaz „Kupujem ja” i lokalna provisional dodela.
2. Server CAS i UI za izgubljeno preuzimanje.
3. Oslobađanje, admin preraspodela i uklanjanje člana.

**Merljivo prihvatanje:**
- Istovremeni zahtev dva člana daje tačno jednog potvrđenog kupca; drugi vidi čije je preuzimanje uspelo.
- Claim ne menja isBought, pantry ni demand.
- Uklonjeni član ne ostaje aktivni assignee; istorija kupovine zadržava postojeće autorstvo.

**Konkretne provere koje implementacija mora da izvrši:**
- Dva fake klijenta claim na istoj reviziji, duplicate/reordered delivery, claim+buy i claim+delete.
- Local RLS member iz drugog domaćinstva i viewer ne preuzimaju; widget „Preuzeo/la”, „Čeka potvrdu”, „Oslobodi”.

### F045 — Moja osnovna korpa (P1)

**Ciljni moduli (plan, ne napravljeni fajlovi):** `lib/domain/shopping_template.dart (new)`; `lib/data/shopping_repository.dart (extend)`; `lib/features/shopping/template_sheet.dart (new)`.

**Postojeće:** lib/data/shopping_repository.dart::addManual dodaje ručnu stavku, _reconcile čuva ručne stavke; lib/data/database.dart nema šablon redovne kupovine. To je odvojeno od ostave i minimalnih zaliha.

**Predloženi ugovor/model:**
- ShoppingTemplate(id,householdId,name,revision) i TemplateLine(id,templateId,name,quantityMicros?,unit,category,productRefId?,details). instantiate(selection,listId,operationId) eksplicitno pravi ručne ShoppingItems kroz proširenje postojećeg ShoppingRepository; batch UUID obezbeđuje idempotentni retry. Pravilo duplikata je pregled i izbor „Dodaj posebno”/„Spoji”, nikad tiho povećanje kupljene stavke.

**Zavisnosti:** G-SCHEMA.

**Male vertikale, redom:**
1. Sačuvaj i uredi šablon, bez automatskog dodavanja.
2. Izaberi podskup i dodaj u postojeću listu atomarno sa outbox-om.
3. Pregled duplikata i opcioni product/details snapshot.

**Merljivo prihvatanje:**
- Od 5 omiljenih izabrana 2 stvaraju tačno 2 očekivana unosa; retry istog operationId ne dodaje nove.
- Promena šablona ne menja već stvorenu nabavku.
- Nema automatskog čitanja minimalne zalihe niti automatske kupovine.

**Konkretne provere koje implementacija mora da izvrši:**
- Repository transaction rollback i duplicate batch retry; merge dve iste namirnice sa uporedivim/neuporedivim jedinicama.
- Widget „Moja osnovna korpa” → izbor → pregled → dodaj; regression recipe/plan reconciliation i ručni redovi.

### F056 — Glasanje za predloge jela (P2)

**Ciljni moduli (plan, ne napravljeni fajlovi):** `lib/domain/meal_poll.dart (new)`; `lib/data/meal_poll_repository.dart (new)`; `lib/data/meal_plan_repository.dart (extend)`; `lib/features/planning/meal_poll_sheet.dart (new beside existing plan_screen.dart)`.

**Postojeće:** lib/domain/meal_plan.dart i lib/data/meal_plan_repository.dart drže planove; lib/domain/account.dart i server household_members još nemaju višekorisnički tok. U lib/data/database.dart nema poll/ballot tabele.

**Predloženi ugovor/model:**
- MealPoll(id,householdId,planId?,closesAt,status open|closed,revision), PollOption(id,pollId,recipeId?,recipeSnapshot,constraintVersion,eligibility), Ballot(pollId,voterUserId,optionId,revision), unique(pollId,voterUserId) za jedan glas. Autor plana potvrđuje izbor; nije automatska izmena zaključanog obroka. Eligibility se ponovo proverava po važećim obaveznim ograničenjima pre primene.

**Zavisnosti:** F011; G-SCHEMA; G-PLAN-CONSTRAINTS (B/A shared planner gate).

**Male vertikale, redom:**
1. Otvoren poll sa snapshot opcijama i jednim glasom po članu.
2. Zatvaranje po serverskom vremenu i pregled rezultata.
3. Potvrđena primena uz ponovnu proveru ograničenja i zaključavanja.

**Merljivo prihvatanje:**
- Promena glasa zamenjuje prethodni; replay ne povećava broj glasova.
- Najviše glasova ne dozvoljava jelo koje krši obavezno ograničenje; nerešen rezultat traži odluku.
- Offline glas posle zatvaranja je odbijen uz vidljivo stanje, bez retroaktivne izmene rezultata.

**Konkretne provere koje implementacija mora da izvrši:**
- Fake clock: tik pre/tačno na/posle closesAt; dva uređaja istog glasača i revizije.
- RLS član vidi samo poll svog domaćinstva, piše samo svoj ballot; test zaključanog plana i promene alergena nakon glasanja.
- Widget „Glasanje”, „Zatvoreno”, „Potvrdi izbor”; 3 člana, 2:1 rezultat, zatim nevažeća pobednička opcija.

### F063 — Više nezavisnih domaćinstava (P2)

**Ciljni moduli (plan, ne napravljeni fajlovi):** `lib/domain/account.dart (extend)`; `lib/account/account_api.dart (extend)`; `lib/account/auth_controller.dart (extend)`; `lib/data/database.dart (extend memberships/selection)`; `lib/sync/downloader.dart (extend bootstrap)`.

**Postojeće:** lib/domain/account.dart::Account ima tačno jedno domaćinstvo; lib/account/account_api.dart::fetch limit(1), lib/account/auth_controller.dart::accountScopeProvider izvodi taj jedan scope. lib/data/database.dart::Accounts ima householdId a SyncCursors key je accountId+entity. lib/sync/sync_remote.dart::fetchSince se oslanja na RLS i ne filtrira aktivno domaćinstvo. Repozitorijumi već filtriraju householdId; to je osnova za proširenje.

**Predloženi ugovor/model:**
- Account ostaje identitet, Membership list postaje zaseban cache, SelectedHousehold(userId,householdId) je korisnikov izbor. Postojeći AccountScope se rekreira sa epoch-om; sve async rezultate, odabrani plan i pretplate vezati za epoch, nikad za trenutno promenljivi scope.
- Odlučeno: download svih važećih domaćinstava po nalogu sa postojećim account-global cursor-om; pri novom članstvu obavezan poseban full bootstrap tog household-a i entiteta, jer stari updated_at ne bi prošao globalni cursor. UI bira samo aktivno. Ne prebacivati na household-filtered download bez particionisanja kursora.
- Outbox svaki nalog/operacija trajno vezuje originalno householdId, uključujući delete, i radi nezavisno od izabranog ekrana. Membership refresh pri reconnect-u uklanja pristup opozvanom prostoru i zaustavlja njegove upload-e.

**Zavisnosti:** F011; G-SCHEMA; G-SYNC.

**Male vertikale, redom:**
1. Normalizovati account/membership cache i migrirati postojeće jedino članstvo bez novih praznih domaćinstava.
2. Switcher + reset scoped providera i zaštita od odgovora starog scope-a.
3. Bootstrap novog članstva, opoziv, offline switching i account deletion regresije.

**Merljivo prihvatanje:**
- A→B→A bez mešanja planova, ostave, lista, assets, glasova ili budžeta; ne poslati A pending write u B.
- Offline dozvoliti izbor ranije keširanog važećeg članstva sa oznakom poslednje provere; novo članstvo traži mrežu.
- Novo pridruženo domaćinstvo sa zapisima starijim od postojećeg kursora potpuno se preuzme.
- Brisanje naloga čuva zajednički prostor preostalih članova i rešava poslednjeg vlasnika pre uklanjanja članstva.

**Konkretne provere koje implementacija mora da izvrši:**
- Migration fixture sa starim Accounts redom, starim cursor-om i pending delete; proveriti nepromenjene UUID-jeve i broj redova.
- Fake transport zadrži A odgovor do prebacivanja u B; potvrditi da se ne pojavi A sadržaj.
- Local pgTAP tri naloga/dva household-a, član oba, outsider, revoke; pregled supabase/migrations/20261030120700_delete_account.sql i Edge Function solo-household ponašanja.

### F066 — Razduživanje zajedničkih troškova (P2)

**Ciljni moduli (plan, ne napravljeni fajlovi):** `lib/domain/expense.dart (new)`; `lib/domain/money.dart (shared from G-MONEY)`; `lib/data/expense_repository.dart (new)`; `lib/features/shopping/expense_sheet.dart (new)`.

**Postojeće:** lib/data/database.dart nema Expense/Settlement; lib/data/shopping_repository.dart::_buy čuva kupljene potrebe, bez platioca, učesnika i iznosa. F043 je predložena osnova računa korpe, ne gotov ledger.

**Predloženi ugovor/model:**
- Expense(id,householdId,purchaseEventId?,currency,totalMinor,paidBy,revision,status draft|posted|void), ExpenseLine(totalMinor,beneficiaryWeights[]), Share(userId,amountMinor), Settlement(id,from,to,currency,amountMinor,confirmedAt). Lične stavke dodeliti samo tom korisniku; ne bacati ih iz ukupnog plaćenog iznosa. Za više platioca zasebne Payment reda sa sum(payment)=expense total.
- Posted dokument je nepromenljiv; ispravka pravi storno/replacement sa sourceExpenseId. Balance=payments-shares+outgoingSettlements-incomingSettlements. Predlog transfera je informativan i nije bankovno plaćanje. Svaka valuta ima zaseban ledger; odlazak člana ne briše dug ili menja istorijske udela.

**Zavisnosti:** F011; F043; G-MONEY; G-SCHEMA; F073 (optional receipt reconciliation).

**Male vertikale, redom:**
1. Draft trošak sa platiocem, izuzimanjem ličnih stavki i tačnom raspodelom.
2. Posted ledger, saldo i predlog transfera.
3. Potvrđeno poravnanje, storno i audit/idempotency.

**Merljivo prihvatanje:**
- A plati 10001 minor: lično A 2000, zajedničko 8001 sa jednakim težinama A/B/C; shares su A=4667,B=2667,C=2667 po stabilnom member-ID poretku, A saldo +5334, B/C -2667.
- Svaki događaj ima sum(payments)=sum(shares); suma salda domaćinstva po valuti je 0.
- Kada B plati A 2667, B saldo je 0, A +2667 i C -2667; duplirani settlementId ništa ne menja.

**Konkretne provere koje implementacija mora da izvrši:**
- Test-first parser i allocator; random/property fixtures: konzervacija minor jedinica, stabilnost pri drugačijem input poretku, nulte težine i rejected all-zero/negative weights.
- Golden 10001 primer iznad, refund/storno i više platioca; ne izvršavati upstream kod.
- Local RLS čitanje/sopstvena izmena draft-a/posted zabrana, rollback i replay; widget „Ko je platio”, „Lična stavka”, „Potvrdi poravnanje”.

### F067 — Slanje korpe online prodavnici (P2)

**Ciljni moduli (plan, ne napravljeni fajlovi):** `lib/domain/cart_draft.dart (new)`; `lib/data/retailer_adapter.dart (new interface)`; `lib/features/shopping/cart_export_sheet.dart (new)`.

**Postojeće:** lib/data/shopping_repository.dart i lib/features/shopping/shopping_screen.dart završavaju na lokalnoj/sinhronizovanoj nabavci. Nema retailer adapter-a, merchant productId ili checkout ugovora u lib/data/database.dart.

**Predloženi ugovor/model:**
- RetailerAdapter.probe() vraća unavailable|exportText|exportLink|cartApi sa region, storeBranch, checkedAt, limits i reasons; zahteva dokumentovan podržan interfejs i prava. MerchantMapping(ingredient/productRef,merchantSku,packSize,confidence,confirmedByUser). CartDraft(id,listSnapshotHash,merchantId,branchId,lines,substitutions,quoteExpiresAt,feesMinor?,currency,capabilityVersion).
- Najpre prikaži SKU, pakovanja, zamene, cenu i naknade; prenos zahteva izričitu radnju nad pregledanom korpom. submitExport sa idempotencyKey gde ugovor trgovca to podržava; unknown delivery status se proverava pre ponavljanja. Izvoz nije potvrda porudžbine; ne označava isBought ni dopunu ostave. Nema podržanog trgovca potvrđenog u ovom istraživanju.

**Zavisnosti:** F018; G-CAPABILITY; G-SCHEMA; F083 (optional availability C); F071 (optional promotions).

**Male vertikale, redom:**
1. Deterministički lokalni tekst/CSV izvoz i ručni product mapping.
2. Fake adapter sa capability probe, preview i zamenama.
3. Jedan stvarni adapter tek kada su prava/API ugovor dokazani; finalni checkout kod trgovca potvrđuje korisnik.

**Merljivo prihvatanje:**
- Nepokriveni artikli i nepoznate naknade su eksplicitni; nepodržan trgovac daje „Izvoz za ovu prodavnicu nije dostupan”.
- Promena liste ili istek quote-a obavezno poništava staru potvrdu pregleda.
- Izvoz ili timeout ne menja bought/expense/pantry; nijedna porudžbina nije automatski postavljena.

**Konkretne provere koje implementacija mora da izvrši:**
- Fake probe disabled/region mismatch/auth required; unit map 1200 g potrebe na 500 g SKU daje 3 pakovanja i 300 g viška.
- Widget potvrda tačnog snapshot-a, unavailable zamena, quote expiry i naknade.
- Contract fixtures za export payload; request timeout nakon slanja i sigurni replay/query status bez produkcijskih API poziva.

### F068 — Kartice lojalnosti (P2)

**Ciljni moduli (plan, ne napravljeni fajlovi):** `lib/domain/loyalty_card.dart (new)`; `lib/data/loyalty_card_repository.dart (new)`; `lib/features/shopping/loyalty_card_sheet.dart (new)`.

**Postojeće:** lib/data/database.dart nema loyalty card, a lib/features/shopping/shopping_list_view.dart nema kasni prikaz kartice. Barcode namirnice F017 nije isto što i sačuvana članska kartica.

**Predloženi ugovor/model:**
- LoyaltyCard(id,ownerUserId,retailerId,label,symbology,valueAsString,expiresAt?,status,sharePolicy=personal). Kod je string radi vodećih nula. Prvo podržati dokumentovane statične code128/EAN/QR formate kroz renderer iza interfejsa; dinamičke/rotirajuće kartice unavailable. Program eligibility token za F071 je samo tvrdnja da kartica postoji/da korisnik ispunjava uslov, ne dokaz da će kasa odobriti popust.
- Lične kartice sinhronizovati kao privatne korisničke podatke uz RLS, nikad automatski članovima domaćinstva ili u javni dokaz računa. Izbor da li deljenje program dozvoljava ostaje gate pre eksplicitnog opt-in deljenja.

**Zavisnosti:** G-SCHEMA; G-CAPABILITY.

**Male vertikale, redom:**
1. Ručni unos i privatno čuvanje koda sa validacijom symbology.
2. Offline prikaz iz nabavke i tekstualni fallback.
3. Provider/program capability i opcioni datum isteka; deljenje tek posle potvrđenih pravila programa.

**Merljivo prihvatanje:**
- Kod 0012345678905 roundtrip čuva obe vodeće nule; renderer generiše isti payload.
- Drugi član domaćinstva ne može čitati ličnu karticu direktnim upitom.
- Nepodržana/dinamička kartica prikazuje „Ova vrsta kartice nije podržana” i ne prikazuje lažno važeći statični kod.

**Konkretne provere koje implementacija mora da izvrši:**
- Barcode encode/decode fixture i checksum validacija gde format to zahteva; Unicode/dužina/leading-zero slučajevi.
- Local RLS isti household različiti user-i; offline cold start i sign-out session isolation.
- Fizički skener i osvetljenje uređaja samo sa sintetičkim test kodom, bez tvrdnje da trgovac prihvata karticu.

### F069 — Podsetnik blizu prodavnice (P3)

**Ciljni moduli (plan, ne napravljeni fajlovi):** `lib/domain/store_reminder.dart (new)`; `lib/data/store_reminder_repository.dart (new)`; `lib/features/shopping/store_reminder_sheet.dart (new)`; `lib/device/geofence_gateway.dart (proposed new interface; device package decision gated)`.

**Postojeće:** Nema geofence modela u lib/data/database.dart niti lokacijskog toka u lib/features/shopping/shopping_screen.dart. Postojeći AccountScope i lokalne otvorene ShoppingItems su tačke vezivanja, ne postojeća device capability podrška.

**Predloženi ugovor/model:**
- StoreReminder(id,userId,householdId,branchId,center,radiusMeters,enabled,listIds,cooldownSeconds) je sinhronizovana preferenca; GeofenceRegistration i poslednja obaveštenja su lokalni po uređaju. DeviceCapability probe platformSupported/locationServices/preciseLocation/backgroundPermission/notificationPermission/registrationQuota; dozvole tražiti tek po uključivanju.
- Dwell/enter → ponovo proveri aktivno članstvo i lokalnu otvorenu stavku → dedupe po reminder+visit+cooldown → lokalno obaveštenje. Nema upload-a istorije kretanja. Opoziv dozvole/članstva i odjava uklanjaju registracije; desktop unavailable daje ručni podsetnik. Android pozadinski događaji nisu trenutni; Apple adapter zahteva zaseban platform spike.

**Zavisnosti:** G-CAPABILITY; F041 (store identity); F063 (scope-aware reminders).

**Male vertikale, redom:**
1. Model podsetnika i fake geofence/notifier adapter.
2. Android permission/register/unregister lifecycle i cooldown.
3. iOS capability spike i real-device verifikacija; macOS ručni fallback dok podrška nije dokazano završena.

**Merljivo prihvatanje:**
- Sa otvorenim artiklom jedan dwell daje najviše jedno obaveštenje u 4 h; sve bought daje 0.
- Denied/restricted/unsupported ne blokira Nabavku i jasno prikazuje „Podsetnik na lokaciji nije dostupan”.
- Odjava ili uklanjanje iz household-a briše registracije tog scope-a i ne otkriva naziv liste na zaključanom ekranu po default-u.

**Konkretne provere koje implementacija mora da izvrši:**
- Fake clock i event fixture: dupli enter/dwell, enter posle cooldown-a, buy pre dwell-a, revoke pre callback-a, restart i reboot re-registration.
- Device matrix Android/iOS: deny→grant→revoke, battery saver i notifications denied; dokumentovati izmerena kašnjenja umesto obećanja.
- Test offline stale-list notification wording i tap otvara tačnu household/list scope uz novu proveru članstva.

### F070 — Stvarna isplativost obilaska prodavnica (P3)

**Ciljni moduli (plan, ne napravljeni fajlovi):** `lib/domain/shopping_route.dart (new)`; `lib/data/route_matrix_provider.dart (new interface)`; `lib/features/shopping/route_comparison_sheet.dart (new)`.

**Postojeće:** lib/domain/shopping_demand.dart računa potrebe i uporedive jedinice, ali nema route/store/Money model. ShoppingRepository.planTotals daje količine, ne trošak puta. F018 i F071 su predloženi podaci za cene i uslovne ponude.

**Predloženi ugovor/model:**
- RouteScenario(currency,storeAssignment,packCounts,goodsTotalMinor,transportTotalMinor,feesMinor,travelSeconds,shoppingSeconds,unknownItems,priceCoverage,assumptions,dataVersion). Objective=goods+transport+fees; hard constraint travel+shopping <= maxDurationSeconds. Vrednost vremena je opcioni odvojeni scenario, ne skriveni trošak.
- DistanceMatrixProvider sa mode/checkedAt/source/errors; bez njega korisnik unosi povratni put i trošak, a heuristika je označena kao procena. Prvo ograničiti na najviše 3 radnje i enumerisati sve dopuštene raspodele/pakovanja; ne obećavati globalni optimum van tog skupa. Haversine blizina nije dužina puta. Nepokriveni artikli sprečavaju tvrdnju da je jedna korpa ukupno jeftinija.

**Zavisnosti:** F018; F043; F071; G-MONEY; G-CAPABILITY; F083 (optional availability C).

**Male vertikale, redom:**
1. Ručni troškovi i vremena: jedna naspram dve radnje sa jednakom pokrivenošću.
2. Ograničen egzaktan optimizer i prikaz pretpostavki/nesigurnosti.
3. Distance provider tek uz dokazanu mogućnost, prava i quote/freshness invalidaciju.

**Merljivo prihvatanje:**
- Korpa A 100000 minor + put 10000 = 110000; A+B roba 90000 + put 25000 = 115000: jedna radnja je povoljnija za 5000 minor uprkos nižim cenama robe.
- Scenario 50 min ne ulazi u rezultat kad je limit 40 min.
- Nedostajuća cena ili matrica udaljenosti daje nepotpun scenario, ne 0 troška ili garantovanu uštedu.

**Konkretne provere koje implementacija mora da izvrši:**
- Golden ručni primer i brute-force oracle za <=3 radnje/<=6 artikala, MOQ/pakovanja i neispunjena promocija.
- Test dateline/straight-line map podatak ne glumi voznu distancu; deterministic tie storeId i isti snapshot.
- Widget prikaže prevoz, robu, naknade, vreme i pokrivenost; fake route provider unavailable/rate-limited/offline.

### F071 — Kuponi i uslovne akcije (P2)

**Ciljni moduli (plan, ne napravljeni fajlovi):** `lib/domain/promotion.dart (new pure evaluator)`; `lib/data/promotion_repository.dart (new)`; `lib/features/shopping/promotion_explanation_sheet.dart (new)`.

**Postojeće:** ShoppingItems i supabase/migrations/20261030120200_household_data.sql nemaju promotion model. Open Prices Price.discount_type je kategorizacija ponude, bez izvršivog predicate ugovora za količinu, vremenski interval i članstvo.

**Predloženi ugovor/model:**
- Promotion(id,retailerId,branchScope,productScope,currency,validFrom,validUntilExclusive,storeTimeZone,predicateAST,effect,stackGroup,priority,maxUses,source,sourceVersion). Predicate je tipiziran allowlist AST: All/Any, QuantityAtLeast, QualifyingSpendAtLeast, HasLoyaltyProgram, CouponActivated, StoreIn, ProductIn i WithinWindow; bez eval teksta ili AI generisanog izvršnog koda.
- Evaluator vraća eligible|ineligible|unknown sa reason codes i trace-om; efekat fixedBundlePrice/buyNPayM/percentOffBasisPoints/fixedOff ima limit i eksplicitno pravilo kombinovanja. Unknown predicate se ne primenjuje kao popust. Redemption rezervacija nije ostvarena ušteda, a ista couponId se ne troši dvaput.

**Zavisnosti:** F018; G-MONEY; F068 (optional loyalty eligibility); G-SCHEMA.

**Male vertikale, redom:**
1. Quantity/validity/loyalty predicate i obrazloženje za jednu ponudu.
2. Bundle/percentage effects, zaokruživanje i eksplicitna ekskluzivnost.
3. Aktivacija kupona, use-limit ledger i pregled kombinovanih ponuda.

**Merljivo prihvatanje:**
- Jedinica 10000 minor, buy2 bundle 15000: qty1 = 10000 bez popusta, qty2 = 15000, qty3 = 25000; ne primeniti 7500 na qty1.
- Loyalty potrebna + status unknown daje unknown i osnovnu cenu; interval [start,end) isključuje tačno end.
- 10% na 19999 minor daje discount 2000 i net 17999 po half-up pravilu; dva exclusive kupona ne sabiraju uštede.

**Konkretne provere koje implementacija mora da izvrši:**
- Truth table svih predicate čvorova i All(false,unknown)=false, Any(true,unknown)=true; ostalo po tri-state ugovoru.
- Fake clock/store time zone: UTC offset, DST i datum isteka; qty 1/2/3, pogrešna poslovnica i pakovanje.
- Golden cent/minor zaokruživanje, bundle remainder, cap, stacking, replay redemption i nedozvoljeni AST; svi podaci sintetički bez trgovca.

## Upstream dokaz i odluke o upotrebi

Cache: `/Users/urosmilutinovic/.cache/tavli-next-sources/D/`. Commit-i su HEAD klonova u trenutku pregleda; nisu obećanje kompatibilnosti sa budućim verzijama. Root LICENSE fajlovi su stvarno pročitani. Za oba AGPL projekta potvrđena je verzija 3, ali grant „only/or later” nije nezavisno razjašnjen; manifest koristi konzervativni AGPL-3.0-only marker i beleži nepoznanicu. Ni u jednoj varijanti nema kopiranja njihovog koda u ovom prolazu.

### kitchenowl — `3cc27f41e3de3d805abd66bdac9eb283eb16e72c`

Licenca: `AGPL-3.0-only`. Study and cite architecture only. No AGPL code, assets or tests copied; proposed Tavli design is an independently authored blueprint.

- [LICENSE](https://github.com/TomBursch/kitchenowl/blob/3cc27f41e3de3d805abd66bdac9eb283eb16e72c/LICENSE) — `root license`: Actual full AGPL version 3 file read. Project README also says AGPL-3.0; no permissive per-file exception observed in inspected source. only/or-later grant not further established; conservative no-copy decision applies either way.
- [kitchenowl/lib/services/transactions/shoppinglist.dart](https://github.com/TomBursch/kitchenowl/blob/3cc27f41e3de3d805abd66bdac9eb283eb16e72c/kitchenowl/lib/services/transactions/shoppinglist.dart) — `TransactionShoppingListAddItem.runLocal/runOnline; TransactionShoppingListRemoveItem`: Local MemStorage changes and persisted transaction classes are separate from API calls; server IDs/name fallback appear in requests.
- [kitchenowl/lib/cubits/shoppinglist_cubit.dart](https://github.com/TomBursch/kitchenowl/blob/3cc27f41e3de3d805abd66bdac9eb283eb16e72c/kitchenowl/lib/cubits/shoppinglist_cubit.dart) — `ShoppinglistCubit; _onConnectionChange; onShoppinglistItemAdd`: Socket listeners, reconnect refresh and a 30-second periodic fallback; event transaction uses forceOffline=true/saveTransaction=false to avoid echo.
- [backend/app/sockets/connection_socket.py](https://github.com/TomBursch/kitchenowl/blob/3cc27f41e3de3d805abd66bdac9eb283eb16e72c/backend/app/sockets/connection_socket.py) — `on_connect`: Authenticated user joins rooms for memberships.
- [backend/app/sockets/shoppinglist_socket.py](https://github.com/TomBursch/kitchenowl/blob/3cc27f41e3de3d805abd66bdac9eb283eb16e72c/backend/app/sockets/shoppinglist_socket.py) — `on_add; on_remove`: Authorizes Shoppinglist before item mutations and emits household-room events. on_remove imports removeShoppinglistItem while helper is separately named removeShoppinglistItemFunc in controller: observed source inconsistency, not a validated working socket removal path.
- [backend/app/controller/shoppinglist/shoppinglist_controller.py](https://github.com/TomBursch/kitchenowl/blob/3cc27f41e3de3d805abd66bdac9eb283eb16e72c/backend/app/controller/shoppinglist/shoppinglist_controller.py) — `removeShoppinglistItemFunc`: Deletes current association; optional client removed_at feeds History. This is not expected-revision conflict arbitration.
- [backend/app/helpers/authorize_household.py](https://github.com/TomBursch/kitchenowl/blob/3cc27f41e3de3d805abd66bdac9eb283eb16e72c/backend/app/helpers/authorize_household.py) — `RequiredRights; authorize_household`: Member/admin/admin-or-self authorization; server admin bypass and member owner/admin flags. Use design observation, not Tavli access policy verbatim.
- [backend/app/models/household.py](https://github.com/TomBursch/kitchenowl/blob/3cc27f41e3de3d805abd66bdac9eb283eb16e72c/backend/app/models/household.py) — `Household; HouseholdMember`: Household owns lists, items and expenses. Owner/admin flags and float expense_balance observed.
- [kitchenowl/lib/enums/shoppinglist_sorting.dart](https://github.com/TomBursch/kitchenowl/blob/3cc27f41e3de3d805abd66bdac9eb283eb16e72c/kitchenowl/lib/enums/shoppinglist_sorting.dart) — `ShoppinglistSorting.sortShoppinglistItems`: Alphabetical/category/algorithmic sorting; no per-store aisle mapping established.
- [backend/app/models/expense.py](https://github.com/TomBursch/kitchenowl/blob/3cc27f41e3de3d805abd66bdac9eb283eb16e72c/backend/app/models/expense.py) — `Expense; ExpensePaidFor`: Float amount and integer factor allocation associations.
- [backend/app/service/recalculate_balances.py](https://github.com/TomBursch/kitchenowl/blob/3cc27f41e3de3d805abd66bdac9eb283eb16e72c/backend/app/service/recalculate_balances.py) — `recalculateBalances`: Paid amounts minus weighted expenses, scoped by household; floating-point calculations unsuitable for proposed Tavli finance contract.
- [kitchenowl/lib/models/expense.dart](https://github.com/TomBursch/kitchenowl/blob/3cc27f41e3de3d805abd66bdac9eb283eb16e72c/kitchenowl/lib/models/expense.dart) — `Expense; PaidForModel`: Flutter double amount, paidById and factor-based paidFor. Independent implementation should use integer minor units.

### open-prices — `ecb334d80083908cabd372df04121314d628af8c`

Licenca: `AGPL-3.0-only`. Study/cite only; no AGPL code copied. Future adapter needs independent implementation plus separate data/evidence license, attribution and current API contract validation.

- [LICENSE](https://github.com/openfoodfacts/open-prices/blob/ecb334d80083908cabd372df04121314d628af8c/LICENSE) — `root license`: Actual AGPL version 3 LICENSE read, not a search snippet; no permissive exception established. Exact only/or-later project grant remains unresolved.
- [open_prices/prices/models.py](https://github.com/openfoodfacts/open-prices/blob/ecb334d80083908cabd372df04121314d628af8c/open_prices/prices/models.py) — `Price; Price.clean; Price.set_is_duplicate_of`: Three-decimal DecimalField prices, currency/date/store/proof references and duplicate identity; values can be nullable.
- [open_prices/prices/validators.py](https://github.com/openfoodfacts/open-prices/blob/ecb334d80083908cabd372df04121314d628af8c/open_prices/prices/validators.py) — `validate_price_price_rules; validate_price_date_rules; validate_price_location_rules; validate_price_proof_rules`: Discount/base-price consistency, future date rejection, paired OSM identity, proof owner/type compatibility; callable validation is more than table shape.
- [open_prices/prices/constants.py](https://github.com/openfoodfacts/open-prices/blob/ecb334d80083908cabd372df04121314d628af8c/open_prices/prices/constants.py) — `DISCOUNT_TYPE_LIST; PRICE_PER_LIST`: Discount class labels and UNIT/KILOGRAM/LITER bases; labels are not a full executable promotion predicate.
- [open_prices/api/prices/filters.py](https://github.com/openfoodfacts/open-prices/blob/ecb334d80083908cabd372df04121314d628af8c/open_prices/api/prices/filters.py) — `PriceFilterForm.clean; PriceFilter.filter_queryset`: Coordinates/radius supplied together, validated bounds; nearby location IDs constrain prices plus currency/date/product filters.
- [open_prices/locations/models.py](https://github.com/openfoodfacts/open-prices/blob/ecb334d80083908cabd372df04121314d628af8c/open_prices/locations/models.py) — `LocationQuerySet.nearby`: Bounding box plus spherical proximity, antimeridian/pole handling; proximity is not route travel cost.
- [open_prices/proofs/models.py](https://github.com/openfoodfacts/open-prices/blob/ecb334d80083908cabd372df04121314d628af8c/open_prices/proofs/models.py) — `ProofQuerySet`: Receipt/price-tag/import distinctions and draft/community/consumption grouping observed.
- [open_prices/api/prices/views.py](https://github.com/openfoodfacts/open-prices/blob/ecb334d80083908cabd372df04121314d628af8c/open_prices/api/prices/views.py) — `PriceViewSet.get_authenticators/create/get_serializer_class`: Read versus authenticated create/update paths and owner handling observed. No live API call, availability, Serbia coverage or data redistribution rights verified.

### dinero.js — `76b969e519dc44675d4af898d25629995d0b16f2`

Licenca: `MIT`. Copy one complete source file plus LICENSE verbatim for review/reference only. Implement Tavli allocator independently with validated nonnegative weights, stable member-ID ties, bounded exact arithmetic; do not run this subset.

- [LICENSE](https://github.com/dinerojs/dinero.js/blob/76b969e519dc44675d4af898d25629995d0b16f2/LICENSE) — `MIT grant and Sarah Dayan copyright`: Actual complete license read; preserved verbatim with copied source. No NOTICE found in upstream file inventory.
- [packages/dinero.js/src/core/utils/distribute.ts](https://github.com/dinerojs/dinero.js/blob/76b969e519dc44675d4af898d25629995d0b16f2/packages/dinero.js/src/core/utils/distribute.ts) — `distribute`: Integer division and remainder distribution by descending ratios; full unchanged source file collected as reference, imports not vendored.
- [packages/dinero.js/src/core/utils/__tests__/distribute.test.ts](https://github.com/dinerojs/dinero.js/blob/76b969e519dc44675d4af898d25629995d0b16f2/packages/dinero.js/src/core/utils/__tests__/distribute.test.ts) — `distribute test suite`: Examples 1003 split 50/50, negative/zero ratios, largest-ratio residue and MAX_SAFE_INTEGER guard inspected, not run or copied.
- [packages/dinero.js/src/core/utils/equal.ts](https://github.com/dinerojs/dinero.js/blob/76b969e519dc44675d4af898d25629995d0b16f2/packages/dinero.js/src/core/utils/equal.ts) — `equal`: Comparison via injected calculator; inspected dependency.
- [packages/dinero.js/src/core/utils/greaterThan.ts](https://github.com/dinerojs/dinero.js/blob/76b969e519dc44675d4af898d25629995d0b16f2/packages/dinero.js/src/core/utils/greaterThan.ts) — `greaterThan`: Comparison helper dependency inspected.
- [packages/dinero.js/src/core/utils/greaterThanOrEqual.ts](https://github.com/dinerojs/dinero.js/blob/76b969e519dc44675d4af898d25629995d0b16f2/packages/dinero.js/src/core/utils/greaterThanOrEqual.ts) — `greaterThanOrEqual`: Comparison helper dependency inspected.
- [packages/dinero.js/src/core/utils/lessThan.ts](https://github.com/dinerojs/dinero.js/blob/76b969e519dc44675d4af898d25629995d0b16f2/packages/dinero.js/src/core/utils/lessThan.ts) — `lessThan`: Comparison helper dependency inspected.
- [packages/dinero.js/src/core/types/DineroCalculator.ts](https://github.com/dinerojs/dinero.js/blob/76b969e519dc44675d4af898d25629995d0b16f2/packages/dinero.js/src/core/types/DineroCalculator.ts) — `DineroCalculator; DineroComparisonOperator`: Injected arithmetic interface; confirms full copied file is a reference requiring upstream dependencies, not standalone executable code.

KitchenOwl zaključak za F011/F063: autentifikovane household rooms + fallback refresh su koristan obrazac, ali se ne prenose MemStorage, socket code ili server admin bypass u Tavli. Postojeći Tavli drift/outbox je osnova. Pregledani KitchenOwl timestamp removal/history put nije dokaz automatskog rešavanja konkurentnih edit-a. Posmatrani on_remove/helper nazivni nesklad je zabeležen radi ograničenja dokaza, bez pokušaja izvršavanja ili popravljanja upstream-a.

KitchenOwl za F066: paid-by/paid-for i integer factors su dobar model pitanja, dok float iznos i float expense_balance nisu osnova za tačan Tavli obračun. Open Prices za F018: product/category, price basis, date, branch i proof su provereni izvori oblika podataka; null/missing vrednosti zahtevaju status nepoznato. Za F071 discount_type samo kategorizuje — nema prikupljenog izvršivog kuponskog engine-a. F041, F044, F045, F056, F067–F071 su sopstveni predlozi i ne predstavljaju tvrdnju da navedeni upstream projekti već imaju te kompletne funkcije.

### Platform dokumentacija za F069

[Android — Create and monitor geofences](https://developer.android.com/develop/sensors-and-location/location/geofencing) je otvoren tokom istraživanja: opisuje fine/background location dozvole, 100 registracija po app/device user, dwell i odložene pozadinske događaje. Zato su podrška, dozvole i registration lifecycle posebni probe/test slučajevi, a podsetnik nema garanciju trenutnog izvršenja. [Apple — Monitoring proximity](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions) vratio je JS placeholder, a pokušaj Markdown linka je neuspešan; iz ovog pristupa se ne tvrde Apple kvote ili završena podrška.

## Migracije, kompatibilnost i zaštita podataka

- Postojeći ručni/stari shopping redovi ostaju validni: nullable detalji, bez nametnute cene, bez kreiranja sku/claim-a po default-u. Povezane kupovine i pantry sourceShoppingItemId ostaju isti. Metadata snapshot pravilo i deletion/cascade lifecycle specifikovati pre F010.
- Novi membership bootstrap ne sme koristiti samo trenutni account-global updated_at cursor: ranije nastali podaci mogu biti preskočeni. Ne menjati remote filtriranje u aktivni household bez nove cursor strategije. Realtime može propustiti event; nije zamena za ovaj bootstrap.
- Role/grants migracije uključuju composite FK, storage policies, revoke i stare build-ove. Povećanje broja članova zahteva pregled account deletion i owner transfera; ne obećavati da sadašnja solo-household funkcija rešava sve uloge i ledger identitete.
- Instant opoziv pristupa uređaju koji je offline nije tehnički ostvariv samo RLS-om. Cached članstvo ima vreme poslednje provere; pri sledećoj vezi pre deljenog upload-a potvrditi membership, ugasiti pretplate i ukloniti nedozvoljeni cache iz UI. Već viđeni offline podaci ne mogu se daljinski pouzdano „odvideti”. Ne mešati personal loyalty podatke i zajedničke assets.
- Finance migration je nov domen: quantity double/micros se ne konvertuje u novac. Poznata cena ne znači dostupnost SKU. Stale observed price nije garantovana checkout cena. Money/quote/revision wire format versionirati; nepodržan format daje kontrolisanu poruku i read-only gde treba.
- Kartice, računi i podsetnici ne ulaze u logove. Podsetnik default-om ne otkriva nazive privatnih stavki na zaključanom ekranu. Prodavnici se šalje samo pregledani CartDraft, ne privatni ledger/kartica/domaćinstvo. Nikakva porudžbina ili bankovni transfer nisu izvršeni.

## Prikupljeni referentni kod

`research/reference-code/D/dinero/packages/dinero.js/src/core/utils/distribute.ts` je jedan mali kompletan neizmenjen upstream TypeScript fajl (78 linija); uz njega je originalni `dinero/LICENSE`, sa `Copyright (c) 2018-present Sarah Dayan`. Nema upstream NOTICE fajla u pregledanom inventory-ju. Commit, source URL i SHA-256 svakog kopiranog fajla su u `research/reference-code/D/provenance.json` i manifestu. To je čitljiva referenca, ne standalone izvršni paket: upstream imports ostaju, zavisnosti nisu kopirane. Nije pokrenut, testiran ni uključen u Flutter runtime. Independent Dart allocator mora dobiti sopstvene testove i stabilno definisana pravila ostatka; algoritam u referenci koristi descending ratios, a predlog iz ovog plana largest fractional remainder.

KitchenOwl/Open Prices kod, testovi, assets i video nisu kopirani. Za njih je rezultat obrazac za sopstvenu implementaciju sa tačnim dokaznim putanjama iznad.

## Otvorena pitanja i završna verifikacija
- Open Prices Serbia/branch/product coverage and freshness have not been measured; no production API queried.
- Open Prices database, proof-image redistribution terms, rate limits and future API contract need a separate integration gate; AGPL software license does not establish data/image rights.
- Exact AGPL only/or-later project grant not conclusively established; root LICENSE confirms AGPL v3 and no-copy decision is unchanged.
- No retailer cart API, partnership, checkout flow or loyalty-program acceptance verified; manual export is the initial deliverable.
- Apple documentation page requires JS and its Markdown link failed in browsing tool; Apple capability/quotas/background delivery remain an implementation spike, not a verified support claim.
- Household role product policy and ledger visibility proposed here need final spec decisions; no role migration has been implemented.
- Currency exponent table, cash rounding rules and receipt discrepancy policy must be versioned and confirmed before monetary implementation.
- No native device tests, app tests, database tests or upstream tests were run in this research-only stream.

Istraživačka verifikacija: validirati JSON parsiranje, tačan skup 15 D ID-jeva u odnosu na streams.json, prisustvo svih obaveznih polja, da svaka Tavli dokazna putanja postoji, sve upstream dokazne putanje na pinovanom clone-u, SHA-256 i byte-for-byte podudarnost kopija, neizmenjene originalne licence i inventory celog D reference direktorijuma. Rezultati tih provera su prijavljeni u završnoj poruci ovog stream-a; aplikacioni/native/DB/upstream testovi nisu izvršeni. Ovaj izveštaj ne menja status implementacije nijednog Fnnn.

**Stvarno izvršena završna provera:** JSON je parsiran, skup 15 ID-jeva odgovara tačno D dodeli, obavezna polja i dependencies format su provereni, 28 upstream putanja i 17 Tavli current-state putanja postoje, obe MIT kopije (izvor + LICENSE) su byte-for-byte iste i SHA-256 odgovara manifestu. D reference inventory ima 4 fajla (dve kopije, README i provenance). Aplikacioni, DB, device i upstream testovi nisu pokrenuti.
