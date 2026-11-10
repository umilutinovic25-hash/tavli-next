# Tavli Next — kompletan plan realizacije

Status: planiranje i istraživanje. Implementacija novih funkcija nije započeta ovim paketom. Originalni backlog `specs/010-plan-and-shopping/tasks.md` nije prepisan niti proglašen završenim.

## Cilj

Nadograditi originalni Tavli kroz 90 numerisanih predloga, bez paralelnog sistema recepata, zaliha ili sinhronizacije. Svaka implementacija je mala proverljiva vertikala, sa korisničkim ishodom i testovima. Eksterni servisi i uređaji su uslovne integracije, ne garantovana podrška.

## Izvori istine

1. `ARCHITECTURE.md`: zajedničke granice i invarijante.
2. `research/feature-register.json`: tačno 90 ID-jeva, vlasnik i pošten status.
3. `research/manifests/{A..F}.json`: dokazi iz koda, zavisnosti, acceptance i male scope slices.
4. `research/streams/{A..F}.md`: detaljno obrazloženje i implementacioni redosled po oblasti.
5. `tasks/todo.md`: indeks za dalji rad; nije zamena za detaljnu specifikaciju i plan pojedinačne funkcije.
6. `tasks/FEATURE-PLAN.md`: objedinjeni detalji svih 90 funkcija i 273 predložene male vertikalne celine; izvor su stream manifesti.

## Šest paralelnih chatova

| Chat | Oblast | ID-jevi |
|---|---|---|
| A | AI, pretraga, unos i izvori | F001 F002 F003 F004 F005 F019 F020 F024 F025 F026 F030 F035 F048 F058 F089 |
| B | Planiranje i kalendar | F007 F012 F014 F015 F031 F032 F033 F034 F050 F052 F057 F060 F061 F062 F090 |
| C | Ostava, količine i računi | F006 F013 F017 F036 F037 F038 F039 F040 F042 F072 F073 F074 F075 F083 F087 |
| D | Nabavka, domaćinstva i trgovci | F010 F011 F018 F041 F043 F044 F045 F056 F063 F066 F067 F068 F069 F070 F071 |
| E | Kuvanje, edukacija i uređaji | F008 F009 F016 F028 F029 F047 F051 F053 F054 F055 F076 F077 F078 F081 F082 |
| F | Prenosivost, podaci i kvalitet | F021 F022 F023 F027 F046 F049 F059 F064 F065 F079 F080 F084 F085 F086 F088 |

Svaki chat sada piše isključivo svoj izveštaj, manifest i svoj reference-code direktorijum. Root objedinjavanjem proverava svih 90 i pravi jednu dokumentacionu granu/PR. Nema konkurentnih promena `providers.dart`, baze, routera ili migracija.

## Faza 0 — integracioni preduslovi (G0–G6)

- **G0 Baseline:** zabeležiti commit, stvarno stanje 010 i postojeće funkcije. Acceptance: root source/test/migration fajlovi identični baseline-u u ovom planerskom paketu. Provera: `git diff <baseline> -- lib test supabase android ios macos pubspec.yaml pubspec.lock`.
- **G1 AI boundary:** zatvoriti gubitak ograničenja između podkoraka, definisati typed constraints, gateway auth, budžet i otkazivanje. Razdvojiti na parser/prompt propagaciju, kontrolu deadline-a, transport gateway i build-key migraciju; svaka ima poseban scenario i commit.
- **G2 Identity/quantities:** ugovor ingredient ID/alias, dimenzije i fixed-point; granica recipe/demand/supply/receipt. Acceptance: unapred izračunat slučaj 600 g potrebe − 400 g potvrđene zalihe = 200 g manjka, bez dvostrukog trošenja pri dve potražnje.
- **G3 Account/sync:** scope switch, registry/cleanup i stale-write pravila. Acceptance: dva naloga ne vide tuđe redove; kasni upload i tombstone ne vraćaju obrisano; svaka nova operacija je idempotentna.
- **G4 Migration gate:** verzionisane additive promene, server/local parity, regeneracija i restore fixture. Ne rezervisati verzije u šest chatova unapred.
- **G5 Quality gate:** dovršiti otvorene 010 journey/UX zadatke i dodati backend test/build matriks u kasnijoj CI grani. Testovi su lokalni/fake; ne koristiti produkciju.
- **G6 Source gate:** commit/path/symbol dokaz, proverena licenca i notices za svaki kopirani fajl; nepromenjen hash; reference-only nije runtime dependency.

Kontrolna tačka: ne otvarati širok feature rollout dok failure scenariji osnovnog toka plan → nabavka → ostava → offline/sync nisu provereni. Sadašnji blueprint validira dokumentaciju, ne zatvara G1–G5 implementaciju.

## Redosled talasa

| Talas | Sadržaj | Uslov ulaska / izlaska |
|---|---|---|
| W0 | G0–G6, specifikacija 010 i zajednički ugovori | Izlaz: dosledan baseline, bezbedan AI tok i proširivi quantity/scope model sa testovima. |
| W1 | Pretraga/normalizacija/ostava, URL import, portable JSON i osnovno kuvanje | Početi F039/F002 → F003/F004/F030 → F005, zatim F001/F022/F008/F047; svaka funkcija zasebna vertikala. |
| W2 | Praktično planiranje i solo nabavka | F007/F031/F033/F034/F041/F045, zatim F009/F010/F016/F028/F036/F049; zajedničke upise redom. |
| W3 | Lotovi, prinos, pakovanja, ostaci i merenje | F006/F012/F013/F037/F038/F040/F042/F073/F074/F075; isti supply obračun i jasna semantika kuvanja/konzumacije. |
| W4 | Domaćinstva, članstvo, konflikti, finansije | F011/F063 pre F044/F056/F057/F066; zatim privatno deljenje F064 i arhive F065. |
| W5 | Cene, promocije, kalendar i automatizacije | F017/F018 pre F043/F070/F071/F083; F060/F090, F059/F068/F069/F072/F088 i sandbox F067. |
| W6 | Napredna pretraga, sadržaj, formule i edukacija | F014/F019/F020/F021/F023/F024/F025/F026/F027/F029/F032/F035/F046/F048/F050/F051/F052/F053/F054/F055/F058/F061/F062/F079/F080/F081/F082/F084/F085/F086/F089 prema dokazanim zavisnostima. |
| W7 | Uslovni hardver i spoljne zajednice | F076/F077/F078/F087 tek nakon probe podrške/API-ja i ručne alternative. |

Ovo su grupe redosleda, ne obećanje datuma i ne tvrda zabrana ranije samostalne S/M vertikale. Tačan topološki redosled iz manifesta ima prednost. Pre implementacije svaku stavku koja prelazi pet fajlova razložiti na manje vezane commit-e; scope slices iz istraživanja su početni razrez.

## Šablon izvršavanja jedne funkcije

1. Pročitaj baseline i odgovarajuću Fnnn stavku, napiši/razjasni malu Spec Kit specifikaciju na novoj grani iz najnovijeg `main`.
2. Napiši kriterijume i failing domain/parser/repository test za minimalni korisnički scenario. Za dokumentacionu promenu ne izmišljati Flutter test.
3. Implementiraj minimalni tok kroz postojeće modele/repozitorijum i UI; novu migraciju odobrava integrator ugovora. Ne menjaj susedne funkcije bez potrebe.
4. Proveri promenjeni i susedni tok, offline i scope; dodaj pogrešan/granični ulaz. Testovi bez realnih AI ključeva/produkcije.
5. Tek nakon stabilnih podataka uradi vizuelno doterivanje, uz čuvanje postojećih animacija, reduced motion i wake-lock ponašanja.
6. Review i CI, mala ljudski potpisana commit poruka bez Codex co-author/session linija; tek posle dokaza ažurirati status funkcije.

## Matrica verifikacije

- Brza provera plana: `python3 tools/verify_blueprint.py`.
- Implementacija: `scripts/check.sh`, relevantni `flutter test test/...`; puna Flutter suite kada shared kod to zahteva i u CI.
- Šema/RLS: lokalni `supabase db reset` i `supabase test db` nad lokalnim stack-om, sa dva naloga; nikada produkcija.
- Build: `flutter build macos --debug`, uz platform smoke provere Android/iOS kada se menjaju native adapteri.
- Dugi/eksterni tokovi: fake deterministički test + sandbox/device dokaz, uz zapis platforme/modela/verzije.
- UI/usability: kompletan plan i standalone nabavka na telefonu i wide layout-u, text 2×, offline/retry, bez gubitka unosa.

## Rizici i odluke koje ostaju otvorene

| Rizik | Postupak |
|---|---|
| Prevelik obim 90 funkcija | W1/W2 su prvi korisnički releasovi; ostalo ostaje pošten backlog. |
| Različite licence i jezici | Proučiti obrazac, koristiti mali permissive fajl sa notices ili samostalno implementirati ugovor; nema blanket kopiranja. |
| Nema potvrđenih cena/proizvoda za Srbiju | Capability probe i datiran coverage uzorak pre izbora dobavljača. |
| AI ne poštuje ograničenja | Typed propagation + završna domenska provera + regresioni eval skup. |
| Konflikti zaliha/finansija | Jasna semantika događaja, idempotency i serverska atomska potvrda kad je potrebna. |
| Šest paralelnih radova | Isključivi output direktorijumi, jedan integrator zajedničkog state-a i migracija. |
| Stari klijent/novi server | Additive protokol, nullable polja, verzije arhiva i testovi upgrade/restore. |

Neodlučeno: konkretan price/retail dobavljač za Srbiju, runtime za duže AI poslove, BYOK gateway model, podržani uređaji, način zaštite i čuvanja pune arhive, dozvole za buduće javno izdanje originalnog koda. Ove tačke ne sprečavaju sadašnji izvorni blueprint; sprečavaju tvrdnju da odgovarajuća integracija već radi.
