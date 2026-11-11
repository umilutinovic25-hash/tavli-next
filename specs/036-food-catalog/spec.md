# Feature Specification: Katalog namirnica (stalni id namirnice)

**Feature Branch**: `036-food-catalog` (created from latest `main`, dddbc8f)

**Created**: 2026-11-11

**Status**: Draft — clarify završen 2026-11-11

**Input**: Beleške tima (Aleksa) i provera koda: „svaka namirnica ima stalni id, a recepti, Ostava i nabavka čuvaju taj id (tekst je samo prikaz).“

## Kontekst (stanje na `main`, provereno)

- `recipes.ingredientsJson`: `Ingredient{id?, name, quantity, unit, category, note}`. `id` je stabilan samo unutar recepta (veze sa koracima, 027); ne govori koja je to namirnica.
- `pantry_items` i `shopping_items`: `name`, `unit`, `category` kao tekst; nema id namirnice.
- Ledger potražnje (`shopping_contributions`): `ingredientKey` (normalizovan tekst), `unitGroup`, `baseUnit`, `micros`. Ključ pravi `dictionaryIngredientKey(name, version)`: v0 = tekst, v1 = tekst + jedan par (češnjak → beli luk). Verzije su zamrznute (018); `RecipeSnapshot.dictionaryVersion` se beleži pri potvrdi i stari snimci se ne prepisuju.
- Jedinice: `normalizeUnit` pretvara samo g↔kg i ml↔l; kom sa kom; ostalo (kašika, čen…) je uporedivo samo sa istom jedinicom. Nema gustine.
- Raspodela zalihe (`allocateSupply`) već drži jednu zalihu pod dva identiteta (stari i v1) sa jednom zajedničkom količinom.
- Kategorija je na sastojku recepta, Ostavi i stavci nabavke (fiksna lista `ingredientCategories`).
- Alergije postoje samo kao slobodan tekst u preferencijama domaćinstva (`household_preferences.allergiesJson`) i idu samo u AI upit. Namirnice nemaju podatke o alergenima; pretraga (019) kaže „nije provera alergena“.
- AI: `ai_router.dart` izvlači JSON objekat; `Recipe.fromAiJson` proverava naziv i sastojke, kategoriju svodi na „ostalo“. Nema provere jedinica ni opsega (to je 037).
- Sync: entiteti imaju opseg `household` ili `user`; outbox + preuzimanje po (`updated_at`, `id`). RLS: samo vlasnik ili članovi domaćinstva.

## Cilj

Namirnica dobija stalni identitet (`food_id`). Sastojak recepta, zaliha u Ostavi i stavka nabavke čuvaju `food_id`; tekst ostaje ono što je osoba napisala i služi samo za prikaz. Kad je `food_id` poznat, „jaje“, „jaja“ i „jajce“ su ista namirnica kroz recept, plan, Ostavu i nabavku. Kad nije poznat, sve radi kao danas (tekstualni ključ), i to se jasno vidi kao „nepotvrđeno“.

Ništa se ne pogađa po sličnosti teksta: namirnica se prepoznaje samo preko tačnog normalizovanog aliasa ili potvrdom osobe.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Ista namirnica kroz recept, Ostavu i nabavku (Priority: P1)

Recept A traži „jaja“, recept B „jaje“, a u Ostavi stoji „jajce“. Sva tri su potvrđena kao namirnica *jaje*. Pri potvrdi plana potreba za jajima je jedna stavka, a potvrđena zaliha je pokriva jednom.

**Why this priority**: To je cela svrha kataloga; bez toga se ista namirnica kupuje dvaput ili se zaliha ne vidi.

**Independent Test**: Plan sa A i B + zaliha „jajce“, sve sa istim `food_id`; lista za kupovinu ima jednu stavku jaja sa unapred izračunatom količinom (vidi SC-001).

**Acceptance Scenarios**:

1. **Given** sastojci „jaja“ (A) i „jaje“ (B) imaju isti `food_id`, **When** se plan potvrdi, **Then** ledger ima jedan identitet `food:<id>` po izvoru i lista ima jednu stavku „jaje“.
2. **Given** potvrđena zaliha „jajce 2 kom“ sa istim `food_id`, **When** se obračuna potreba, **Then** zaliha pokriva potrebu najviše jednom (ne dvaput po izvoru, ne dvaput po identitetu).
3. **Given** sastojak bez `food_id`, **When** se plan potvrdi, **Then** taj sastojak se obračunava po tekstu kao danas i stavka nosi oznaku „Nepotvrđeno“.
4. **Given** kupljena stavka sa `food_id`, **When** se primi u Ostavu, **Then** zaliha nasleđuje isti `food_id`.

---

### User Story 2 — Potvrda namirnice pri unosu (Priority: P1)

Kad osoba upiše sastojak, Ostavu ili stavku nabavke, aplikacija traži tačan alias u katalogu (zajednički + sopstvene namirnice domaćinstva). Ako ga nađe, `food_id` se upisuje odmah i vidi se naziv namirnice. Ako ne nađe, red ostaje „Nepotvrđeno“; dodir otvara izbor: pretraga kataloga ili „Nova namirnica“ (sopstvena, za ovo domaćinstvo).

**Why this priority**: Bez potvrde nema `food_id`; bez jasne oznake osoba ne zna zašto se nešto ne sabira.

**Independent Test**: Upis „jajce“ dobija `food_id` namirnice *jaje* (alias); upis „zmajevo voće“ ostaje nepotvrđen dok osoba ne izabere ili napravi namirnicu.

**Acceptance Scenarios**:

1. **Given** alias „jajce“ postoji, **When** osoba upiše „Jajce “ (veliko slovo, razmak), **Then** sastojak dobija `food_id` namirnice *jaje*, a tekst ostaje „Jajce“.
2. **Given** nema aliasa, **When** osoba sačuva sastojak, **Then** čuva se bez `food_id` i prikazuje „Nepotvrđeno“; čuvanje nije blokirano.
3. **Given** nepotvrđen sastojak, **When** osoba izabere namirnicu iz kataloga, **Then** upisuje se `food_id`; tekst se ne menja.
4. **Given** nepotvrđen sastojak, **When** osoba izabere „Nova namirnica“ i potvrdi naziv, kategoriju i osnovnu jedinicu, **Then** nastaje sopstvena namirnica domaćinstva (vidljiva samo članovima) i njen alias je upisani tekst.
5. **Given** osoba promeni potvrđenu namirnicu sastojka, **When** sačuva, **Then** nastaje nova verzija recepta (postojeći tok verzija), a snimci već potvrđenih planova se ne menjaju.

---

### User Story 3 — Postojeći podaci i stari snimci (Priority: P1)

Posle nadogradnje postojeći recepti, Ostava i nabavka se mapiraju po tačnom aliasu. Sve što se ne prepozna ostaje nepotvrđeno. Odobreni snimci plana i samostalne nabavke (dictionaryVersion 0 i 1) daju iste količine kao pre.

**Why this priority**: Snimci su zamrznuta istorija (010, 018); promena njihovih količina je regresija.

**Independent Test**: Fiksni skup starih snimaka (v0, v1) daje identične `DemandLine` liste pre i posle 036 (golden test).

**Acceptance Scenarios**:

1. **Given** snimak bez verzije sa „jaja 3 kom“ i „jaje 2 kom“, **When** se ponovo obračuna posle 036, **Then** ostaju dva odvojena identiteta kao pre (v0 pravila).
2. **Given** snimak v1 sa „češnjak 10 g“ i „beli luk 5 g“, **When** se ponovo obračuna, **Then** ostaje jedan identitet `v1:beli luk` sa 15 g.
3. **Given** postojeći recept sa „jaja“, **When** se izvrši migracija, **Then** sastojak dobija `food_id` samo ako „jaja“ tačno odgovara aliasu; tekst i količina se ne menjaju.
4. **Given** nova potvrda plana posle 036, **When** se snimak sačuva, **Then** nosi `dictionaryVersion: 2` i `food_id` po sastojku.

---

### User Story 4 — AI ne piše u katalog (Priority: P2)

Recept iz AI (tekst, slika, URL) prolazi isto prepoznavanje po aliasu. Za neprepoznat sastojak AI može samo da *predloži* sopstvenu namirnicu; ona nastaje tek kad je osoba potvrdi. Pokvaren predlog (prazan naziv, nepoznata kategorija ili osnovna jedinica) se odbija pre baze, a sastojak ostaje nepotvrđen.

**Why this priority**: Zajednički katalog mora ostati čist; ali recept mora i dalje da se sačuva i kad AI pogreši.

**Independent Test**: Lažni AI odgovor sa nepoznatim sastojkom → nema novog reda u `foods`; posle potvrde osobe → jedan sopstveni red sa `household_id` domaćinstva.

**Acceptance Scenarios**:

1. **Given** AI vrati sastojak „jaja“, **When** se recept pregleda, **Then** sastojak je potvrđen po aliasu bez pitanja.
2. **Given** AI vrati nepoznat sastojak sa predlogom namirnice, **When** osoba ne potvrdi, **Then** u katalog se ne upisuje ništa, a sastojak je „Nepotvrđeno“.
3. **Given** AI predlog sa kategorijom van liste ili osnovnom jedinicom van {kom, g, ml}, **When** se obradi, **Then** predlog se odbacuje (nema upisa), recept se i dalje može sačuvati.
4. Ni jedan tok u aplikaciji ne upisuje red sa `household_id = null` (zajednički katalog); to je moguće samo kroz migraciju/seed na serveru.

---

### User Story 5 — Oznake alergena na namirnici (Priority: P3)

Namirnica u katalogu ima oznake alergena iz fiksnog skupa (EU 14). U detalju recepta, za potvrđene sastojke, vidi se „Sadrži: …“. Dok katalog i potvrde nisu potpuni, aplikacija nikad ne tvrdi da je recept „bez alergena“.

**Why this priority**: Korisno, ali zavisi od kataloga i potvrda; pogrešna tvrdnja „bez alergena“ je gora od nikakve.

**Independent Test**: Recept sa potvrđenim *jaje* i *pšenično brašno* prikazuje „Sadrži: jaja, gluten“; recept sa bar jednim nepotvrđenim sastojkom prikazuje i „Podaci o alergenima nisu potpuni.“

**Acceptance Scenarios**:

1. **Given** svi sastojci potvrđeni i bez oznaka, **When** se otvori recept, **Then** ne prikazuje se nikakva tvrdnja o alergenima (ni „bez alergena“).
2. **Given** bar jedan nepotvrđen sastojak, **When** se otvori recept, **Then** uz eventualno „Sadrži: …“ stoji „Podaci o alergenima nisu potpuni.“
3. Oznaka alergena je uvek kod iz kontrolisane tabele; slobodan tekst se ne prihvata (baza to odbija).

### Edge Cases

- Isti alias u zajedničkom katalogu i u sopstvenoj namirnici domaćinstva: alias je jedinstven u okviru vidljivog skupa; sopstveni alias ne sme da zakloni zajednički, pa se pravljenje odbija sa „Ova namirnica već postoji u katalogu.“
- Sopstvena namirnica kasnije dobije zajednički ekvivalent: ostaje sopstvena; spajanje je van opsega (posebna funkcija).
- Brisanje namirnice (sopstvene ili zajedničke) nije deo 036: namirnice se ne brišu, id se nikad ne koristi ponovo, pa `foodId` u receptu nikad ne visi. Sopstvenoj namirnici se mogu menjati samo naziv i kategorija; osnovna jedinica je stalna.
- Osoba pređe u drugo domaćinstvo (034): sopstvene namirnice ostaju u starom; recepti novog domaćinstva koriste svoje.
- Sastojak sa `food_id` čija namirnica nije (još) preuzeta na uređaj: prikazuje se tekst, obračun koristi `food:<id>` (id je dovoljan za sabiranje).
- Ista namirnica u dve neuporedive jedinice (2 kom jaja + 100 g jaja): bez konverzije namirnice ostaju dve stavke (kao danas po grupi jedinica).
- Imam/nemam (Q1): sastojak potvrđene namirnice u jedinici bez konverzije (kašika soli, prstohvat bibera) nikad se ne oduzima brojčano; ide na proveru kao danas nepoznata količina.
- Količina nepoznata: kao danas, grupa `unknown`, ide na proveru.
- Stariji klijent bez 036: ignoriše `foodId` u JSON-u i `food_id` kolone; obračunava novi (v2) snimak po tekstu. Mešovite verzije zahtevaju koordinisano ažuriranje (isto upozorenje kao 018).

## Requirements *(mandatory)*

### Functional Requirements

**Katalog**

- **FR-001**: Tabela `foods`: `id` (stalan, nikad se ne menja ni ne koristi ponovo), `name` (nominativ jednine, prikaz), `category` (iz `ingredientCategories`), `base_unit` ∈ {kom, g, ml}, `household_id` (null = zajednički katalog, inače sopstvena namirnica domaćinstva), uobičajene kolone za sync (`created_at`, `updated_at`, `updated_by`).
- **FR-002**: Tabela `food_aliases`: `food_id`, `alias` (normalizovan istim pravilom kao `ingredientKey`: trim, mala slova, jedan razmak), `household_id` kao kod namirnice. Alias je jedinstven u okviru zajedničkog kataloga; u okviru domaćinstva ne sme da se poklopi ni sa zajedničkim ni sa drugim sopstvenim aliasom. Naziv namirnice je uvek i njen alias.
- **FR-003**: Konverzije po namirnici `food_conversions`: `food_id`, `unit` (npr. čen, kašika, glavica), `factor_micros` u osnovnoj jedinici namirnice (čen = 5 g). Gustina ml↔g postoji u šemi (konverzija `ml`→g), ali seed je ne puni u 036 (Q1).
- **FR-004**: Alergeni: kontrolisana tabela `allergens` (kod, naziv na srpskom) sa fiksnim skupom EU 14 (Q4; korisnik ne dodaje kodove, sopstvenoj namirnici bira oznake iz liste) i veza `food_allergens(food_id, allergen_code)` sa stranim ključem na kod. Slobodan tekst nije moguć.
- **FR-005**: Zajednički deo kataloga (`household_id is null`) menja se samo migracijama/seed-om na serveru; `authenticated` ga sme samo čitati. Sopstvene namirnice, aliasi i konverzije domaćinstva: čitaju i pišu samo članovi (isti `private.is_member`).

**Čuvanje id-ja**

- **FR-006**: `Ingredient` dobija opciono `foodId`; `name` ostaje originalni tekst osobe/AI i ne prepisuje se nazivom namirnice. `toJson` piše `foodId` samo kad postoji (stari JSON ostaje bajt-isti za nepotvrđene sastojke).
- **FR-007**: `pantry_items` i `shopping_items` dobijaju `food_id` (nullable) lokalno (drift, `schemaVersion` 16 → 17, migracija) i na serveru (migracija + sync mapiranje u `entities.dart`). Prijem kupljene stavke u Ostavu prenosi `food_id`.
- **FR-008**: Prepoznavanje: tačno poklapanje normalizovanog teksta sa aliasom iz zajedničkog kataloga ili sopstvenih namirnica aktivnog domaćinstva. Bez približnog poklapanja, bez AI pogađanja.

**Obračun (nadogradnja 018, ne paralelni sistem)**

- **FR-009**: Nova verzija rečnika **v2**: identitet sastojka sa `foodId` je `food:<foodId>`; bez `foodId` je v1 tekstualni ključ (`v1:<tekst>`, isti par češnjak → beli luk). `dictionaryIngredientKey` v0 i v1 ostaju nepromenjeni.
- **FR-010**: Nova potvrda plana/samostalne nabavke beleži `dictionaryVersion: 2` i `foodId` po sastojku u snimku (`withCurrentDictionary`). Stari snimci (0, 1) se ne prepisuju i obračunavaju po svojim pravilima.
- **FR-011**: Ledger (`shopping_contributions.ingredient_key`) i dalje je tekst; za v2 nosi `food:<id>`. Nema nove kolone u ledgeru.
- **FR-012**: Raspodela zalihe: zaliha sa `food_id` dobija i identitet `food:<id>`, uz postojeće (tekst, v1); jedna fizička količina pokriva najviše jednom bez obzira kroz koliko identiteta je viđena (proširenje postojećeg `canonicalId`/`samePhysicalAs` modela).
- **FR-013**: Grupa jedinica u v2: g↔kg, ml↔l, kom↔kom kao danas; konverzije namirnice (čen → g) važe samo u v2 i samo za potvrđene sastojke. Jedinica bez konverzije ostaje sopstvena grupa (imam/nemam, Q1).

**UI i AI**

- **FR-014**: Red sastojka/zalihe/stavke bez `food_id` prikazuje oznaku „Nepotvrđeno“; dodir otvara izbor namirnice (pretraga po aliasima) i „Nova namirnica“. Čuvanje nikad nije blokirano zbog nepotvrđenog reda.
- **FR-015**: AI tok (`fromAiJson` i pregled recepta) primenjuje FR-008. AI predlog nove namirnice je samo predlog u memoriji; upis u `foods` ide isključivo posle potvrde osobe i uvek sa `household_id` aktivnog domaćinstva. Predlog koji ne prolazi proveru (naziv prazan, kategorija van liste, osnovna jedinica van {kom, g, ml}) odbacuje se pre baze.
- **FR-016**: Prikaz alergena po FR-004 i US5; nijedan ekran ne tvrdi „bez alergena“. Postojeće slobodne alergije u preferencijama ostaju kako jesu; povezivanje je van 036 (Q4).
- **FR-017**: Katalog (zajednički + sopstveni) dostupan je offline posle prvog preuzimanja: zajednički deo se preuzima ceo (< 1 MB) po `updated_at`, kao novi opseg samo za čitanje; sopstveni deo ide kao podaci domaćinstva kroz outbox (Q5).
- **FR-018**: Potroši prvo (014), provera Ostave u receptu (030) i „Dodaj u kupovinu“ porede po namirnici kad obe strane imaju `foodId`, inače po tekstu kao danas.
- **FR-019**: Lični izvoz podataka sadrži sopstvene namirnice domaćinstva (aliasi, konverzije, alergeni), bez zajedničkog kataloga.

### Key Entities

- **Food** — namirnica: stalni id, naziv, kategorija, osnovna jedinica, vlasnik (zajednički ili domaćinstvo).
- **FoodAlias** — normalizovan tekst → namirnica; jedinstven u vidljivom skupu.
- **FoodConversion** — jedinica → faktor u osnovnoj jedinici namirnice (uključujući gustinu).
- **Allergen / FoodAllergen** — fiksan skup kodova i oznake namirnice.
- **Ingredient / PantryItem / ShoppingItem** — postojeći, + opcioni `foodId`; tekst ostaje.
- **RecipeSnapshot** — postojeći, `dictionaryVersion: 2` + `foodId` po sastojku.

### New UI copy (srpski, latinica)

- „Nepotvrđeno“
- „Izaberi namirnicu“
- „Pretraži namirnice“
- „Nova namirnica“
- „Naziv namirnice“, „Kategorija“, „Osnovna jedinica“ (kom / g / ml)
- „Sačuvaj kao moju namirnicu“
- „Ova namirnica već postoji u katalogu.“
- „AI predlaže novu namirnicu: „…“.“ / „Potvrdi“ / „Odbaci“
- „Sadrži: …“
- „Podaci o alergenima nisu potpuni.“

## Success Criteria *(mandatory)*

### Measurable Outcomes (unapred izračunati slučajevi)

- **SC-001 (jaje kroz ceo tok)**: Recept A (4 porcije): „jaja 3 kom“; recept B (2 porcije): „jaje 2 kom“; oba u planu za 2 porcije. Ostava: „jajce 2 kom“, potvrđeno. Sva tri sa `food_id` *jaje*.
  - Potreba: A 3 × 2/4 = 1,5 kom; B 2 × 2/2 = 2 kom; ukupno **3,5 kom** (3 500 000 micros), identitet `food:<jaje>`.
  - Zaliha pokriva 2 kom → lista za kupovinu: **jedna stavka „jaje“, 1,5 kom**.
  - Kontrola (isti podaci bez `food_id`, v1 pravila): tri različita ključa, zaliha ne pokriva ništa → dve stavke (1,5 kom „jaja“ i 2 kom „jaje“). Test mora pokazati obe varijante.
- **SC-002 (stari snimci)**: Golden skup snimaka v0 i v1 (uključujući „češnjak 10 g“ + „beli luk 5 g“ → v1 = 15 g, v0 = 10 g + 5 g odvojeno) daje identične `DemandLine` liste i `ShoppingNeed` zbirove pre i posle 036.
- **SC-003 (migracija)**: Posle migracije nijedan postojeći `name`, `quantity`, `unit` u receptima, Ostavi i nabavci nije promenjen; `food_id` je postavljen samo gde je tekst tačan alias; ostali redovi su `null`.
- **SC-004 (katalog čist)**: Ni jedan klijentski tok ne može upisati red u `foods`/`food_aliases` sa `household_id = null` (pgTAP test sa dva naloga: insert/update zajedničkog reda odbijen; sopstveni red drugog domaćinstva nevidljiv).
- **SC-005 (AI)**: Lažni AI odgovor sa nepoznatim sastojkom i pokvarenim predlogom ne menja broj redova u `foods`; recept se i dalje može sačuvati.
- **SC-006**: `scripts/check.sh` čist; testovi domena pisani prvi (TDD); `flutter test` zelen; `supabase test db` zelen.

## Assumptions

- **Ustav II (RLS)**: zajednički katalog je čitljiv svim prijavljenim korisnicima, što nije „vlasnik ili član domaćinstva“. Potrebna je izmena ustava (MINOR: izuzetak za referentne podatke bez ličnih podataka, samo `select` za `authenticated`, bez upisa) — predlaže se u planu, pre implementacije.
- `food_id` zajedničkih namirnica je tekstualni id koji pravi seed (npr. `f_jaje`) ili uuid; sopstvene namirnice dobijaju id sa uređaja (kao ostali zapisi). Odluka u planu.
- Kategorija se na namirnici prikazuje kao predlog; postojeća kategorija na sastojku/zalihi/stavci ostaje i dalje se čuva (bez brisanja kolona), da stariji klijenti i snimci rade.
- Ništa se ne briše iz postojeće šeme; sve promene su dodavanje kolona/tabela.
- Nema novih zavisnosti.

## Izvan opsega (posebne spec/zadaci)

- 037 AI ugovor: jedna šema odgovora, stroga validacija (opseg, jedinice, kategorije, `food_id`), ponavljanje pri grešci.
- Cloudflare Worker / Edge Function za ključeve.
- timestamp → date migracija za datume bez vremena.
- Home „Danas“, kuvari kao tab u Receptima.
- Istraživanje: javni API za cene u Srbiji, prosečna korpa, Windows build, pgvector.
- Ispravka zastarelih Status redova u 010, 034, 022.
- Spajanje sopstvene namirnice sa zajedničkom; uređivanje zajedničkog kataloga iz aplikacije.

## Clarifications

### Session 2026-11-11

- Q1: Količina ili imam/nemam? → Hibrid. Meri se samo uporedivo (g↔kg, ml↔l, kom); konverzije po namirnici (čen = 5 g) ulaze u 036 samo za potvrđene sastojke u v2; gustina ml↔g postoji u šemi, bez podataka; začini/so/ulje u kašikama ili prstohvatu su imam/nemam i ne oduzimaju se brojčano.
- Q2: Početni zajednički katalog? → Seed iz rečnika 018 i najčešćih sastojaka postojećih recepata, ~150–250 ručno pregledanih namirnica; održava tim isključivo kroz migracije uz PR pregled; bez uvoza iz otvorenog izvora.
- Q3: Migracija? → Jednokratno mapiranje po tačnom aliasu (lokalno i server); neprepoznato ostaje „Nepotvrđeno“ bez upita; snimci v0/v1 netaknuti, nova potvrda v2; promena namirnice u receptu pravi novu verziju recepta.
- Q4: Alergeni? → Fiksnih EU 14 sa srpskim nazivima; korisnik ne dodaje kodove, bira iz liste za sopstvenu namirnicu; nikad „bez alergena“; povezivanje sa slobodnim alergijama iz preferencija van 036.
- Q5: Sync kataloga? → Ceo zajednički katalog na uređaju (< 1 MB), osvežavanje po `updated_at` posle prijave i pri svakom sync-u, kao opseg samo za čitanje; sopstvene namirnice kao podaci domaćinstva kroz outbox.
- Alias: sopstveni ne sme da zakloni zajednički („Ova namirnica već postoji u katalogu.“).
- Analiza C1: Potroši prvo, provera Ostave i „Dodaj u kupovinu“ ulaze u 036 (FR-018).
- Analiza G1: lični izvoz sadrži sopstvene namirnice (FR-019).
