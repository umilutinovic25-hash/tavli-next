# Ugovori za integraciju šest radnih paketa

Status: predloženi ugovori za naredne implementacione specifikacije. Nijedna tabela/API migracija ovde nije izvršena. Ovaj dokument razrešava preklapanja istraživačkih predloga; nazivi gate-ova u izveštajima su lokalni alias-i, ne šest različitih sistema.

## Kanonske granice

| Granica | Vlasnik ugovora | Odluka za dalji rad |
|---|---|---|
| Recipe format/version/evidence | F uz A/E | Jedan verzionisan serializer za Recipe i RecipeSnapshot. Stabilni ingredient/step ID-jevi; legacy adapter, bez slučajnih ID-jeva pri svakom čitanju. |
| Ograničenja/pretraga | A uz B | Tipizovana hard ograničenja, trovalentno known/unknown/violated. Preferencija i glasanje ne nadjačavaju hard pravilo. |
| Plan/command revision | B uz D | Jedan plan command sa operationId i expectedRevision. Lokalni fingerprint ne predstavlja server atomarnost; budući server CAS/RPC zasebna vertikala. |
| Fizička zaliha/potražnja | C uz B/D | Postojeći demand/allocation core ostaje računski autoritet. Pantry lot je projekcija kapaciteta; transakcija je idempotentna, istorija kupovine se ne prepisuje. |
| Priprema/jedenje | B uz C/E | Preparation jednom stvara potrebu za sirovinama; Consumption deli gotov prinos. Cooked, eaten, wasted i frozen su različiti potvrđeni događaji. |
| Cooking session | E uz F | Lični tok i napredak čuvaju zamrznut sadržaj; završetak plana je zasebna potvrđena household komanda. Pruning RecipeVersions ne sme obrisati dokaz cook log-a. |
| Account/household scope | D uz F | Jedan aktivni AccountScope; promena scope-a zatvara stare sesije/tokove i invalidira nacrte/pretragu. Privatni lični podaci ne prelaze u shared payload. |
| Novac/ponude | D uz C | Integer minor-unit + currency. Sum allocations = total; uslovi popusta su izvršivi predikati, ne marketinška oznaka. |
| Spoljni adapteri | Vlasnik oblasti | Capability probe + typed error + datirana evidencija i ručni fallback. Dostupnost Open Prices nije dokaz robe na stanju. |
| Hardware komande | E | Device write nije retry-outbox. Potvrda, kratak rok, command ID i readback; nikad automatski stari preheat posle povratka mreže. |
| Arhive/deljenje | F uz D | Recept JSON nije puna arhiva naloga. Restore ima dry-run, manifest/hash, policy za ID-remap i tombstone; opoziv deljenog linka važi za budući pristup. |
| Kalendar | B | Izlaz F060 i ulaz F090 imaju odvojene dozvole. Free/busy ne zahteva naslove/opise privatnih događaja i ne šalje se modelu. |

## Normalizacija gate-ova

G0–G6 iz glavnog plana su kontrolne tačke isporuke. Lokalni detaljni gate-ovi se grupišu ovako:

- **Baseline/kvalitet:** `G010` → G0/G5; dovršiti realno stanje 010 bez prepisivanja njene istorije.
- **AI/server:** `G-SERVER`, `G-AI`, `G-RULES`, `G-HARD-CONSTRAINTS`, `G-PLAN-CONSTRAINTS`, `G-RULE-METADATA`, `G-PLANNER`, `G-PROVENANCE` → G1, uz kanonski recipe/constraint ugovor.
- **Količine i stanje:** `GQ`, `GTX`, `G-DEMAND`, `G-PANTRY`, `G-PACKAGE-CATALOG`, `G-PLAN-REV` → G2/G3/G4; jedan registar operacija i deterministički račun, ne novi sistemi po stream-u.
- **Schema/sync:** `G-SYNC`, `G-SCHEMA`, `G-ASSETS`, `G-FORMAT-COORDINATION`, `G-STEP` → G3/G4, sa tačno jednom dogovorenom šemom i integratorom migracija.
- **Adapteri/capability:** `GADAPTER`, `G-CAPABILITY`, `G-DEVICE`, `G-ACAIA-LICENSE`, `G-OVEN-API`, `G-SPEECH`, `G-FEED`, `G-AVAILABILITY`, `GSHARE` → capability preflight po integraciji, G3/G5/G6 za prava/dokaze.
- **Vreme/sadržaj/oprema:** `G-TIME`, `G-LIFECYCLE`, `G-CONTENT`, `G-EQUIPMENT-METADATA` → odgovarajući čisti ugovor i G5 proveru; nisu zavisnost od završetka svih 90 funkcija.
- **Prenosivost i izvori podataka:** `G-PORTABLE` → verzionisan read-only snapshot/staging/cleanup ugovor pre export/restore tokova; `G-DATA-LICENSE` → G6 provera tačnog dataset izdanja, atribucije i dozvoljene upotrebe, odvojeno od licence parsera.

Ako kasniji izveštaj uvede novi alias, prvo ga mapirati u ovaj dokument. Feature dependency DAG se sklapa iz eksplicitnih Fnnn zavisnosti; uslovni provider/hardware gate ostaje otvorena sposobnost, ne automatski završen zadatak.

## Pravilo sekvencijalnog rada

1. Pre implementacije zajedničke promene dopuniti mali ADR: izabrani model, stari format, migracija, konflikt i plan povratka.
2. Jedan vlasnik dodaje novu SQL migraciju, Drift schema bump i regenerated fajl. Drugi rade svoje UI/domain adaptere tek na stabilnom ugovoru.
3. Nova funkcija prvo ima ograničen kraj-do-kraja slučaj sa fake adapterom, zatim proveru greške/retry/offline, pa vizuelno doterivanje.
4. Nema stapanja vlasničkog/commercial source koda u runtime; reference-only permisivni fajl traži odluku o portovanju/zavisnosti pre korišćenja.

## Obavezne referentne računice

- Potreba 600 g, potvrđena zaliha 400 g → kupi 200 g. Drugi obrok ne dobija istih 400 g ponovo.
- Potreba 750 g, pakovanje 500 g → 2 pakovanja, višak 250 g; kupovina 1000 g nije isto što i potrošnja 750 g.
- Priprema 6 porcija, konzumacija 4+2 → sirovine za 6, bez nove nabavke za preostale 2.
- Trošak 100 najmanjih jedinica valute, tri jednaka korisnika → deterministička raspodela 34+33+33, zbir 100.
- Posuda 180 g, ukupno 680 g → 500 g neto. Neto se ne potvrđuje ako bruto < tara.
- Kalup istog oblika/visine prečnika 20 → 24 cm → faktor površine 1.44; vreme pečenja nije automatski isti faktor.
- Brašno 1000 g i voda 650 g → 65% hidratacije pre drugih sastojaka; starter računati samo uz poznat sastav.

Ovo su očekivani test rezultati, ne tvrdnja da su te nove funkcije već implementirane.
