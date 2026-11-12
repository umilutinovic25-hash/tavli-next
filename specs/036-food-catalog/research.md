# Research: 036 Katalog namirnica

Odluke za plan. Svaka: odluka → razlog → odbačene alternative.

## R1. Identitet u obračunu: rečnik v2, ne nov ledger

**Odluka**: `dictionaryIngredientKey(name, 2, foodId:)` vraća `food:<foodId>` kad sastojak ima `foodId`, inače isti ključ kao v1 (`v1:<tekst>`). `shopping_contributions.ingredient_key` ostaje tekst. v0 i v1 se ne diraju.

**Razlog**: 018 je već uveo verzionisan identitet zamrznut u snimku i raspodelu koja jednu zalihu vidi pod više identiteta. v2 je treći identitet istog mehanizma; ledger, outbox i server šema ledgera ostaju isti.

**Odbačeno**: nova kolona `food_id` u ledgeru (dupli izvor istine pored `ingredient_key`); prepisivanje starih snimaka na v2 (krši 010/018).

## R2. Snimak v2 zamrzava i konverziju

**Odluka**: pri potvrdi (`withCurrentDictionary`) sastojak sa `foodId` i jedinicom koju pokriva konverzija namirnice zamrzava se u snimku kao `conversions["<foodId>|<jedinica>"] = {factorMicros, baseUnit}` (nivo snimka, ne polje sastojka). Ponovni obračun v2 snimka koristi zamrznutu konverziju, nikad trenutni katalog.

**Razlog**: zajednički katalog se ispravlja migracijama (npr. čen 5 g → 4 g). Odobren snimak ne sme da promeni količinu kad se katalog promeni — isto pravilo kao zamrznut rečnik.

**Odbačeno**: čitanje konverzije iz kataloga pri svakom obračunu (snimak više nije zamrznut); verzionisanje celog kataloga (preteško za 036).

## R3. Faktor konverzije u milionitim delovima

**Odluka**: `factor_micros` (bigint) = koliko milionitih delova osnovne jedinice je 1 jedinica (čen = 5 g → `factor_micros = 5 000 000`). Obračun: `toMicros(q) * factorMicros ~/ 1 000 000` sa zaokruživanjem na pola naviše (isto kao `_scale`).

**Razlog**: postojeći `normalizeUnit` ima celobrojni `factor` (kg = 1000) i ne može da izrazi 2,5 g po kašičici. Micros su već jedinica preciznosti ledgera.

## R4. Imam/nemam bez novog mehanizma

**Odluka**: jedinica bez konverzije (kašika, prstohvat) ostaje sopstvena grupa (`unit:kašika`), kao danas. Takva potreba se pokriva samo zalihom iste grupe ili postojećom potvrdom „imam celu stavku“ (`confirmedWhole`). Nema novog stanja.

**Razlog**: ponašanje već postoji i testirano je; Q1 traži samo da se začini ne oduzimaju brojčano preko neuporedivih jedinica.

## R5. Raspodela zalihe: treći identitet

**Odluka**: `Supply` dobija `foodIngredient` i `foodUnitGroup` (iz `food_id` zalihe i trenutne konverzije namirnice — zaliha je živo stanje, ne snimak). `allocateSupply` prihvata poklapanje po legacy, v1 ili food identitetu; kapacitet je i dalje po `canonicalId`, pa se jedna fizička količina troši najviše jednom.

## R5a. Pravilo para (dopuna posle T019)

**Odluka**: dva zapisa su isti sastojak po namirnici samo kad oba imaju `foodId`; inače po tekstu (`sameIngredient`, `supplyCovers`). Važi u planu, nabavci, Potroši prvo i proveri „imam“.

**Razlog**: recept dobija `foodId` automatski, a red Ostave koji nije mapiran (lokalna izmena na čekanju, tekst bez aliasa) bi inače izgubio pokriće koje danas ima.

## R6. Prepoznavanje: tačan alias, pri upisu

**Odluka**: čista funkcija `matchFood(text, aliases)` (normalizacija = `ingredientKey`). Repozitorijumi (recept, Ostava, nabavka) pri upisu popunjavaju `foodId` samo kad je `null`; nikad ne prepisuju izbor osobe. Redosled: zajednički alias, pa sopstveni (sopstveni ne sme da zakloni zajednički — R8).

**Odbačeno**: približno poklapanje (Levenshtein, stemovanje) — spec zabranjuje; AI prepoznavanje — 037.

## R7. Migracija postojećih podataka: na serveru

**Odluka**: jednokratno mapiranje radi serverska migracija (`recipes.ingredients` jsonb, `pantry_items`, `shopping_items`) po tačnom aliasu zajedničkog kataloga. Trigger `touch_updated_at` podiže `updated_at`, pa uređaji dobijaju mapirane redove kroz postojeće preuzimanje. Lokalna drift migracija samo dodaje tabele i kolone, bez lokalnog mapiranja.

**Razlog**: server je trajna kopija (ustav II); lokalno mapiranje bi pravilo hiljade outbox upisa i trke među članovima. Red sa lokalnom izmenom na čekanju preuzimanje preskače (postojeće pravilo) — taj red ostaje nepotvrđen dok ga osoba ne potvrdi (Q3 to dozvoljava).

`recipe_versions` i snimci (`shopping_sources`) se ne menjaju — istorija.

## R8. Jedinstvenost aliasa

**Odluka**: `food_aliases.alias` = normalizovan tekst (check u bazi: `alias = lower(btrim(regexp_replace(alias, '\s+', ' ', 'g')))`). Jedinstveni indeksi: `(alias) where household_id is null` i `(household_id, alias) where household_id is not null`. Trigger `before insert` odbija sopstveni alias koji postoji u zajedničkom katalogu. Seed migracija koja doda zajednički alias koji već postoji kao sopstveni: lookup daje prednost zajedničkom (sopstveni ostaje, ali je u senci); generator seed-a to prijavljuje kao upozorenje.

## R9. Zajednički katalog i ustav II

**Odluka**: izmena ustava 2.0.1 → 2.1.0 (MINOR): „Referentni podaci bez ličnih podataka (zajednički katalog namirnica, kodovi alergena) MOGU biti čitljivi svakom `authenticated` korisniku; nijedna klijentska uloga ih ne sme menjati; menjaju se samo migracijama.“ RLS: `select using (household_id is null or private.is_member(household_id))`; `insert/update with check (household_id is not null and private.is_member(household_id))`.

Prvi zadatak u tasks.md, zaseban commit, pre bilo koje migracije.

## R10. Sync kataloga

**Odluka**: četiri nova entiteta u `syncEntities` (`food`, `food_alias`, `food_conversion`, `food_allergen`), opseg `household`, `scopeColumn = householdId` (null za zajedničke). `fetchSince` je već ograničen RLS-om, pa isti `_pull` donosi i zajedničke i sopstvene redove. Nema novog opsega u kodu.

Veličina: ~250 namirnica × ~4 aliasa ≈ 1 000 redova aliasa + ~250 + konverzije + alergeni; < 1 MB, jedna do tri strane od 500.

**Za proveru u implementaciji**: brisanje keša pri promeni domaćinstva (034) i `LegacyMover` ne smeju da obrišu ili premeste redove sa `household_id = null`; test za oba.

## R11. Alergeni

**Odluka**: serverska tabela `allergens(code, name_sr)` sa 14 redova (EU Uredba 1169/2011, Prilog II), samo `select`. U Dartu `const euAllergens` sa istim kodovima i srpskim nazivima (bez lokalne tabele — fiksno je). `food_allergens(food_id, allergen_code → allergens.code)`. Test u Dartu i pgTAP test proveravaju istih 14 kodova.

Kodovi: `gluten, crustaceans, eggs, fish, peanuts, soy, milk, nuts, celery, mustard, sesame, sulphites, lupin, molluscs`.
Prikaz: gluten, rakovi, jaja, riba, kikiriki, soja, mleko, orašasti plodovi, celer, slačica, susam, sulfiti, lupina, mekušci.

## R12. Seed

**Odluka**: izvor je pregledan CSV `supabase/catalog/foods.csv` (id, naziv, kategorija, osnovna jedinica, aliasi `|`, konverzije `čen=5000000|…`, alergeni `eggs|…`). `scripts/catalog_seed.dart` generiše SQL migraciju (idempotentni `insert … on conflict do nothing`). Polazni spisak: rečnik 018 + jedinice/sastojci iz `prompts.dart` + ručni spisak tima; ~150–250 redova. Id zajedničke namirnice je čitljiv slug (`f_jaje`), nikad se ne menja ni ne koristi ponovo. Sopstvene namirnice: UUID sa uređaja.

Napomena: „najčešći sastojci postojećih recepata“ se ne čitaju iz produkcije (lični podaci); tim sastavlja spisak ručno.

## R13. AI bez upisa u katalog (bez izmene prompta)

**Odluka**: 036 ne menja prompt ni `fromAiJson` (to je 037). Za nepotvrđen sastojak recepta iz AI izvora forma nudi „AI predlaže novu namirnicu: „…“.“ — predlog je AI-jev naziv, kategorija i osnovna jedinica izvedena iz jedinice (g/kg → g, ml/l → ml, kom → kom, inače bez predloga). „Potvrdi“ otvara popunjenu formu „Nova namirnica“; upis ide kroz `FoodDraft.validate` → `FoodRepository.createOwn` (uvek `household_id` aktivnog domaćinstva). Pokvaren predlog se ne nudi.

## R14. Prikaz naziva u nabavci

**Odluka**: stavka nabavke iz identiteta `food:<id>` prikazuje naziv namirnice (npr. „jaje“) kad je namirnica na uređaju, inače tekst prvog izvora (kao danas). Sastojak u receptu uvek prikazuje originalni tekst.
