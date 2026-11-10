# B — Planiranje i kalendar: proverljiv blueprint

Datum istraživanja: 09.11.2026. Baseline Tavli commit: `1eca2c3d14fb5dd9b25a42958aa018c8d8dfbb94`.
Ovo je istraživanje i plan implementacije 15 dodeljenih predloga, ne implementacija aplikacije. Čitani su AGENTS.md, ustav, product-design, IDEAS-90, feature-register i coordination/streams. Nisu menjani aplikacija, testovi, migracije, zajednički dokumenti ili git stanje. Nisu čitane tajne niti kontaktiran produkcijski backend.

## Dokazano postojeće stanje

- `lib/domain/plan_calendar.dart`: CivilDate čuva kalendarski datum bez zone; weekOf, monthOf, weekPeriods i periodFor daju ponedeljak–nedelja i preseke meseca. `test/domain/plan_calendar_test.dart` već opisuje šest perioda novembra 2026, DST i prestupne dane. To su postojeći testovi pročitani u ovom prolazu, nisu pokrenuti.
- `lib/domain/meal_plan.dart`: PlanRequest ima najviše 31 dan, globalne porcije i opcioni skup slotova; PlanDraft je sesijski i čuva snapshots, PlanBase i nedostajuća mesta. PlannedMeal ima isLocked/isCooked, bez eaten, away, preparation veze ili prisutnosti. regenerableSlots čuva zaključane, skuvane i prošle obroke.
- `lib/domain/shopping_source.dart`: RecipeSnapshot zamrzava sastojke, porcije, opcione korake i jedno prepMinutes polje. Nema aktivnog/ukupnog trajanja niti resursa po koraku.
- `lib/data/meal_plan_repository.dart`: approve u jednoj lokalnoj transakciji upisuje plan, nove recepte, entries, outbox i poziva ShoppingRepository.reconcilePlan. fingerprint je JSON plan.toJson + entries sortirani po id. Štiti lokalni nacrt od promene plana; ne obuhvata ostavu, cene, buduće veze, niti pruža server CAS. changeServings odbija skuvan obrok; setCooked samo menja oznaku i usklađuje nabavku. removeMeal čuva zaštitu i uklanja izvor kroz shopping repository.
- `lib/data/shopping_repository.dart`: reconcilePlan pravi izvor po entry-ju sa snapshot-om i periodom; isCooked zatvara izvor. _demand skalira recept prema entry servings. _reconcile računa celo domaćinstvo, preskače zatvorene/superseded izvore, koristi confirmed supply i identitet iste fizičke zalihe. Ne rušiti te invarijante zasebnim leftover ili template kalkulatorom.
- `lib/data/database.dart`: MealPlans/MealPlanEntries nemaju aggregate revision ili eksplicitni entry kind; ShoppingItems.purchaseProvenanceJson zamrzava poreklo kupovine. `lib/sync/entities.dart`: MealPlanEntity i MealPlanEntryEntity mapiraju postojeće redove i household scope; atomarnost više server redova nije dokazana lokalnom transakcijom.
- `lib/ai/meal_plan_ai.dart`: MealPlanAI.propose traži raspored po nedeljnim delovima i recepte u grupama po 3, podržava resume/cancel; parseOutline proverava slotove i recipeId, parseSummaries porcije i sastojke. Nema verifikacije dnevnih pravila ili vremena. AI nacrt ništa ne čuva.
- `lib/features/planning/plan_generation.dart`: PlanGenerationState ima jedan nacrt, useRecipe postavlja recept na slot, save je postojeća potvrda. `plan_preview_screen.dart`, `meal_entry_detail.dart`, `meal_entry_card.dart` i `plan_calendar.dart:PlanMonthCalendar` su tačke nadogradnje postojećeg toka, bez paralelnog planera.

## Zajednički ugovori i redosled

**G-SYNC — migracije i offline ugovor.** Svaka nova tabela/kolona ide kroz drift schemaVersion, migraciju i test starog snapshot-a; novi SyncEntity, SyncedWriter i fake-backend roundtrip. Server: nove append-only migracije, RLS/grants samo authenticated i lokalni pgTAP sa dva naloga/domaćinstva. UI čita lokalni cache. UUID/operationId se generišu pre upisa; partial upload/retry ne ostavlja child bez parent-a. Ne prebacivati postojeće per-row writes u novi sistem dok replay/compatibility nije dokazan.

**G-PLAN-REV — odobrenje agregata.** Proširiti postojeći repository command ugovor: PlanCommand{operationId,planId,expectedRevision,expectedInputFingerprint,patch}. Lokalni command journal+optimistic apply i server atomski RPC sa household proverom, unique operationId, revision CAS i koherentnim delta setom. Server vraća accepted revision ili conflict; pri konfliktu sačuvati nacrt i obnoviti pregled, ne prepisati tuđi plan. Pored lokalnog fingerprint-a, novi otisak uključuje kind, preparations, consumption links, attendance i rule snapshots; metadata/inventory/cene imaju zasebne ulazne otiske kada utiču na odluku. Zaštita zaključanih/skuvanih/prošlih ostaje u repository-ju, ne samo UI-ju. Jedinstven slot po planu/date/type proveriti i ograničiti bez gubitka postojećih duplikata pri migraciji. Ovo je temelj za undo i zajedničke ostatke, ne tvrdnja da baseline već ima distribuiranu atomarnost.

**G-DEMAND — jedan izvor sirovinske potrebe.** Pre leftover migracije svaki običan recipe entry je jedna Preparation i jedna consumption alokacija. Identitet demand source mora ostati mapiran na legacy source/purchased provenance; ne napraviti paralelni source pri backfill-u. Novi preparation daje jedan source; cookServings/yield određuju demand, consumption servings samo deljenje gotovih porcija. Datum kupovine prati cookSlot, ne datum jedenja. Ponavljanje istog recepta bez eksplicitne veze znači odvojene pripreme. Uz cook->leftover/away prvo pregled razlike, pa reuse postojećeg reconcile-a. Čuvati kupljene/ručne stavke i zatvorene alokacije; zatvaranje kuvanja nije potvrda stvarne potrošnje ostave. Cross-week veze računaju se preko celog plana/domaćinstva; undo ne vraća zalihe kao da sigurno nisu potrošene. F075 može dodati masu/yield, F040 bacanje, ali inicijalni leftover radi sa potvrđenim porcijama i ne računa rok bez podataka.

**G-TIME — datum nije trenutak.** CivilDate ostaje datum plana. Za podsetnik, timed ICS i scheduling dodati LocalTime+IANA zone i eksplicitnu konverziju na UTC interval. Ambiguous/nonexistent lokalni sat traži izbor ili validacionu grešku. Putovanje ne menja datum obroka; režim prati zonu uređaja samo ako je izričito izabran. Clock i gateway se injektuju. Nepoznato trajanje nije nula.

**G-FEED — samo čitanje ka spolja.** F060 je read-only projekcija sinhronizovanog plana; ne uvozi busy niti poziva event-write API. Link je zasebna opoziva capability, bez Supabase auth tokena u URL-u, stored digest i redacted access logs. Kreiranje/rotacija je authenticated i scoped; javni endpoint ima samo ograničenu projekciju i bounded date range, rate limit/ETag. UID stabilan za život događaja, revision monoton i pri undo-u; vreme poll-a ne menja revision. Za obrisane unose čuvati cancellation tombstone u definisanom prozoru. Obroci podrazumevano transparentni/celodnevni. Revocation zaustavlja buduće čitanje, ne povlači kopije. Detalje folding/escaping, DATE i sequence proveriti prema [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545), naročito §§3.1, 3.3.11, 3.8.2.2, 3.8.4.7, 3.8.7.4; sopstvena implementacija, bez kopiranja AGPL serializer-a.

**G-AVAILABILITY — samo zauzetost ka unutra.** F090 nije pretplata F060 i ne deli njene ključeve/dozvole. [Google Freebusy query](https://developers.google.com/workspace/calendar/api/v3/reference/freebusy/query) dokumentuje busy start/end, intervale [start,end), scope-ove calendar.freebusy/calendar.events.freebusy i parcijalne greške. Adapter mora dokazati najmanji dovoljan scope za izabrani tip kalendara; API dostupnost i OAuth registracija ostaju uslovne. Nema Events.list fallback-a sa čitanjem opisa. Ako platforma ne može minimalnu granicu, prikazuje unavailable i ručne prozore. Cache kratkotrajan/privatan na uređaju, bez household sync-a ili AI promptova; disconnect briše cache. Busy ne garantuje da je osoba zaista slobodna niti automatski pomera sačuvan plan.

**Metadata gates.** G-RULE-METADATA uvodi potvrđene oznake/sastojke i trovalentni evaluator, bez zavisnosti od URL uvoza F001 ili rangiranja rokova F005. G-HARD-CONSTRAINTS je zajednički ugovor sa streamom A za neizuzimljive alergije/ishranu; proveriti stvarni postojeći taste-profile model pre implementacije, ne izmišljati da su dnevna pravila već prisutna. G-EQUIPMENT-METADATA uvodi potvrđene strukturisane zahteve i inventar opreme uz postojeći snapshot. G-PACKAGE-CATALOG uvodi potvrđenu veličinu pakovanja sa uporedivom jedinicom; F037 otvoreno pakovanje i F038 ture mogu kasnije dati bolju zalihu, ali sami nisu katalog veličina. F018 je izvor cena za F061; ručno potvrđene cene mogu prethoditi integraciji, dok nepoznati troškovi ostaju nepoznati.

Implementirati po jednu vertikalnu funkciju/spec/branch: prvo G-SYNC/G-PLAN-REV; zatim nezavisne P1 F033/F031/F034/F007; F012 uvodi accounting osnovu pre attendee/batch/parallel zavisnika. F062 prvo može pokriti jednu običnu zamenu, ali opšti undo tek kad su svi novi agregatni članovi uključeni. P2 nadogradnje rade na stabilnom demand/model ugovoru; P3 F052/F090 tek posle potvrđenih vremena/resursa. F060 može odvojeno posle stabilnih identiteta/revizija i feed capability probe-a. Prioritet P1/P2/P3 označava zavisnosni red, ne rok isporuke.

Sve implementacije: domen/parsing prvo test-first, fake AI/backend/gateways; izmenjena i susedna funkcija, flutter analyze/test i macOS smoke po pravilima projekta. Novi UI tekst srpski Latin; postojeće animacije sačuvati. Predloženi izrazi: „Primeni šablon”, „Ostaci od prethodne pripreme”, „Pojedeno”, „Van kuće”, „Aktivno vreme”, „Ukupno vreme”, „Neprovereno”, „Poništi izmenu plana”, „Zauzetost nije proverena”.

## Petnaest vertikalnih predloga

### F007 — Šabloni nedelje (P1)

**Postojeće stanje:** lib/domain/meal_plan.dart: MealPlan/PlanDraft imaju apsolutne datume, snimke i PlanBase; lib/data/meal_plan_repository.dart: approve kreira nove izvore kroz reconcilePlan. Nema modela šablona.

**Predloženi ugovor/model:** PlanTemplate{id,householdId,name,schemaVersion,days[dayOffset,mealType,entryKind,snapshot,recipeId,servings,preparationKey]}; sačuvati sadržaj, bez kupljenih stavki, cooked/locked statusa i rezervacija. applyTemplate(anchor,portionOverrides,targetBase) vraća PlanDraft; relativne veze priprema premapirati u nove UUID. Ne kopirati postojeće izvore potražnje.

**Zavisnosti:** G-SYNC, G-PLAN-REV.

**Mali vertikalni koraci:**

1. Sačuvaj sedam relativnih dana iz postojećeg plana i prikaži sadržaj šablona offline.
2. Primeni na novi datum uz pregled praznih mesta, novih porcija i nove identitete.
3. Primeni na postojeći plan uz diff i zaštitu zaključanih/skuvanih/prošlih obroka; odobri kroz postojeći repository.

**Merljivi kriterijumi prihvatanja:**

- Primena 2 puta daje 2 nezavisna plana i izvore; promena jednog ne menja šablon/drugi plan.
- Od 28.12.2026. sedmi dan je 03.01.2027; stari isCooked se ne prenosi.
- Pregled i odbacivanje ne menjaju recepte, nabavku ili outbox; obrisani izvorni recept ostaje upotrebljiv preko snimka.

**Konkretne provere u implementaciji (nisu pokrenute):**

- Domain: relativni datumi preko godine i prestupnog dana; povezane pripreme imaju nove, konzistentne ID-jeve.
- Repository: broj upisa/outbox-a pre i posle odbačenog pregleda, dupli submit operationId, stari fingerprint.
- Widget: primena na telefonu/rail-u i tekst 2×; regresija test/data/meal_plan_repository_test.dart.

### F012 — Povezani ostaci (P2)

**Postojeće stanje:** lib/domain/meal_plan.dart: PlannedMeal ima servings i isCooked, bez pojma pojedeno; lib/data/shopping_repository.dart: reconcilePlan stvara izvor za svaki unos sa snapshot-om, _demand skalira njegove porcije. Kopiran recept sutradan danas duplira potražnju.

**Predloženi ugovor/model:** Preparation{id,householdId,planId,cookSlot,snapshot,plannedYield,actualYield?,status}; MealConsumption{id,entryId,preparationId,reservedServings,eatenServings?,status}. Unos ima kind=cook|leftover|away. Potražnja sirovina pripada preparationId i cookSlot-u jednom; servings za jedenje nisu yield pripreme. Rezervacije ukupno <= raspoloživ prinos; status planned/cooked/discarded i reserved/eaten/released su odvojeni. F075 može dodati merenu masu, ali nije uslov za ručne porcije.

**Zavisnosti:** G-SYNC, G-PLAN-REV, G-DEMAND.

**Mali vertikalni koraci:**

1. Migriraj svaki legacy recipe unos u jednu pripremu i jednu konzumaciju, bez promene ukupne potražnje.
2. U pregledu povećaj prinos i poveži budući obrok sa ostatkom; prikaži račun porcija i jednu nabavku.
3. Potvrdi skuvano i zatim pojedeno odvojeno; premeštanje/brisanje/undo proverava sve zavisne obroke.

**Merljivi kriterijumi prihvatanja:**

- Priprema 6 porcija sa 600 g pasulja: 4 večeras + 2 sutra = 600 g potrebe, nikada 800 g ili 1.2 kg.
- Promena sutrašnje rezervacije sa 2 na 3 bez većeg prinosa je odbijena; promena planiranog prinosa na 7 pre kuvanja daje 700 g.
- Skuvano zatvara sirovinsku nabavku jednom i zadržava postojeće rezervacije zalihe; pojedeno ne pravi novo skidanje sirovina.
- Brisanje pripreme sa vezanim ostacima zahteva eksplicitno razvezivanje/zamenu u pregledu; drugi household ne može rezervisati prinos.

**Konkretne provere u implementaciji (nisu pokrenute):**

- Domain: 6=4+2, 5<4+2 invalidno, ciklus/veza na kasniju pripremu/negativan prinos zabranjeni.
- Repository: ponovljena cooked/eaten potvrda je idempotentna; cooked->uncooked uz već eaten zavisnike odbijen; cross-week ostatak ne stvara izvor u drugoj nedelji.
- Sync/RLS: dva uređaja istovremeno rezervišu poslednje 2 porcije; server prihvata najviše jednu komandu.
- Regresija supply allocations i purchaseProvenanceJson, ručna i kupljena stavka ostaju posle uklanjanja veze.

### F014 — Grupe jela koje troše pakovanja (P2)

**Postojeće stanje:** lib/ai/meal_plan_ai.dart: MealPlanAI.propose ima pantryNames i raspored po nedeljama, bez podataka o veličini pakovanja; lib/domain/shopping_demand.dart računa normalizovane potrebe.

**Predloženi ugovor/model:** PackageOption{ingredientKey,unitGroup,sizeMicros,source,observedAt}; BundleProposal{3..5 draft meals,packageChoices,demandTotals,residuals,coverage}. Rangiranje deterministički računa ceil(uncovered/size)*size-uncovered po uporedivoj jedinici. Ostatak pakovanja nije kvarenje niti novac. AI može predložiti grupu, kod proverava količine i uslove.

**Zavisnosti:** G-DEMAND, G-PACKAGE-CATALOG.

**Mali vertikalni koraci:**

1. Ručno potvrđene veličine pakovanja i tačan obračun ostatka za jednu namirnicu.
2. Pregled grupe 3–5 jela uz pokrivenost podacima i postojeću zalihu raspoređenu jednom.
3. Odobri grupu kao PlanDraft, uz zamenu jela i ponovno računanje.

**Merljivi kriterijumi prihvatanja:**

- Tri jela traže 200+150+100 g; pakovanje 500 g bez zalihe daje 1 pakovanje i 50 g ostatka.
- Sa 100 g potvrđene zalihe kupuje se 500 g za 350 g nepokrivene potrebe, ostatak 150 g; zaliha se ne oduzima po jelu.
- Nepoznata veličina/jedinica je Nepoznato, ne nula; nema tvrdnje o uštedi bez uporedivih cena.

**Konkretne provere u implementaciji (nisu pokrenute):**

- Domain unapred izračunati primeri 450/500, 550/500=>2 pakovanja, mešane neuporedive jedinice.
- Repository preview bez upisa i approve jednom; postojeće kupljeno ne nestaje.
- Widget zamena jednog jela menja zbir/ostatak i prikazuje izvor veličine.

### F015 — Podsetnici za pripremu (P2)

**Postojeće stanje:** lib/domain/shopping_source.dart: RecipeSnapshot ima tekstualne steps i prepMinutes; lib/domain/plan_calendar.dart: CivilDate nema vreme/zonu. U pregledanim planning modelima nema pripremnih obaveza.

**Predloženi ugovor/model:** PrepObligation{id,preparationId,label,offsetMinutes,anchorKind,cookLocalTime,zoneId,enabled,revision}; NotificationGateway.capabilities/probe/schedule/cancel. Ručno uneta obaveza prvo; AI predlog mora da se potvrdi. Obaveze nisu tajmeri kuvanja F009. Trajno čuvati nameru, a raspored lokalnih notifikacija ponovo izvesti pri promeni plana/zone/dozvole.

**Zavisnosti:** G-SYNC, G-TIME, F012.

**Mali vertikalni koraci:**

1. Ručno dodaj obavezu uz datum, sat i zonu u detalju pripreme.
2. Probe dozvole/platforme i lokalno zakazivanje sa stabilnim ID-jem.
3. Reconcile promena, brisanja, undo-a i ponovnog pokretanja; predlozi iz recepta uz pregled.

**Merljivi kriterijumi prihvatanja:**

- Kuvanje 10.11.2026. u 18:00 Europe/Belgrade i offset 12 h daju podsetnik u 06:00.
- Pomeri kuvanje za 1 h: tačno jedan novi aktivan podsetnik, stari otkazan; retry ne duplira.
- Odbijena dozvola prikazuje Podsetnici nisu dostupni i obavezu u aplikaciji; nema obećanja tačnog vremena isporuke.

**Konkretne provere u implementaciji (nisu pokrenute):**

- Fake clock/gateway: denied, unsupported, reboot, stale revision, prošli rok.
- Zone testovi nonexistent/ambiguous sat pri DST: eksplicitni izbor bez tihog pomeranja CivilDate.
- Widget promena/suppress/cancel i gašenje na odjavi; OS smoke provera tek u implementaciji.

### F031 — Želim uskoro da kuvam (P1)

**Postojeće stanje:** lib/features/planning/plan_generation.dart: useRecipe postavlja recept na određeni MealSlot; PlanRequest.only očekuje datirana mesta. Nema nedatiranog reda u pregledanim modelima.

**Predloženi ugovor/model:** CookingQueueItem{id,householdId,recipeId?,snapshot,positionKey,requestedServings,createdBy}; nema shopping source dok se ne odobri raspoređivanje. schedule(queueItem,slot,targetBase) pravi postojeći nacrt; uklanjanje stavke reda tek u istoj transakciji sa uspešnim odobrenjem. Duplikat recepta je dozvoljen kao odvojena namera.

**Zavisnosti:** G-SYNC, G-PLAN-REV.

**Mali vertikalni koraci:**

1. Dodaj/ukloni i promeni redosled nedatiranih snimaka offline.
2. Izaberi datum/obrok dugmetom; drag je dodatna radnja na širokom ekranu.
3. Pregled zamene postojećeg unosa i atomarno odobrenje+uklanjanje iz reda.

**Merljivi kriterijumi prihvatanja:**

- 10 stavki u redu daje 0 novih shopping sources.
- Odbijen zastareo nacrt ostavlja stavku u redu i postojeći obrok netaknut.
- Obrisani bibliotečki recept ima upotrebljiv snapshot; prazno mesto i zamena imaju različit pregled.

**Konkretne provere u implementaciji (nisu pokrenute):**

- Repository fake backend: schedule rollback i isti operationId dvaput.
- Widget 390/1024 px, tastatura i tekst 2× bez obaveznog drag-a.
- Dva uređaja raspoređuju istu queue stavku: jedna potvrđena operacija, konflikt druge.

### F032 — Pravila po danima (P2)

**Postojeće stanje:** lib/domain/meal_plan.dart: PlanRequest.wishes je slobodan tekst; lib/ai/meal_plan_ai.dart: parseOutline proverava oblik/slotove/recipeId, ne pravila sastojaka ili dana.

**Predloženi ugovor/model:** DayRule{id,weekday,mealType?,predicate,mode=required|preferred,version}; eksplicitni SlotRuleOverride{ruleId,slot,reason}. Deterministički evaluator nad potvrđenim recipe metadata/ingredients vraća pass/fail/unknown sa dokazom. Obavezne alergije ostaju neizuzimljiva ograničenja iz streama A; lokalno dnevno pravilo nije dozvola za njihovo zaobilaženje.

**Zavisnosti:** G-SYNC, G-RULE-METADATA, G-HARD-CONSTRAINTS.

**Mali vertikalni koraci:**

1. Ručno pravilo i evaluator za jedan potvrđen tag/namirnicu.
2. Dodaj pravila u zahtev generatora i validaciju posle AI rezultata; nema rezultata prikazuje razlog.
3. Pregled odstupanja i eksplicitni override samo dnevnog pravila, sa čuvanjem verzije u planu.

**Merljivi kriterijumi prihvatanja:**

- Ponedeljak bez mesa odbija poznat mesni recept i označava neklasifikovan kao Neprovereno.
- Petak riba i <=20 aktivnih minuta se kombinuju; 0 kandidata ne popušta pravilo tiho.
- Override ponedeljka ne važi za sledeći ponedeljak niti menja alergije.

**Konkretne provere u implementaciji (nisu pokrenute):**

- Domain matrica weekday 1..7, mealType wildcard, preferred/required i unknown.
- Fake AI vrati zabranjen recept: pregled pokazuje prekršaj i approve ga odbija bez override-a.
- Offline sačuvano pravilo i RLS dva domaćinstva; regresija parseOutline.

### F033 — Obrok van kuće (P1)

**Postojeće stanje:** lib/domain/meal_plan.dart: SlotProposal uvek bira libraryRecipeId ili draftRecipeKey; PlannedMeal.snapshot null označava legacy zapis, ne obrok van kuće. reconcilePlan preskače unos bez snimka.

**Predloženi ugovor/model:** Proširi postojeći unos diskriminatorom kind=cook|leftover|away, awayReason=restaurant|visiting|skip i opcioni label. Ne koristiti null snapshot kao diskriminator. away zauzima termin, nema sirovinsku potražnju i generator ga čuva dok korisnik izričito ne odabere zamenu.

**Zavisnosti:** G-SYNC, G-PLAN-REV.

**Mali vertikalni koraci:**

1. Migracija kind=cook za postojeće unose i ručni away unos.
2. Prikaži zauzet termin i isključi ga iz regenerableSlots.
3. Pregled cook<->away zamene i reconcile samo razlike.

**Merljivi kriterijumi prihvatanja:**

- Restoran, Kod roditelja i Preskačem daju 0 demand lines i prikazuju zauzet slot.
- Zamena recepta restoranom čuva kupljene/ručne stavke i oslobađa samo neiskorišćene rezervacije.
- Stari nečitljiv snapshot pokazuje Recept nije dostupan, ne Restoran.

**Konkretne provere u implementaciji (nisu pokrenute):**

- Domain exhaustive switch/parser nepoznatog kind-a i legacy fallback.
- Repository zamena sa kupljenih 200 g i rezervisanih 100 g: kupovina opstaje, neiskorišćena rezerva se oslobađa.
- Widget away oznaka, undo i regeneracija koja ga ne prepisuje.

### F034 — Vreme po danu (P1)

**Postojeće stanje:** lib/domain/shopping_source.dart: RecipeSnapshot.prepMinutes je jedina vremenska mera; lib/features/planning/meal_entry_card.dart prikazuje je kao min, bez razlikovanja aktivnog/ukupnog.

**Predloženi ugovor/model:** RecipeTiming{activeMinutes?,elapsedMinutes?,source,confirmedAt}; SlotTimeBudget{slot,maxActiveMinutes?,maxElapsedMinutes?,window?}. Postojeći prepMinutes zadržati kao legacy nespecificirano vreme, ne migrirati automatski u aktivno. Poznato trajanje proverava kod; unknown zahteva proveru pre tvrdog ograničenja.

**Zavisnosti:** G-SYNC, G-PLAN-REV.

**Mali vertikalni koraci:**

1. Potvrđeno aktivno/ukupno vreme i ručni budžet za jedan dan.
2. Evaluator i prikaz poznato/nepoznato u postojećem pregledu.
3. Generator filtrira/rangira uz isti evaluator, bez tihog popuštanja.

**Merljivi kriterijumi prihvatanja:**

- Utorak 20 min: recept 15 aktivno/60 ukupno prolazi aktivni limit; 25/30 ne prolazi.
- Ako postoji i prozor 18:00–18:45, 60 ukupno ne staje, iako aktivni rad prolazi.
- Legacy prepMinutes=15 ne postaje potvrđenih 15 aktivno; nedelja 90 ne menja utorak.

**Konkretne provere u implementaciji (nisu pokrenute):**

- Domain granice 20/21, unknown, nula/negativno, active<=elapsed.
- Fake AI prekršaj i ručna izmena metadata posle početka nacrta invalidiraju evaluaciju.
- Widget dve jasno odvojene mere i offline unos; regresija postojećeg prikaza vremena.

### F050 — Oprema koju posedujem (P2)

**Postojeće stanje:** lib/domain/shopping_source.dart: RecipeSnapshot sadrži sastojke i tekstualne korake, bez strukturisanih resursa; PlanRequest nema opremu.

**Predloženi ugovor/model:** HouseholdEquipment{equipmentType,count,capabilities,confirmedAt}; RecipeEquipmentRequirement{type,count,capability?,alternativeGroup?}. Evaluator required/optional/alternative sa unknown stanjem; ne pretpostavljati da reč rerna u tekstu znači potvrđenu opremu. Snapshot zamrzava odobrene zahteve; bez kontrole uređaja.

**Zavisnosti:** G-SYNC, G-EQUIPMENT-METADATA.

**Mali vertikalni koraci:**

1. Ručno unesi kućnu opremu i zahteve jednog recepta.
2. Objasni nedostajuću opremu i alternative u detalju/pretrazi.
3. Primeni isti evaluator na PlanDraft i sačuvaj potvrđeni izbor alternative.

**Merljivi kriterijumi prihvatanja:**

- Rerna=0 blokira recept koji zahteva rernu; blender opciono ne blokira.
- Alternativa blender OR seckalica prolazi kad postoji jedan odgovarajući resurs; AND zahteva oba.
- Nepoznati zahtevi ne prikazuju Oprema proverena; promena opreme ponovo proverava nacrt.

**Konkretne provere u implementaciji (nisu pokrenute):**

- Domain AND/OR, count 0/1/2, capability temperature nepoznata.
- Repository household izolacija i snapshot nakon izmene biblioteke.
- Widget bez opreme/unknown i pristupačno objašnjenje; nema Bluetooth/API poziva.

### F052 — Paralelna priprema (P3)

**Postojeće stanje:** lib/domain/shopping_source.dart: RecipeSnapshot.steps je List<String>, bez trajanja pojedinačnih koraka/zavisnosti; MealPlan nema raspored resursa. Sam tekst nije dovoljan za pouzdan raspored.

**Predloženi ugovor/model:** CookTask{id,preparationId,dependsOn[],durationMinutes?,attention=active|passive,resources[{type,quantity,capability}],earliest?,latest?}; PreparationSchedule{inputFingerprint,tasks,startTimes,conflicts,confirmedAt?}. Prvo DAG i deterministički bounded list scheduling, ne obećanje optimuma. Aktivni zadaci dele human-attention kapacitet; pasivni korak oslobađa pažnju ali može držati rernu. AI ekstrakcija ide samo u pregled.

**Zavisnosti:** F034, F050, F012, G-TIME.

**Mali vertikalni koraci:**

1. Ručno potvrdi DAG i resurse za dva mala recepta.
2. Izračunaj predlog bez preklapanja i prikaži konflikte/unknown trajanja.
3. Potvrdi raspored i ručno pomeri korak uz revalidaciju zavisnika.

**Merljivi kriterijumi prihvatanja:**

- Dva zadatka rerne po 30 min sa kapacitetom 1 daju najmanje 60 min zauzeća; nema preklapanja.
- Dva aktivna zadatka po 10 min za jednog kuvara daju 20 min; pasivnih 30 može teći uz aktivnih 10.
- Ciklus ili nepoznato trajanje daju nepotpun predlog, bez poruke da je završetak garantovan; promena input-a uklanja staro odobrenje.

**Konkretne provere u implementaciji (nisu pokrenute):**

- Domain topološki red/ciklus, resource interval disjointness, AND preduslovi i deadline nemoguć.
- Unapred izračunat primer A aktivno 10->rerna 30 i B aktivno 10: završetak 40 min sa B tokom rerne.
- Widget potvrda i pomeranje, fake clock; bez pokretanja pametnih uređaja.

### F057 — Ko jede obrok (P2)

**Postojeće stanje:** lib/domain/meal_plan.dart: PlannedMeal.servings podržava broj porcija po unosu; MealPlan.defaultServings je podrazumevana vrednost. Ne postoje prisutni/gosti, niti pouzdan broj članova u ovom modelu.

**Predloženi ugovor/model:** MealAttendance{entryId,memberIds[],guestCount,servingOverrides?,revision}; imena samo potvrđenih članova, gosti kao broj. Predložen broj porcija iz prisutnih uz eksplicitno prihvatanje; ne zaključivati privatne profile drugih članova. Uz F012 attendance menja konzumaciju, a ne automatski prinos već skuvane pripreme.

**Zavisnosti:** G-SYNC, F011, F012.

**Mali vertikalni koraci:**

1. Ručno broj prisutnih i gostiju uz postojeće changeServings.
2. Izbor članova sa household proverom i pregledom novih porcija.
3. Raspodela na novu pripremu/ostatak uz proveru prinosa i stale revision.

**Merljivi kriterijumi prihvatanja:**

- 2 člana +1 gost predlažu 3 porcije; odbacivanje ostavlja stare porcije.
- Promena 2->3 za svežu pripremu sa 200 g za 2 daje 300 g; 0 prisutnih traži skip/away, ne nevažeće 0 servings.
- Dodavanje gosta uz ostatak bez viška označava nedostatak i ne pravi sirovinsku nabavku za već skuvan ostatak.

**Konkretne provere u implementaciji (nisu pokrenute):**

- Domain attendance granice i eksplicitni serving override; bez automatskog čitanja privatnih profila.
- Repository bivši/tuđi član odbijen; konflikt istovremenog attendance i prinosa.
- Widget gosti bez naloga, prikaz ukupno/porcije i regresija changeServings zaštite skuvanog.

### F060 — Pretplata na kalendar (P2)

**Postojeće stanje:** lib/domain/plan_calendar.dart: CivilDate čuva datum bez zone; lib/data/meal_plan_repository.dart: fingerprint je lokalni JSON plan+entries, ne ICS UID/revision; nema feed ugovora u pregledanim planning fajlovima.

**Predloženi ugovor/model:** CalendarSubscription{id,householdId,tokenDigest,selectedPlanIds,fieldPolicy,enabled,createdAt}; odvojeni server read-only feed projektuje potvrđene sinhronizovane obroke. UID=opaque subscriptionId+stable entryId@tavli; SEQUENCE iz monotone eventRevision, ne fingerprint ili vreme poll-a. Podrazumevano celodnevni DATE, DTEND sledeći datum; vremenski događaj samo sa potvrđenim vremenom/zonom. Snimak odobrenog obroka je izvor naziva, ne promenljiv bibliotečki recept.

**Zavisnosti:** G-PLAN-REV, G-FEED, G-TIME.

**Mali vertikalni koraci:**

1. Čista ICS projekcija i fixture serializer sa tačnim datumima/escaping/folding.
2. Autentifikovano kreiranje/rotacija/opoziv linka i scoped feed read sa ograničenim poljima.
3. Probe javnog HTTPS endpoint-a i korisnikovog kalendarskog klijenta; dokumentuj eventualno osvežavanje i tombstone politiku.

**Merljivi kriterijumi prihvatanja:**

- Dva poll-a istog obroka imaju isti UID i SEQUENCE; pomeranje datuma menja SEQUENCE, zadržava UID.
- Rotacija ili opoziv odmah odbija stare linkove na serveru; već preuzete kopije se ne mogu izbrisati sa tuđeg kalendara.
- Srpski UTF-8, zarez, tačka-zarez, kosa crta i newline se bezbedno serijalizuju; redovi najviše 75 okteta uz pravilno folding.
- Feed ne daje sastojke, privatne profile, attendee imena, backend credential ili pravo pisanja; offline nesinhronizovana izmena jasno čeka objavu.

**Konkretne provere u implementaciji (nisu pokrenute):**

- Golden ICS i roundtrip nezavisnim parserom u budućim testovima; DATE 31.12->01.01, DST timed opciono.
- Local server test dva household-a, disabled/rotated/unknown digest, GET bez write efekta, bez URL tokena u logovima.
- Deletion tombstone STATUS:CANCELLED stabilan UID i veći sequence; stvarni Google/Apple klijenti uslovni smoke, ne tvrdnja implementirane integracije.

### F061 — Poređenje nacrta (P2)

**Postojeće stanje:** lib/features/planning/plan_generation.dart: PlanGenerationState ima jedan draft; MealPlanAI.propose ne piše podatke; MealPlanRepository.approve već predstavlja tačku potvrde.

**Predloženi ugovor/model:** PlanScenarioSet{requestSnapshot,baseFingerprint,inventoryFingerprint,priceSnapshotId,timingVersion,candidates[2..3]}; ScenarioMetrics{knownCost?,currency,coverage,activeMinutes?,shoppingTripsAssumptions}. Sve alternative koriste istu zalihu/cene/pravila kao nezavisne simulacije, bez rezervacija. Broj odlazaka nije broj artikala: zahteva eksplicitnu pretpostavku termina/prodavnica; bez nje Nepoznato.

**Zavisnosti:** G-PLAN-REV, G-DEMAND, F034, F018.

**Mali vertikalni koraci:**

1. Dva ručno sastavljena nacrta i isti deterministički kalkulator metrika.
2. Poređenje pokrivenosti i pretpostavki na telefonu/široko; opcioni treći AI nacrt kroz AIRouter.
3. Izaberi jedan i pozovi postojeći approve jednom, ostale odbaci.

**Merljivi kriterijumi prihvatanja:**

- Tri scenarija rezervišu 0 zalihe i stvaraju 0 izvora pre potvrde; posle potvrde samo izabrani postoji.
- Scenariji sa 80% i 100% pokrivenosti cena ne prikazuju nepotpun niži zbir kao dokaz da je jeftiniji.
- Cena 2×100 RSD i 1×150 RSD daje 200 i 150 samo pod istim osnovama; RSD i EUR se ne sabiraju bez potvrđenog kursa.

**Konkretne provere u implementaciji (nisu pokrenute):**

- Pure evaluator identični ulazi=>identične metrike; zaliha 100 g simulirana zasebno po scenariju.
- Repository stale plan/inventory/cene traže novi pregled; dupli confirm operationId stvara jedan plan.
- Fake AI failure zadržava spremne alternative; widget tabovi 2/3 scenarija i unknown vreme/odlasci.

### F062 — Poništi ceo plan (P2)

**Postojeće stanje:** lib/data/meal_plan_repository.dart: approve/_edit/removeMeal rade transakciju i reconcile, fingerprint proverava lokalni plan+entries. Nema istorije agregata; lib/data/database.dart: ShoppingItems.purchaseProvenanceJson čuva poreklo kupovine.

**Predloženi ugovor/model:** PlanOperation{id,planId,householdId,baseRevision,resultRevision,beforeImage,afterImage,undoOf?,status}; undoLatest(expectedRevision) pravi kompenzacionu komandu, ne vraća celu bazu. beforeImage obuhvata plan, entry identitete/snimke, pripreme i veze, pravila/attendance u agregatu. Ponovo izvedi otvorenu potražnju kroz reconcile; kupljene/ručne stavke, potvrđena potrošnja i istorija ostaju činjenice. Ne briši recepte automatski čak i ako ih je approve napravio.

**Zavisnosti:** G-PLAN-REV, G-SYNC, G-DEMAND.

**Mali vertikalni koraci:**

1. Zabeleži before/after jedne zamene unosa u istoj lokalnoj transakciji.
2. Poništi poslednju odobrenu agregatnu izmenu uz pregled razlike i preuskladjivanje potražnje.
3. Proširi pokriće na batch/template/leftover operacije i server CAS/idempotentni replay.

**Merljivi kriterijumi prihvatanja:**

- Potreba 300->400 g, kupljeno 200 i ostava 100: undo na 300 daje 0 preostalo i zadržava kupovinu 200; pri ponovnom povećanju opet 100.
- Tuđa novija izmena ili potvrđeno jedenje/potrošnja posle operacije blokiraju automatsko vraćanje i nude pregled konflikta.
- Retry istog undo operationId ne pravi drugi undo niti novi izvor; revision monotono raste i pri undo-u.

**Konkretne provere u implementaciji (nisu pokrenute):**

- Repository transaction fault između restore i reconcile vraća sve lokalne upise/outbox; istorija kupovine byte-identična.
- Dva uređaja undo expectedRevision=N: jedan uspeva, drugi dobija konflikt bez prepisivanja.
- Domain povezani ostaci ne postaju siročad; promena nedelje obnavlja logički isti izvor bez drugog pokrića.
- Regresije test/data/shopping_repository_test.dart i test/data/meal_plan_repository_test.dart; ne koristiti recipe-version undo kao zamenu.

### F090 — Zauzetost iz kalendara (P3)

**Postojeće stanje:** lib/domain/plan_calendar.dart: CivilDate i PlanRequest nemaju instant intervale; postojeći generation koristi ručne izbore. Nema calendar availability gateway-a u pregledanim planning fajlovima.

**Predloženi ugovor/model:** AvailabilityGateway.probe()->supported|permissionRequired|unavailable i query(window,calendarSelection)->BusySnapshot{intervals[startUtc,endUtc),zoneId,fetchedAt,expiresAt,coverageErrors}; samo zauzetost, bez naslova/opisa/lokacije/ucesnika. Lokalni algoritam oduzima uniju intervala od ručnog prozora, predlaže raspored uz aktivno/ukupno vreme. Provider dozvole ostaju zasebne od ICS bearer linka; ručni prozori ostaju dostupan fallback.

**Zavisnosti:** F034, G-TIME, G-AVAILABILITY.

**Mali vertikalni koraci:**

1. Fake gateway i ručni prozor sa intervalnim algoritmom.
2. Jedan uslovni provider adapter sa najmanjim dokazano dovoljnim freebusy scope-om i eksplicitnim izborom kalendara.
3. Preview predloga, svežina/greške i potvrda novog termina; offline koristi označen cache ili ručni prozor.

**Merljivi kriterijumi prihvatanja:**

- Prozor 17:00–20:00 i busy [18:00,19:00) daju slobodno [17,18) i [19,20); recept 45 min nudi 17:00 ili 19:00, 90 min ne staje.
- Interval koji se završava u 18:00 ne blokira start 18:00; preklopljeni busy intervali se spajaju.
- 403, nepoznata parcijalna greška, denied/unsupported i istekao cache ne znače Slobodno; korisnik vidi Zauzetost nije proverena.
- Nijedan detalj spoljnog događaja ne ulazi u PlanDraft, AI prompt, telemetry ili household sync; potvrda ne piše u spoljni kalendar.

**Konkretne provere u implementaciji (nisu pokrenute):**

- Domain prazni/dupli/prekonoćni intervali, granice, DST u Europe/Belgrade i conversion UTC->lokalni dan.
- Fake adapter delimičan calendar error, revoke, token expiry, stale TTL i offline; isključenje briše cache i prekida refresh.
- Contract fixture samo busy start/end; capability test na svakoj ciljnoj platformi pre javnog obećanja podrške.

## Izvori, tačne verzije i odluke o kodu

Javni repo-i klonirani read-only u `/Users/urosmilutinovic/.cache/tavli-next-sources/B/`; HEAD zaključan dole. Nije pokrenut njihov kod, build, package manager ili install skripta. Web dokumentacija služi samo kao dopuna primarnom kodu. Komercijalni primeri iz IDEAS-90 nisu dokaz implementacije ili licencne dozvole i nisu kopirani.

### https://github.com/cooklang/cookcli

Commit `4e53c8c9c29a5ced2b444b19133cb38a5217c8bb`; licenca `MIT`.

- [crates/core/src/shopping_list/days.rs](https://github.com/cooklang/cookcli/blob/4e53c8c9c29a5ced2b444b19133cb38a5217c8bb/crates/core/src/shopping_list/days.rs) — `DayRange.contains; section_date; kept_ingredients; kept_quantity`: Datumskim filtrom bira indekse sastojaka, a zatim sabira samo odabrane članove grupe; korisno za granice perioda, nije model ostataka.
- [src/util/menu.rs](https://github.com/cooklang/cookcli/blob/4e53c8c9c29a5ced2b444b19133cb38a5217c8bb/src/util/menu.rs) — `load_menu; parse_menu; keep_empty_meals; scaled_quantity`: Rezolvira skalu referenci; posebno vraća prazne obroke za prikaz; API i shopping ih ne koriste.
- [src/server/handlers/menus.rs](https://github.com/cooklang/cookcli/blob/4e53c8c9c29a5ced2b444b19133cb38a5217c8bb/src/server/handlers/menus.rs) — `menu_response`: Odgovor uklanja obroke koji imaju samo beleške/tekst; Tavli away mora ostati eksplicitno zauzet slot.
- [crates/core/LICENSE](https://github.com/cooklang/cookcli/blob/4e53c8c9c29a5ced2b444b19133cb38a5217c8bb/crates/core/LICENSE) — `MIT license grant`: Original copyright Alexey Dubovskoy; puna dozvola i disclaimer kopirani uz fajl. Nema pronađenog NOTICE fajla.

**Odluka:** Kopiran kompletan days.rs i njegova MIT licenca samo kao referenca. Rust i njegove zavisnosti nisu instalirani, izvršeni ili povezani; Tavli CivilDate/demand ostaju osnova sopstvene implementacije.

### https://github.com/mealie-recipes/mealie

Commit `471c7936d3c782a431fd2081b632f404cb3dbb1a`; licenca `AGPL-3.0`.

- [mealie/repos/repository_meal_plan_rules.py](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/repos/repository_meal_plan_rules.py) — `RepositoryMealPlanRules.get_rules`: Spaja konkretan dan/tip i wildcard pravila uz household filter.
- [mealie/routes/households/controller_mealplan.py](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/routes/households/controller_mealplan.py) — `GroupMealplanController._get_random_recipes_from_mealplan`: Pretvara primenljiva pravila u kombinovan filter; za raspon koristi samo globalna pravila.
- [mealie/schema/meal_plan/plan_rules.py](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/schema/meal_plan/plan_rules.py) — `PlanRulesDay; PlanRulesCreate.validate_query_filter_string`: Tipizirani dani/obroci; validacija filtera pre upotrebe.
- [mealie/services/household_services/mealplan_ical_service.py](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/services/household_services/mealplan_ical_service.py) — `MealPlanICalService._event_lines; _fold; _escape_text`: Stabilan UID, revision iz vremena izmene, DATE ekskluzivni kraj, UTF-8 folding i TEXT escaping. Tavli predlaže namenski monotoni revision.
- [mealie/routes/households/controller_mealplan_ical.py](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/routes/households/controller_mealplan_ical.py) — `MealplanICalController.create_ical_token; delete_ical_token`: Rotacija zamenjuje token, opoziv ga uklanja; odvojena javna GET ruta.
- [LICENSE](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/LICENSE) — `GNU Affero GPL v3 text`: AGPL, bez kopiranja bilo kog izvornog fajla u ovaj repo.

**Odluka:** Samo proučeni i citirani arhitektonski obrasci; sopstvena implementacija iz ugovora i standarda, bez AGPL koda.

### https://github.com/kewisch/ical.js

Commit `e6b2e61930d819ff72a7e5b399d52c8b92131106`; licenca `MPL-2.0`.

- [lib/ical/period.js](https://github.com/kewisch/ical.js/blob/e6b2e61930d819ff72a7e5b399d52c8b92131106/lib/ical/period.js) — `Period.fromString; Period.fromData`: Period razdvaja početak/kraj ili trajanje i odbija neispravan slash oblik; koristan signal za strogo parsiranje intervala.
- [LICENSE](https://github.com/kewisch/ical.js/blob/e6b2e61930d819ff72a7e5b399d52c8b92131106/LICENSE) — `MPL-2.0`: MPL je izvan MIT/BSD/Apache izbora ovog prolaza; ništa kopirano.

**Odluka:** Proučavanje tipa perioda; nije odabrana runtime zavisnost niti kopirana implementacija.

### Prikupljeni referentni fajlovi

`research/reference-code/B/cookcli/days.rs` je kompletan neizmenjen upstream modul (128 linija) sa izborom sastojaka po datumu, ne izvod ili pseudokod. Njegove Rust/chrono/cooklang/regex zavisnosti nisu prikupljene i ne predstavlja samostalan executable. `cookcli/LICENSE` je kompletna originalna MIT licenca sa copyright-om. `PROVENANCE.md` objašnjava upotrebu i ograničenja. Nema upstream NOTICE u pregledanom CookCLI stablu. Manifest beleži hash i pinovan URL za oba kopirana fajla. Za ostale funkcije rezultat je obrazac za sopstvenu implementaciju, bez kopiranja AGPL/MPL koda.

## Migracije, kompatibilnost i otvorena pitanja

Legacy snapshots ostaju čitljivi; uvoditi verziju za nove opcione timing/equipment podatke, parsere sa unknown stanjima i migracione fixture-e. Ne pretvarati null legacy snapshot u away, prepMinutes u activeMinutes, isCooked u isEaten, niti servings u izmereni yield. Ne menjati kupljeno poreklo pri backfill-u izvora. Stariji klijent koji ne razume novi entry kind mora dobiti capability/upgrade granicu pre upisa, kako ne bi prepisao leftover kao novi recept. Server command i entity downloader moraju čitati koherentnu committed revision pre prikazivanja zavisnih veza.

Backup/export stream F mora obuhvatiti templates, preparation/consumption veze, operations i revizije, ali nikada calendar/OAuth capability tajne. Stream C je vlasnik stvarne potrošnje/yield/pakovanja; stream D kupovina/household/budžeta; stream A generatora i ograničenja; stream E kuvanja/tajmera. B definiše planerske ugovore i njihove ulazne/izlazne granice.

- Apple/native calendar pristup bez event-content dozvole nije potvrđen; podrška ostaje unavailable dok capability probe i API dokumentacija ne dokažu traženu granicu.
- Google freebusy endpoint/scope je dokumentovan, ali Tavli OAuth konfiguracija, verifikacija aplikacije i platformska podrška nisu testirani.
- Klijentska ICS učestalost osvežavanja, brisanje i cancellation ponašanje Google/Apple moraju se proveriti uslovnim smoke testom; server opoziv ne briše već preuzete podatke.
- Plan fingerprint nije server aggregate CAS; potreban je novi atomski command/revision ugovor, bez pretpostavke da postojeći row outbox već pruža distribuiranu transakciju.
- Prinos, rok/način čuvanja ostataka i trajanja nisu pouzdano poznati iz današnjih string koraka. Ne nuditi automatsku bezbednosnu procenu hrane; korisnik potvrđuje podatke.
- Veličine pakovanja, cene, prisutnost i oprema nedostaju u baseline modelu; metrike i filtri imaju unknown stanje do potvrde.
- Retention za plan operations i tombstones zahteva dogovor pre migracije; početni predlog 90 dana istorije feeda/tombstone-a je produktna odluka, ne interoperabilna garancija.

## Stvarna verifikacija ovog istraživanja

Provereni su JSON sintaksa, obavezni manifest ključevi, tačno 15 dodeljenih ID-jeva bez duplikata, prisustvo svih feature sekcija i byte-identitet/SHA-256 kopiranih fajlova prema pinovanom upstream cache-u. Nisu pokretani Flutter testovi niti upstream softver: aplikacija nije menjana. Opisane funkcionalne provere su budući kriterijumi implementacije, ne rezultati testiranja aplikacije.
