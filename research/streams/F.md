# F — Platforma, prenosivost i kvalitet recepta

Datum: 9. novembar 2026. Tavli baseline: `1eca2c3d14fb5dd9b25a42958aa018c8d8dfbb94`. Ovo je istražen plan i kolekcija referenci, bez implementacije 15 predloga. Pročitani su AGENTS.md, constitution, product direction, koordinacija i svih 15 dodeljenih stavki registra. Nisu menjani lib/, test/, migracije ni git stanje projekta; nisu pokretani upstream kod, install skripte, backend ili Flutter testovi. Svi scenariji ispod su buduće provere osim završne validacije istraživačkih artefakata.

## Uočeno postojeće stanje

- `lib/domain/recipe.dart`: interni Recipe/Ingredient JSON, source photo/ai/manual, opcione quantity/unit i ravni steps. `fromAiJson` može podrazumevati 2 porcije; ne koristiti ga kao jedinu import validaciju.
- `lib/data/recipe_repository.dart`: household scope, create/update u drift transakciji + SyncedWriter, prethodne verzije i maxVersions=30. Nema export/import/backup servisa.
- `lib/domain/shopping_source.dart`: RecipeSnapshot zamrzava odobren sadržaj za plan i samostalnu nabavku; nije backup naloga niti trenutni immutable revision identitet.
- `lib/domain/shopping_demand.dart`: scaleQuantity/demandFor/normalizeUnit održavaju porcije, kompatibilne jedinice i unknown količine. Ne menjati ovu računicu radi kalupa ili testa.
- `lib/data/database.dart`: schemaVersion 5; postoji kompletan povezani skup plans/shopping/pantry/ratings/userProfiles i lokalni sync/account/settings podaci. Razlikovati ovlašćene korisničke podatke od lokalnih mehanizama naloga.
- `lib/sync/entities.dart`: 12 domenskih entity adaptera u topološkom redosledu; `parents` uključuje dodatne veze. `SyncedWriter` outbox čuva identitet promene i čita aktuelni sadržaj kasnije: nije istorijski event payload.
- `lib/sync/photo_sync.dart`: `_referenced` čita recipe i version slike. Za budući backup inventar potrebno je dodatno proći meal/shopping snapshots i ugnježdene child snapshots; ovo je plan u okviru F065, bez usputne izmene PhotoSync-a.
- `lib/features/recipes/from_photo_screen.dart`, `ai_preview.dart`, `lib/data/photo_resize.dart`: već postoje fotografija/AI/preview/save, ali slika je smanjeni JPEG i ne postoji raw OCR transcript ili validiran confidence. Sačuvati PhotoScan animaciju.
- Native manifesti/AppDelegate fajlovi postoje, ali nema widget targeta/provider-a u pregledanom stablu. `pubspec.yaml` ne uključuje PDF/widget biblioteku. Nema obećanja da platformski capability već radi.

## Zajednički ugovori i kapije

Oznake zavisnosti u manifestu su kapije za implementaciju, ne tvrdnja da su završene:

- **G010**: sačuvati postojeći plan→nabavka→ostava i snapshot računicu; proveriti stvarni 010 status kod integracije. Kod već implementira deo pravca, istorijski dokument nije zamena za pregled.
- **G-PORTABLE**: read-only typed snapshot reader, bounded file I/O, staging/cleanup, capability save/share. Portable Recipe JSON (F022), batch import (F023), PDF (F021) i full backup (F065) imaju različite formate i garancije.
- **G-PROVENANCE**: zajednički FieldProvenance(sourceKind, sourceRef, rawValue, transformVersion, retrievedAt, userConfirmation), stable ingredient IDs i canonical recipe revision hash. Source claim, AI suggestion, user assertion i deterministic derived estimate su odvojene vrste. Hash obuhvata sadržaj recepta i intrinsic formula metadata; trial porcije/oprema su zaseban zapis uslova, a lokalne putanje/timestamps nisu deo sadržaja. Stare ingredient liste migriraju sa stabilnim ID-jevima; display redosled ostaje očuvan.
- **G-SCHEMA**: nova polja/tabele tek u zasebnim verzionisanim drift migracijama sa schemaVersion bump-om, generated kodom, backward JSON decoder-ima, entity registry/parents adapterima i Supabase migracijom. Svaki domenski upis preko postojećih repozitorijuma i outbox transakcije; svaka server tabela RLS/grants i dva naloga u pgTAP. Defaults ne smeju pretvoriti nepoznat podatak u potvrđen.
- **G-SERVER**: odvojeni server endpoint-i za share/API/events, eksplicitna allowlist projekcija i prava po vlasniku/domaćinstvu. Public token ne otključava private Supabase tabelu. Service credential nikad u aplikaciji; backend rad u lokalnom test okruženju pre deploy-a.
- **G-DEVICE**: capability probe po platformi, dostupnost native targeta i real-device test. Nedostupno/odbijeno stanje je pun podržan tok.
- **G-DATA-LICENSE**: dataset prava i atribucija za tačno izdanje odvojeni su od MIT licence parsera. Ne pretpostaviti da open-source aplikacija daje pravo na sav uvezeni sadržaj.

Predloženi novi moduli su čiste Dart granice `lib/domain/recipe_portability.dart`, `recipe_revision.dart`, `recipe_consistency.dart`, `nutrition.dart`, `baking_calculators.dart`; servisi u data/ sloju nad postojećim repository-ima. To su predlozi putanja, ne kreirani fajlovi. Nema paralelne baze recepata, plana ili nabavke. Riverpod wiring ostaje u postojećem obrascu. Svaki vertikalni korak ide zasebno kroz spec→plan→test-first domain/parsing→implementacija→provera; polish posle stabilnih podataka, bez uklanjanja animacija.

Prioritet: P1 F022/F049; P2 F046/F059/F064/F065/F084/F085; P3 F021/F023/F027/F079/F080/F086/F088. P1 nije dozvola za preskakanje schema/RLS kapija. Sva nova UI kopija je srpska latinica; primeri ispod su obavezne poruke u odgovarajućoj implementacionoj specifikaciji.

## Granice formata i dokaza

| Proizvod | Sadržaj | Šta nije garantovano |
|---|---|---|
| PDF kuvar | Samo odabrani čitljivi recepti/slike | Mašinska obnova ili opoziv preuzete kopije |
| schema.org Recipe | Prenosiva semantika jednog recepta | Nalog, istorija, planovi, prava, svi interni metapodaci |
| Migracioni batch | Kandidati + losses + odluke + source map | Tiho spajanje po naslovu ili svaki format svake verzije |
| tavli-space backup | Ovlašćeni kompletan graf i assets, verzionisan manifest | Tuđe privatne informacije, autentifikacija ili ključevi |
| Nutritivna/ekološka procena | Potvrđeni izvori + metod + pokriveni subtotal | AI vrednosti kao činjenice ili nepoznato=0 |
| Isprobano | Korisnička izjava za sadržaj i uslove | Sertifikat, AI pouzdanost ili automatsko važenje za novu verziju |

## F021 — Porodični PDF kuvar (P3)

**Postojeće:** RecipeRepository.getAll/get daju recepte domaćinstva; RecipeView je prikaz u aplikaciji, bez PDF izvoza. Pubspec nema PDF/printing biblioteku.

**Tačne Tavli tačke:** `lib/data/recipe_repository.dart: RecipeRepository.getAll/get`; `lib/features/recipes/recipe_view.dart: RecipeView`; `lib/domain/recipe_format.dart: ingredientLine`; `pubspec.yaml`.

**Predloženi ugovor/model:**

1. Predlog: RecipeBookExportService.render(ExportSelection, frozenRecipeSnapshots, PhotoReader) -> ExportArtifact(bytes, mime, warnings). Izbor sadrži samo eksplicitno odabrane ID-jeve i redosled; metadata opcije: naslov, sadržaj, fotografije, izvorni link. Snimiti read-only stanje pre renderovanja.
2. Izostaviti AI instrukcije iz istorije, lične ocene i tuđe profile. Uključiti samo dostupne odabrane slike; nedostajuća slika daje tekstualnu zamenu. Renderovanje u pozadini; korisnik prvo dobija pregled, zatim sistemski save/share sa capability proverom. Bez OS podrške ponuditi čuvanje fajla.
3. Predložena nova lib/features/recipes/recipe_book_export.dart koristi postojeći repozitorijum; pdf/font dependency odabrati i obrazložiti u spec plan.md tek u implementaciji. Proveriti pravo ugrađivanja fonta i srpske glifove.

**Mali vertikalni koraci:**

1. Izbor dva recepta -> statičan tekstualni PDF -> pregled bez upisa.
2. Dodati paginaciju, sadržaj i lokalne slike na istom toku.
3. Dodati sistemsko čuvanje/deljenje i otkazivanje velikog izvoza.

**Merljivi kriterijumi prihvatanja:**

1. PDF od izabranih 2 od 5 recepata sadrži tačno ta 2 u zadatom redosledu; nema naslova ostala 3.
2. ćčđšž i dugačak korak pravilno se prelamaju; naslov i porcije su vidljivi; generisanje ne menja ni jedan outbox red.
3. Nedostajuća slika ne prekida izvoz; otkazivanje ne ostavlja trajni privremeni fajl.

**Konkretna verifikacija (planirana):**

1. Budući service test sa fake repository i photo store: hash baze i outbox count isti pre/posle.
2. Otvoriti rezultat PDF parserom, proveriti broj recepata/stranica i tekst; vizuelno proveriti čćđšž i višestranične korake.
3. Widget test izbora i capability denied/cancel; ručni Android/iOS/macOS save/share smoke.

**Rizici/granice:**

1. PDF je deljena statična kopija koju opoziv linka ne može povući. Ne predstavljati ga kao rezervnu kopiju.

**Zavisnosti:** `G010`, `G-PORTABLE`.

**Dokaz izvora:** `recipya:files.go/exportRecipesPDF`.

## F022 — Prenosivi schema.org/Recipe JSON (P1)

**Postojeće:** Recipe.toJson je Tavli interni oblik sa id/source/imagePath/createdAt; Recipe.fromJson delegira fromAiJson koji nedostajuće porcije podrazumeva na 2. To nije schema.org adapter. Ingredient.quantity/unit su opcioni, steps su ravna lista stringova.

**Tačne Tavli tačke:** `lib/domain/recipe.dart: Recipe.toJson/fromJson/fromAiJson, Ingredient`; `lib/domain/recipe_format.dart: ingredientLine`; `lib/data/recipe_repository.dart: RecipeRepository.create`; `lib/sync/entities.dart: RecipeEntity`.

**Predloženi ugovor/model:**

1. Predložiti lib/domain/recipe_portability.dart: RecipeDocument(schemaVersion, recipeCandidate, rawSourceJson, fieldProvenance, warnings, losses); RecipeJsonAdapter.decode/encode su čiste funkcije. RecipeSource proširiti preko zasebne migracije za import, ne pogrešno označiti kao manual/AI.
2. Izvoz: @context=https://schema.org, @type=Recipe, name=title, recipeYield=tekst potvrđenih porcija, recipeIngredient=ingredientLine, recipeInstructions=HowToStep(text); prepMinutes mapirati isključivo na prepTime PT…M, nikako izmišljati cookTime ili totalTime. createdAt mapirati dateCreated. Lokalnu putanju imagePath ne objavljivati; sliku izostaviti uz upozorenje ili poseban eksplicitni paket.
3. Uvoz prihvata objekat, listu i @graph sa tačnim Recipe tipom (string ili niz), tekstualne sastojke i PropertyValue, tekst/HowToStep/HowToSection uz redosled i sačuvan original. Razdvojiti rawYield i potvrđene servings: 12 keksa, 4–6 porcija i odsutno polje traže pregled; bez tihe pretpostavke 2. Nepoznate mere ostaju null + raw line u provenance.
4. Ekstenzije Tavli u namespaced sidecar mogu očuvati category/note i preciznu strukturu; generičan schema.org round-trip garantuje semantički tekst i potvrđene porcije, ne identične objekte. Raw polja se ne renderuju kao HTML i ne izvršavaju; ograničiti veličinu/dubinu; ništa ne preuzimati iz image URL-a bez posebne odluke.

**Mali vertikalni koraci:**

1. Test-first tekstualni Recipe export i ručni izbor fajla -> preview.
2. Decoder za kanonski Recipe i Nextcloud tipove -> per-field upozorenja -> potvrda -> repository create.
3. @graph/sections/PropertyValue + verzionisan Tavli sidecar -> loss report i ograničeni import.

**Merljivi kriterijumi prihvatanja:**

1. Tavli recept sa 250 g brašna i 2 porcije izvoz/uvoz čuva naslov, tekst svih sastojaka, korake i potvrđene 2 porcije.
2. Nextcloud recipeYield=null ili "4–6 servings" traži potvrdu, bez automatskog biranja maksimalnog broja.
3. Za nepodržano nutrition/tags/sections polje postoji eksplicitan losses zapis; arhiva naloga se ne prihvata kao jedan Recipe JSON.
4. @graph sa Recipe i Person ne uvozi Person kao recept; 10 MB/dubina 64 su predloženi početni limiti koji daju čitljivu grešku.

**Konkretna verifikacija (planirana):**

1. Novi test/domain/recipe_portability_test.dart: samostalne sintetičke fixtures za context http/https, type niz, graph, sections, yield range, Unicode fractions, 0/negativno/NaN, invalid JSON.
2. Golden schema output + raw field retention; round-trip porediti ugovorena polja, ne source IDs ili lokalne putanje.
3. Proširiti test/data/recipe_repository_test.dart i test/sync/entities_test.dart; import preview cancel mora ostaviti 0 novih redova.

**Rizici/granice:**

1. Nextcloud filter popravlja/normalizuje šemu, ne čuva sve dvosmislenosti; Tavli treba pregled. Recipe JSON nije backup planova, istorije, ostave ili prava pristupa.

**Zavisnosti:** `G-PORTABLE`.

**Dokaz izvora:** `cookbook:RecipeService`, `cookbook:filters`, `recipe-scrapers:SchemaOrg`.

## F023 — Uvoz postojećih kolekcija (P3)

**Postojeće:** Nema importer registry/batch migracionog izveštaja; create upisuje jedan recept i outbox. Naslov nije jedinstveni identitet recepta.

**Tačne Tavli tačke:** `lib/data/recipe_repository.dart: RecipeRepository.create`; `lib/domain/recipe.dart: Recipe`; `lib/domain/ids.dart: newId`; `lib/features/recipes/add_recipe_sheet.dart`.

**Predloženi ugovor/model:**

1. Predložiti ImportAdapter.probe(header, boundedEntries)->format/version, preview()->ImportBatch i commit(confirmedDecisions, batchId). Početni adapteri: Nextcloud direktorijumi recipe.json + full.*, zatim Mealie recipe JSON; Paprika ide u zaseban adapter posle uzorka/fixture provere.
2. ImportItem čuva sourceRecordId, canonicalSourceUrl, contentFingerprint, candidate, unmappedFields, imageIssues i odluku skip/create/replace. Duplikat: prvo prethodno import mapiranje/identičan hash; sličan naslov samo kandidat za korisničku proveru. Nikad automatski spojiti dva različita jela istog naslova.
3. Verzionisani ImportBatchJournal daje nastavak i idempotenciju po batchId+itemKey. Preview nema upisa. Commit svake odobrene stavke ide preko istog repository/outbox toka; neuspešna stavka ostaje u izveštaju. Za replace koristiti update i postojeću istoriju.
4. Arhiva ima ograničenje broja fajlova, ukupne dekompresovane veličine i dubine; odbiti apsolutne putanje, ../, symlink i nested archive bez zajedničkog budžeta. Slike samo iz potvrđenog extraction root; remote URLs ne fetchovati podrazumevano.

**Mali vertikalni koraci:**

1. Batch sintetičkih Recipe JSON fajlova -> preview sa losses i duplicate candidates.
2. Nextcloud ZIP adapter sa slikama -> nastavak/otkazivanje -> journal.
3. Mealie adapter sa verzijom formata -> replace kroz update -> konačan izveštaj.

**Merljivi kriterijumi prihvatanja:**

1. Ulaz 5 zapisa: 2 nova + 1 već uvezen + 1 nevalidan + 1 sličan naslov daje tačan izveštaj, a commit samo odobrene nove stavke.
2. Ponovno pokretanje istog batch-a i prekid posle prve stavke ne dupliraju ništa.
3. recipe.json i full.jpg povezuju se po direktorijumu, bez mešanja slika dva istoimena jela.
4. 10000 entries / 250 MB expanded su predloženi početni limiti; traversal i symlink ne mogu pisati/čitati van staging direktorijuma.

**Konkretna verifikacija (planirana):**

1. Test-first fixture matrica za svaku eksplicitno podržanu aplikaciju/verziju; malformed header, whitespace pre {, batch mixed success, ID collisions.
2. Fake photo store i repository failure injection na stavci 2; resume i ponovljen commit moraju dati isti broj ID-jeva/outbox operacija.
3. Archive tests: ../outside, absolute, mixed separators, duplicate names, case collision, recursive ZIP bomb; two-account RLS restore/import tests.

**Rizici/granice:**

1. Recipya detektuje format prema početnom bajtu i koristi više aplikacionih parsera; Tavli treba tolerantniji whitespace i eksplicitni format probe. Migracija sa starog Go projekta ne dokazuje Rust kompatibilnost.

**Zavisnosti:** `F022`, `G-PORTABLE`, `G-SCHEMA`.

**Dokaz izvora:** `recipya:files_apps.go`, `mealie:NextcloudMigrator`.

## F027 — Podrecepti i zbir nabavke (P3)

**Postojeće:** Ingredient je samo name/quantity/unit/category/note; RecipeSnapshot zamrzava ravne ingredients. demandFor čuva DemandSource identitet i sabira kompatibilne jedinice. Nema grafa recepta.

**Tačne Tavli tačke:** `lib/domain/recipe.dart: Ingredient`; `lib/domain/shopping_source.dart: RecipeSnapshot`; `lib/domain/shopping_demand.dart: DemandSource/demandFor`; `lib/data/meal_plan_repository.dart`; `lib/data/shopping_repository.dart`.

**Predloženi ugovor/model:**

1. Nadograditi postojeći model komponentom RecipeComponent = IngredientComponent | SubrecipeComponent(childRecipeId, childRevisionHash, requestedYield, yieldUnit, frozenChild). Parent i child čuvaju poznat baseYield; broj porcija nije automatski masa sosa.
2. Pure expandRecipe(snapshot, requestedYield) -> ExpandedDemand(lines, provenancePaths, warnings). DFS stack odbija cikluse i preveliku dubinu pre upisa (predlog max 16); deljeni child u dva kraka mora doprineti oba puta. Za 200 g sosa iz recepta za 1000 g množiti child sastojke sa 0.2. Ne mešati g sa porcijama bez eksplicitne konverzije.
3. Zamrznuti kompletno razrešen graf u odobrenom meal/shopping snapshot-u. Kasnija child izmena/brisanje ne menja plan. Provenance putanja sourceId/componentPath omogućava objašnjenje nabavke; odabrati da se referenca računa kao sastojci ili kao već pripremljen sos, nikada oba istovremeno.

**Mali vertikalni koraci:**

1. Jedan parent -> child sa masenim yield -> preview proširene nabavke.
2. Snapshot grafa i outbox/remote serialization -> cycle/depth validacija.
3. Više nivoa i ponovljen child -> potvrđen izbor gotovo/sastojci -> regressions nabavke.

**Merljivi kriterijumi prihvatanja:**

1. Child 1000 g sosa traži 500 g paradajza; parent za 2 porcije koristi 200 g sosa: 100 g paradajza; za 4 porcije 200 g.
2. A->B->A se odbija pre bilo kakvog upisa; A->B i A->C->B računaju oba doprinosa.
3. Promena/brisanje child recepta posle odobrenja ne menja plan ni zamrznutu nabavku.
4. Nepoznat yield daje needsReview i ne izmišlja koeficijent.

**Konkretna verifikacija (planirana):**

1. Domain test-first DFS cycle/diamond/depth, različite yield jedinice, null količine, mikros rounding.
2. Proširiti test/domain/shopping_demand_test.dart, test/data/shopping_repository_test.dart i test/data/meal_plan_repository_test.dart za tačan unapred izračunat primer.
3. Round-trip serialized graph + offline sync + RLS dva domaćinstva; stari flat snapshot ostaje validan.

**Rizici/granice:**

1. Cooklang RecipeReference i IngredientList pokazuju reference/grupisanje, ali parser sam po sebi ne dokazuje Tavli cross-recipe resolver ili cycle policy.

**Zavisnosti:** `G010`, `G-SCHEMA`, `F022`, `F002`.

**Dokaz izvora:** `cooklang:model`, `cooklang:IngredientList`.

## F046 — Nutritivne vrednosti po porciji (P2)

**Postojeće:** Recipe nema nutrition; Ingredient nema kanonski food ID, jestivi udeo ili gram conversion. normalizeUnit ne pretvara volumen u masu bez gustine. AI trenutno vraća recept, ne proverene nutritivne podatke.

**Tačne Tavli tačke:** `lib/domain/recipe.dart: Recipe/Ingredient`; `lib/domain/shopping_demand.dart: normalizeUnit`; `lib/ai/prompts.dart`; `lib/data/database.dart: Recipes`.

**Predloženi ugovor/model:**

1. Predložiti NutrientFact(provider, datasetVersion, foodId, nutrientId, amount, unit, basisMassG, foodState, retrievedAt, license, sourceUrl). IngredientFoodBinding je korisnički potvrđena veza ingredientId->foodId i opciona density/edibleFactor sa svojim poreklom.
2. NutrientEstimate(recipeRevisionHash, servings, nutrientTotals, perServing, coverageByNutrient, knownMassG, unmatchedIngredientIds, unknownMassIds, methodVersion). Sumirati massG/basisMassG*amount; tek zatim deliti potvrđenim servings. Nepoznat podatak nije nula; navesti broj pokrivenih sastojaka i masenu pokrivenost samo ako je ukupna masa poznata.
3. Source-published nutrition iz Recipe JSON čuvati kao reported claim uz basis/yield i URL, odvojeno od izračunatog. AI može predložiti food match preko AIRouter; korisnik potvrđuje; AI broj nikada ne postaje NutrientFact. Ne tvrditi cooked retention ili water-loss korekciju bez metode/podataka.
4. FoodData Central je kandidat sa CC0 podacima i key-protected API; provider health/version probe i lokalni cache. Bez ključa/429/offline koristiti već potvrđene keširane fact-ove ili "Nema dovoljno podataka"; integraciju ne obećavati pre adapter testa.

**Mali vertikalni koraci:**

1. Ručno potvrđena 2 food bindings + lokalni fixture facts -> tačan per-serving proračun.
2. Source metadata i coverage u RecipeView -> cache kroz repository/outbox.
3. Opcioni FDC adapter -> capability/offline/429 -> verzionisanje procene.

**Merljivi kriterijumi prihvatanja:**

1. 200 g sastojka sa 10 g proteina/100 g + 100 g sa 5 g/100 g daje 25 g ukupno, 12.5 g za 2 porcije.
2. Dodavanje nepoznatog ulja daje partial coverage i ne ostavlja oznaku kompletno; ml bez gustine ne tretira se kao g.
3. Promena sastojka/yield-a invalidira derived estimate; izvorna tvrdnja ostaje vidljivo odvojena.

**Konkretna verifikacija (planirana):**

1. Domain test-first jedinice mg/g/kcal/kJ, per100g/basis, non-finite, zero servings, known zero vs missing nutrient i coverage denominator unknown.
2. Fake provider za 404/429/offline/stale dataset i potvrdu pogrešnog food match-a; bez stvarnog API ključa.
3. Recipe serialization/migration + dva naloga RLS i prikaz masene naspram brojevne pokrivenosti.

**Rizici/granice:**

1. Srpski nazivi/brandovi i cooked/raw podudaranje nisu provereni; izračun je procena dostupnih podataka, bez zdravstvenih tvrdnji.

**Zavisnosti:** `F002`, `G-SCHEMA`, `G-PROVENANCE`.

**Dokaz izvora:** `mealie:Nutrition`, `recipe-scrapers:SchemaOrg`, `web:FDC`.

## F049 — Sken i izdvojeni tekst uporedo (P1)

**Postojeće:** FromPhotoScreen _pick smanjuje sliku u JPEG, RecipeAI.fromImage daje strukturisani Recipe, AiRecipePreview prikazuje PhotoScan i recept. Nema OCR raw teksta/spans. Čuva se resize JPEG, ne izvorni original; preview trenutno koristi BoxFit.cover.

**Tačne Tavli tačke:** `lib/features/recipes/from_photo_screen.dart: _pick/_read/_save`; `lib/data/photo_resize.dart: downscaleToJpeg`; `lib/features/recipes/ai_preview.dart: AiRecipePreview`; `lib/ai/recipe_ai.dart: RecipeAI.fromImage`; `lib/domain/recipe.dart: Ingredient.fromJson/_parseQuantity`.

**Predloženi ugovor/model:**

1. Proširiti postojeći preview sa ScanExtraction(imageAssetId, rawText?, rawLines, fieldBindings, parseIssues, provider, processedAt). originalImage i processedPreview moraju imati različite asset role; postojeće JPEG slike označiti kao processedSource, bez obećanja nepostojećeg originala.
2. Prvo omogućiti contain/zoom fotografiju i uređivanje parsiranog recepta; opcioni extractedText preko postojeće RecipeAI/AIRouter fasade. Ako model ne daje tekst/koordinate prikazati "Izdvojeni tekst nije dostupan"; ne izmišljati bounding boxes ni confidence procenat.
3. Issue sadrži ingredient ordinal/stableId, raw token, razlog missing/invalid/ambiguousQuantity, korisničko razrešenje. Parser ne sme tiho izgubiti raw "1 1/2" ili nečitko polje pretvarajući ga u null bez objašnjenja. Raw OCR nije dokaz tačnosti; compare/edit/save ostaje potvrda.

**Mali vertikalni koraci:**

1. Postojeći photo preview -> contain/zoom + uporedni/switch prikaz na telefonu, bez novih AI poziva.
2. Proširiti extraction response sa raw lines i issues -> edit/confirm -> sačuvati kroz postojeći repository.
3. Asset role original/processed + opcioni izvornik uz izbor korisnika i migraciju.

**Merljivi kriterijumi prihvatanja:**

1. Na 390 px dostupni su izvor i recept pre čuvanja; na 1000 px dve čitljive kolone; 2x tekst bez overflow.
2. Ulaz "1 1/2 šolje" ili "? g" ima raw token i zahtev za proveru, nikad proizvoljnu ocenu 87%.
3. Odbacivanje/ponovni AI odgovor ne čuva stari draft ili slike; potvrđene ispravke ostaju posle offline otvaranja.

**Konkretna verifikacija (planirana):**

1. Widget tests proširiti test/features/recipes/from_photo_screen_test.dart sa contain/zoom i edit/save/cancel, race stale request odgovorom.
2. Domain extraction parse tests za missing/null/negative/NaN/fraction i synthetic OCR lines; fake AIRouter malformed JSON retry.
3. Photo resize/recipe repository/photo sync regresije; potvrditi da stari JPEG nije označen kao original.

**Rizici/granice:**

1. Potreban dogovor o čuvanju punih slika i potrošnji prostora. Postojeću PhotoScan animaciju sačuvati. F084 kontroliše semantiku koraka, ovaj tok vernost skena.

**Zavisnosti:** `G-PROVENANCE`, `G-SCHEMA`.

**Dokaz izvora:** Sopstveni predlog izveden iz pregledanog Tavli modela; nije tvrdnja o upstream implementaciji..

## F059 — Widget Danas (P2)

**Postojeće:** PlanScreen i shopping repositories postoje; native targeti imaju AppDelegate/MainActivity i manifests, ali nema widget extension/provider fajlova ni widget dependency u pubspec.

**Tačne Tavli tačke:** `lib/features/planning/plan_screen.dart`; `lib/data/meal_plan_repository.dart`; `lib/data/shopping_repository.dart`; `lib/app/router.dart`; `ios/Runner/AppDelegate.swift`; `macos/Runner/AppDelegate.swift`; `android/app/src/main/AndroidManifest.xml`; `pubspec.yaml`.

**Predloženi ugovor/model:**

1. Predložiti WidgetSnapshot(v1, accountScopeFingerprint, civilDate, timezone, meals[], remainingShoppingCount, generatedAt, lastSyncedAt, deepLink). Čita iz drift preko istih repositories, piše minimalnu projection u app-group/native shared storage; native widget ne dobija Supabase ni AI ključeve.
2. WidgetProjectionService regeneriše posle potvrđene lokalne promene, sync download-a, timezone/date/resume i sign-out. Dati naslov "Ažurirano …"; generatedAt nije lastSyncedAt. Stari datum jasno označiti, bez lažne garancije minutnog realtime osvežavanja.
3. Platform capability probe: target extension/provider registrovan, podržana OS verzija, shared container spreman; neuspeh -> "Widget nije dostupan na ovom uređaju" i in-app Danas. Početni widget read-only; tap otvara autorizovanu rutu, bez direktnog check/uncheck iz native skladišta.

**Mali vertikalni koraci:**

1. Čista projection za jedan dan + fake native bridge -> local event refresh.
2. Android provider/Glance vertikala i deep link -> real-device test.
3. iOS/macOS WidgetKit zasebno po platformi -> timeline/entitlements -> signout purge.

**Merljivi kriterijumi prihvatanja:**

1. Lokalna promena obroka daje novu projekciju i vreme osvežavanja bez interneta.
2. Signout/switch account uklanja tuđe nazive iz shared storage; novi nalog ne vidi stari snapshot.
3. Prelaz ponoći i Europe/Belgrade DST ne prikazuju jučerašnji dan kao današnji; OS odlaganje osvežavanja ima vidljiv timestamp.

**Konkretna verifikacija (planirana):**

1. Unit projection clock/timezone injection; count koristiti istu definiciju preostale nabavke kao ShoppingRepository, bez nove računice.
2. Widget/deep-link test signed out, deleted meal i missing account; native bridge fake denied/unavailable.
3. Ručni uređaj/emulator test svake omogućene platforme: pin, resize, OS process kill, restart, offline, midnight, signout; nije izvršen u istraživanju.

**Rizici/granice:**

1. WidgetKit/Android različito raspoređuju osvežavanje; capability matrica i real-device probe uslov su lansiranja. Apple stranica je dostupna ali alat nije dobio čitljiv sadržaj; ne tvrditi precizan refresh budget iz ovog pregleda.

**Zavisnosti:** `G010`, `G-DEVICE`.

**Dokaz izvora:** `web:AndroidWidgets`, `web:AppleWidgets`.

## F064 — Privremeni opozivi link bez naloga (P2)

**Postojeće:** Account-required routing i household RLS štite postojeće recepte; nema public share endpoint-a. Recipe source/version DTO uključuje podatke koji nisu automatski primereni javnom deljenju.

**Tačne Tavli tačke:** `lib/app/router.dart`; `lib/account/auth_controller.dart`; `lib/sync/entities.dart: RecipeEntity`; `supabase/migrations/20261030120500_rls_and_grants.sql`; `lib/domain/recipe.dart: Recipe.toJson`.

**Predloženi ugovor/model:**

1. Predlog ShareGrant(id, ownerUserId, householdId, recipeId, snapshotRevisionHash, tokenHash, expiresAt, revokedAt, createdAt). Random token >=256 bitova u URL-u prikazati samo pri stvaranju, u bazi hash; server vreme proverava expiry pri svakom zahtevu.
2. ShareRecipeDTO je eksplicitna allowlist: naslov, potvrđene porcije, sastojci, koraci i posebno odabrana slika/source attribution. Zamrznut snapshot, bez istorije/instruction/answeredBy/email/ostalih recepata/household IDs. Kreiranje linka je online akcija tek po korisnikovom izboru; offline preview i save normalno rade.
3. Serverse read-only endpoint proverava token+expiry+revocation i vraća samo share DTO; anon nema SELECT na public.recipes. Slike proxy kroz isti grant ili kratkotrajno potpisan URL sa TTL <= remaining grant TTL. No-store response/CDN bypass; stop current access on revoke. Nema automatskog follow/drugih recipe endpoints.

**Mali vertikalni koraci:**

1. Offline pregled tačne allowlist projekcije -> online grant create i jedna read ruta.
2. Expiry/revoke i za sliku -> vlasničko upravljanje linkovima.
3. Anonymous web view bez naloga -> abuse limiting -> accessibility.

**Merljivi kriterijumi prihvatanja:**

1. Anonymous token za A otvara samo A snapshot; pokušaj susednog ID/B istorije/household liste daje odbijanje.
2. Tačno na expiresAt i neposredno posle revoke grant više ne vraća recept niti nove image bytes.
3. Privatni recepti ostaju nedostupni anon role i nakon dodavanja share funkcije.
4. UI kaže da ranije preuzetu kopiju nije moguće obrisati kod primaoca.

**Konkretna verifikacija (planirana):**

1. Local pgTAP: owner/member/unrelated account/anon za grant i original tables; endpoint clock frozen expired/revoked cases.
2. Fake token store collision, tampering, rate limit i access logs redaction; test URL token se ne loguje.
3. Integration fetch HTML/JSON/image posle revoke i proveriti cache headers; nema stvarnog backend-a u testovima.

**Rizici/granice:**

1. Opoziv sprečava budući pristup, ne povlači screenshot/PDF/preuzetu kopiju. Mealie vraća RecipeOut; Tavli treba užu projekciju.

**Zavisnosti:** `G-SERVER`, `G-PROVENANCE`.

**Dokaz izvora:** `mealie:Share`.

## F065 — Potpuna rezervna kopija i obnova (P2)

**Postojeće:** Drift schemaVersion=5 ima recipes/versions, plans/entries, shopping sources/contributions/allocations, pantry, personal ratings/profiles i lokalne sync tabele. syncEntities je topološki registar, ne backup format. PhotoSync._referenced obilazi recepte/verzije, ne kompletan graf svih snapshot slika.

**Tačne Tavli tačke:** `lib/data/database.dart: AppDatabase.schemaVersion, sve domenske tabele`; `lib/sync/entities.dart: syncEntities/parents`; `lib/sync/photo_sync.dart: PhotoSync._referenced`; `lib/data/recipe_repository.dart: maxVersions/delete`; `lib/domain/shopping_source.dart: RecipeSnapshot`; `lib/account/account_service.dart`.

**Predloženi ugovor/model:**

1. Predložiti BackupManifest(format=tavli-space, version, appSchemaVersion, exportId, createdAt, scope, completeness, entityCounts, files[path,size,sha256], references, minReaderVersion). ZIP sadrži manifest.json, typed data/*.json i assets/<contentHash>.jpg; nijedan SQL statement iz arhive se ne izvršava.
2. Obuhvatiti sve korisničke domenske entitete i veze, sačuvanu istoriju do postojeće granice 30, snimke planova/samostalne nabavke, porcije/locked/cooked, pantry confirmations i purchase links/allocations. Lične ocene/profile izvoziti samo za tekućeg korisnika, podatke domaćinstva samo u okviru njegovih prava. "Potpuna" označava ovaj ovlašćeni prostor, ne tuđe profile niti ceo Supabase projekat. Lične preference uključuju samo sopstveni profileJson i bezbednu allowlist korisničkih podešavanja; AppSettings ne eksportovati wholesale.
3. Isključiti Auth identitete/sesije/AI i integracione ključeve, Accounts email cache, ModelStatuses, SyncCursors i stari outbox. Outbox se regeneriše iz obnovljenog stanja. Sve asset reference tražiti kroz recepte, verzije i sve ugnježdene snapshots, ne kopirati samo trenutni PhotoSync traversal.
4. Consistent export barrier: zamrznuti lokalne writes/sync na kratko, uhvatiti snapshot+referentne asset hash-eve, nastaviti aplikaciju, završiti u staging-u. Ako cache nije kompletan, download/images nije gotov ili pending/rejected changes postoje, navesti completeness/pending summary i ponuditi dovršetak; nepotpun izvoz ne nazvati potpunim. Offline moguće arhivirati poznato stanje uz jasno incomplete.
5. Restore plan(archive,target) radi checksum/version/schema/graph/path preflight pre upisa. Početni target novi prostor/import u ovlašćeno domaćinstvo sa novim ID-jevima i kompletnim ID mapiranjem uključujući JSON reference i personal owner map na tekućeg korisnika; nema reinstalacije tuđeg članstva ili automatskih grant-ova. Replace postojećeg prostora je kasniji eksplicitan destruktivan tok sa pre-backup-om, nikad default.
6. Journal restoreId i deterministični ID mapping čine retry idempotentnim; staged photos pre transakcije, topološki domenski upisi+nov outbox u transakciji; pri neuspehu nijedan delimičan podatak ne postaje vidljiv. Nova schema zahteva adapter/migration chain; unknown future version -> bez upisa. Content-hash assets proveriti i finalizovati pre DB commit-a; reference postaju vidljive samo kad svi fajlovi postoje. Failed transakcija ostavlja najviše orphan assets za cleanup. Restore/import eksplicitno isključuje ponovno emitovanje F088 plan.confirmed događaja i vodi sopstveni audit.

**Mali vertikalni koraci:**

1. Versioned manifest i full graph/asset inventory -> export synthetic account -> offline inspect.
2. Preflight dry-run -> novi destination scope -> atomic local restore/outbox i photo staging.
3. Resumable upload/download, completeness i future schemas -> failure recovery.
4. Tek zasebnom specifikacijom dodati replace target i korisnički izbor arhiviranja/enkripcije.

**Merljivi kriterijumi prihvatanja:**

1. Fixture sa 2 recepta, 3 verzije, obrokom čiji je recipe obrisan, slikom samo u snapshot-u, pantry receipt vezom i allocation-om vraća iste count-ove i izračun nabavke.
2. Pre/posle restore broj nedostajućih sastojaka isti; primer potreba 300 g, pantry 100 g, kupljeno 200 g ne stvara novu potrebu ni dvostruko pokriće.
3. Truncated/hash mismatch/future version/dangling link/..//symlink prekidaju pre bilo kakvog domenskog upisa.
4. Ponovljeni restoreId ne stvara duplikate; archive ne sadrži auth/API secrets, sync outbox ni tuđe lične profile.
5. Nijedan nepotpun skup assets ne dobija completeness=complete.

**Konkretna verifikacija (planirana):**

1. Test-first backup encode/decode/migration sintetičke verzije, assert counts, referential closure i snapshot content hash.
2. Failure injection na svakoj fazi stage/transaction/outbox/upload i retry; fake backend + temp directory, bez hosted backend-a.
3. Local pgTAP sa 2 korisnika i dva domaćinstva: owner mapping, import permissions, anonymous denied; real file ZIP validation i zip bomb.
4. Proširiti test/data/migration_test.dart, test/sync/entities_test.dart, test/data/shopping_repository_test.dart; ne koristiti postojeći toRemote direktno kao trajni format.

**Rizici/granice:**

1. Mealie BackupV2.restore briše tabele i vraća podatkovni direktorijum, uključujući administrativnu konfiguracionu tajnu; Tavli taj obrazac ne prenosi. Kopija lokalne SQLite baze nije potpuna server/account kopija. Enkripcioni UX i maksimalna arhiva još su odluke.

**Zavisnosti:** `G010`, `G-PORTABLE`, `G-SCHEMA`, `G-SERVER`.

**Dokaz izvora:** `mealie:BackupV2`, `mealie:BackupContents`, `mealie:AlchemyExporter`.

## F079 — Kalkulator geometrije kalupa (P3)

**Postojeće:** Postoji scaleQuantity(quantity, baseServings, servings), što linearno skalira po porcijama. Nema geometrije/visine kalupa; time se ne može odrediti isti nivo testa u drugom obliku.

**Tačne Tavli tačke:** `lib/domain/shopping_demand.dart: scaleQuantity/demandFor`; `lib/domain/recipe.dart: Ingredient`; `lib/features/recipes/recipe_view.dart`.

**Predloženi ugovor/model:**

1. Pure PanGeometry.round(diameterCm)|rectangle(lengthCm,widthCm), PanScaleRequest(from,to,sourceFillHeightCm,targetFillHeightCm,countFrom,countTo), result(factor,assumptions,warnings). V=area*fillHeight*count; faktor=targetV/sourceV. Podržati prvo ravne vertikalne zidove; tapered/bundt/custom zahteva poznat volumen ili unavailable.
2. Preview primenjuje faktor na poznate ingredient quantities bez izmene base servings. Sačuvati kao novu verziju samo nakon potvrde uz calculation metadata; ordinary serving scaling i geometry mode su odvojene akcije. Korake/vreme/temperaturu ne množiti i ne obećavati isti rezultat pečenja.
3. Prikazati pretpostavku iste gustine/visine i stvarnu visinu kalupa kao granicu, ne popuniti kalup do vrha. NaN/inf/zero/negative dimenzije i targetFillHeight>panHeight -> blokiran izračun.

**Mali vertikalni koraci:**

1. Test-first round/rectangle volumes -> standalone kalkulator iz recepta.
2. Ingredient preview sa null količinama -> potvrda postojeće update istorije.
3. Broj kalupa i eksplicitni volumen za nepravilan oblik -> warnings i metadata.

**Merljivi kriterijumi prihvatanja:**

1. Okrugao 20 cm -> 25 cm pri istoj visini daje 1.5625; 200 g postaje 312.5 g.
2. Pravougaoni 20x30 cm -> okrugao 24 cm pri istoj visini daje 0.24*pi ≈0.7539822369.
3. Dvostruka target visina daje dvostruki faktor; unknown quantities ostaju unknown; 30 minuta ostaje 30 minuta uz upozorenje da vreme treba proveriti.

**Konkretna verifikacija (planirana):**

1. Domain test-first unapred navedeni rezultati uz tolerance 1e-9, unit mm/cm conversion, count, invalid input/overflow.
2. Widget preview/cancel/save -> jedna RecipeVersion i isti source recipe bez upisa pri cancel.
3. Regresija test/domain/shopping_demand_test.dart potvrđuje da standardno skaliranje porcija nije promenjeno.

**Rizici/granice:**

1. Geometrijski faktor nije validacija ponašanja testa ili automatski savet o bezbednosti pečenja. Cooklang scale može skalirati i timers; to se ne sme preuzeti kao Tavli pravilo.

**Zavisnosti:** `G-PROVENANCE`.

**Dokaz izvora:** `cooklang:scale`.

## F080 — Pekarski procenti (P3)

**Postojeće:** Ingredient nema flour/water/starter role ni starter hydration; masa i zapremina odvojene su u normalizeUnit. Obično scaleQuantity nema pojam ukupnog brašna.

**Tačne Tavli tačke:** `lib/domain/recipe.dart: Ingredient`; `lib/domain/shopping_demand.dart: normalizeUnit/scaleQuantity`; `lib/domain/recipe_version.dart: RecipeVersion`.

**Predloženi ugovor/model:**

1. DoughFormula(recipeRevisionHash, components[ingredientId, role, massG, starterHydrationPercent?], flourBasis, targetDoughMassG?, targetHydrationPercent?). Rola korisnički potvrđena; ne zaključivati tip brašna/udeo vode iz naziva ili AI-ja.
2. Za starter S i h=hydrationPercent/100: starterFlour=S/(1+h), starterWater=S*h/(1+h). Ftotal=directFlour+starterFlour, Wtotal=directWater+starterWater, hydration=100*Wtotal/Ftotal; svaki bakers%=100*ingredientMass/Ftotal. Starter uneti kao fizičku komponentu u dough mass samo jednom, njegove izvedene flour/water redove ne sabirati ponovo.
3. Prvi režim prikazuje procente i skalira poznatu kompletnu formulu na targetMass=sum(physical masses)*factor. Kasnije solve target hydration uz fiksno ukupno brašno/starters i ostale mase -> direct water = Htarget*Ftotal-starterWater; negativna voda -> nemoguće. Volumeni/unknown hydration/unknown sastojak daju partial/unavailable, bez pretpostavke 100%.

**Mali vertikalni koraci:**

1. Role picker + poznate mase -> bakers% i ukupna hidratacija.
2. Poznata starter hydration i target total mass -> preview -> potvrđena verzija.
3. Zaseban režim target hydration sa eksplicitnim fiksnim veličinama -> constrained solve.

**Merljivi kriterijumi prihvatanja:**

1. 500 g flour + 300 g water + 100 g starter pri 100% hydration + 10 g salt: F=550 g, W=350 g, H=63.6363636%, salt=1.8181818%, physical mass=910 g.
2. Target mass=1820 g udvostručuje sve fizičke komponente i čuva hidrataciju.
3. Za 70% hydration uz F=550 g, starter 100 g/100%, voda direktno=335 g; starter unknown hydration onemogućava precizan zbir.
4. Starter 200 g pri 50% hydration daje 133.3333 g flour i 66.6667 g water; nema dupliranja u target dough mass.

**Konkretna verifikacija (planirana):**

1. Domain test-first navedene ručno izračunate formule, više brašna/startera, 0 flour, negative/NaN, ml bez density i nepoznata hydration.
2. Mass conservation: sum samo fizičkih komponenti = target, derive starter sum = S, rounding poslednji korak.
3. Widget role confirmation/cancel i repository version regression; ordinary servings scaling ostaje odvojeno.

**Rizici/granice:**

1. Mleko/jaja/med ne računati kao čistu vodu; ako se kasnije uvedu compositional water facts potreban poseban izvor/metod.

**Zavisnosti:** `F002`, `G-PROVENANCE`.

**Dokaz izvora:** `cooklang:scale`.

## F084 — Unutrašnja doslednost recepta (P2)

**Postojeće:** Ingredient.fromJson proverava naziv i parsira količinu, Recipe.fromAiJson proverava naziv/listu; steps su stringovi. Nema semantičkih veza ingredient-step ni lint izveštaja.

**Tačne Tavli tačke:** `lib/domain/recipe.dart: Ingredient.fromJson/Recipe.fromAiJson`; `lib/domain/recipe_format.dart: normalizeForSearch`; `lib/features/recipes/recipe_form_screen.dart`; `lib/ai/recipe_ai.dart: RecipeAI.refine`.

**Predloženi ugovor/model:**

1. RecipeConsistencyService.analyze(revisionHash)->ConsistencyReport(issues[code,severity,stepIndex,ingredientId?,evidenceSpan,expected?,actual?,origin], analyzerVersion). Deterministička pravila prvo: eksplicitno povezani sastojci, kompatibilne jedinice, split quantities i ingredient identity/sinonimi.
2. Heuristike teksta prijavljuju candidateMissingIngredient/candidateAmountMismatch sa citiranim span-om; ne proglašavati odsustvo dok nemamo pouzdano mapiranje. Neupotrebljen sastojak može biti garnitura, pa warning. "pola mleka"/"ostatak" ne tretirati kao novu punu količinu; range/optional i različite faze odvojiti.
3. AI opcioni dodatni pregled isključivo preko AIRouter, origin=aiSuggestion; nema automatskog uređivanja niti safety/verified badge-a. Prihvati ispravku otvara postojeći editor/AI preview i čuva RecipeVersion; dismissed issue vezan za revision+rule version.

**Mali vertikalni koraci:**

1. Pure lint sa eksplicitnim ingredient-step refs i sintetičkim primerima -> issue panel.
2. Text candidate rules sa dokaznim span-om i dismiss/resolve -> postojeći editor.
3. Opcioni AI suggestions -> odvojena oznaka/preview -> regression corpus.

**Merljivi kriterijumi prihvatanja:**

1. Lista sadrži 100 g šećera, dva eksplicitno povezana koraka koriste 60 g i 60 g: issue ukupno 120 g >100 g.
2. 60 g +40 g prolazi; "dodaj ostatak" se ne prijavljuje kao dodatnih 100 g.
3. "Dodaj 2 jaja" bez egg ingredient daje kandidat sa tačnim korakom; izveštaj ne menja recept.
4. Promena verzije briše oznaku da je stari lint rezultat aktuelan; AI issue vidljivo je predlog.

**Konkretna verifikacija (planirana):**

1. Test-first corpus minimalnih srpskih parova: optional garnitura, synonyms, g/kg, ml/g unknown, split/ranges/remainder, korak bez mera.
2. Measure precision/recall na ručno označenom sintetičkom/regresionom skupu; target >=95% precision za deterministic rules, heuristike ne blokiraju čuvanje.
3. Widget resolve/dismiss i stale revision; repository update/undo tests; fake AI parser retry.

**Rizici/granice:**

1. Bez potvrđenih veza step-ingredient ne obećavati potpunu proveru slobodnog srpskog teksta; ovo nije provera nutritivne ili zdravstvene bezbednosti.

**Zavisnosti:** `F002`, `F028`, `G-PROVENANCE`.

**Dokaz izvora:** `cooklang:analysis`.

## F085 — Status testiranog recepta (P2)

**Postojeće:** RecipeSource photo/ai/manual i answeredBy opisuju nastanak/poslednji model, ne stvarno kuvanje. RecipeVersion čuva prethodno stanje, Ratings ima cookedAt/stars ali ne snapshot revision/porcije/opremu.

**Tačne Tavli tačke:** `lib/domain/recipe.dart: RecipeSource/answeredBy`; `lib/domain/recipe_version.dart: RecipeVersion`; `lib/data/database.dart: Ratings`; `lib/data/recipe_repository.dart: update/restore/watchVersions`; `lib/features/recipes/versions_sheet.dart`.

**Predloženi ugovor/model:**

1. Predložiti RecipeTrial(id, recipeId, revisionHash, testerUserId, testedAt, servings, equipmentSnapshot, outcome, notes?, evidenceAssetIds?, visibility). Canonical revision hash stabilno kodira kuvarski sadržaj i opremu/yield koji su deo same formule; trial servings/equipment su zaseban uslov isprobavanja, ne updatedAt/local imagePath/model label. Hash nije current row ID.
2. Badge izveden iz trial-a sa pozitivnim korisnički potvrđenim ishodom za tačan revision i uslove: "Isprobano: 4 porcije, rerna …"; AI, import i ocena zvezdicama ne stvaraju trial automatski. Posle promene recepta prikazati "Prethodna verzija je isprobana". Vraćanje identičnog sadržaja može ponovo povezati postojeći trial; promenjena oprema/servings prikazuje drugačije uslove.
3. Privatni dnevnik/ocene (F047) odvojeni su od eksplicitno deljene tvrdnje o isprobavanju. Trial personal owner RLS; household badge samo uz visibility=household i minimalne podatke. Brisanje recepta/istorije ne sme tiho pretvoriti tvrdnju u dokaz druge verzije; sačuvati trial content hash i potreban snapshot ili ukinuti prikaz.

**Mali vertikalni koraci:**

1. Revision hash i ručno potvrđen trial za jedan recept -> read-only badge.
2. Promena/restore recepta -> aktuelan/prethodni status + uslovi.
3. Eksplicitna visibility kontrola i veze sa opcionalnim dnevnikom -> sync/RLS.

**Merljivi kriterijumi prihvatanja:**

1. AI-generisan recept ima status "Nije označen kao isproban" i ne dobija badge iz source/modela.
2. Trial za 2 porcije u kalupu 20 cm ne dokazuje 8 porcija/30 cm; UI navodi tačne uslove.
3. Izmena 100 g->120 g menja hash i aktuelni badge nestaje, original trial ostaje vezan za stari sadržaj.
4. User B ne može dodati/izmeniti trial kao user A; privatne notes nisu u javnom F064 DTO.

**Konkretna verifikacija (planirana):**

1. Test-first canonicalization hash za semantic changes naspram updatedAt/model/imagePath, ordering i Unicode normalizaciju po definisanom pravilu.
2. Repository trial creation/update/undo/restore i pruned history slučaj; test ličnog visibility-a.
3. Local pgTAP dva korisnika: owner create/update, household projection allowlist i share leak regression.

**Rizici/granice:**

1. "Isprobano" je korisnička izjava, bez nezavisnog sertifikata ili dokaza zdravstvene bezbednosti. Nova trajna current revision osnova potrebna je jer postojeća istorija čuva samo prethodna stanja i najviše 30 verzija.

**Zavisnosti:** `G-PROVENANCE`, `G-SCHEMA`, `F047`.

**Dokaz izvora:** Sopstveni predlog izveden iz pregledanog Tavli modela; nije tvrdnja o upstream implementaciji..

## F086 — Procena ekološkog uticaja sa poreklom (P3)

**Postojeće:** Recipe/Ingredient nemaju environment facts, region, proizvodni metod ni mass binding. Količine bacanja iz F040 nisu environmental impact metod.

**Tačne Tavli tačke:** `lib/domain/recipe.dart: Ingredient`; `lib/domain/shopping_demand.dart: normalizeUnit`; `lib/data/database.dart: Recipes/PantryItems`.

**Predloženi ugovor/model:**

1. EnvironmentalFactor(dataset, datasetVersion, factorId, foodState, geography, productionSystem, functionalUnit, indicator, amount, unit, lifecycleBoundary, methodVersion, sourceUrl, license, retrievedAt). IngredientImpactBinding korisnik potvrđuje; čuvati assumptions i match quality kategorički, ne izmišljeni confidence broj.
2. Početni indikator climate kgCO2e/kg food sa kompatibilnim boundary i istom metodom. result=Σ massKg*factor; per-serving deli potvrđenim servings. Nepoznat sastojak ili geografsko nepoklapanje -> partial/assumption vidljivo. Ne mešati upstream farm-gate sa retail/plate faktorom; ne sabirati već zbirni prepared-dish faktor sa njegovim sastojcima.
3. RecipeImpactEstimate(revisionHash, indicator, totalKnownImpact, coverageCount, knownMassCoverage?, unknownMassIds, factors[], assumptions[], computedAt). Poznati subtotal nije total cele hrane kad nedostaje pokrivenost. AGRIBALYSE LCA dokumentacija je kandidat za metod/provenance, dataset i reuse prava tačnog izdanja tek proveriti; u ovom prolazu nisu preuzeti faktori niti implementiran servis.

**Mali vertikalni koraci:**

1. Sintetički mass factors -> tačna suma/coverage -> read-only prikaz.
2. Dataset license/version/boundary review -> jedan eksplicitno podržan dataset adapter i lokalni cache.
3. User-confirmed ingredient bindings + stale/method change invalidation -> poređenje samo uporedivih procena.

**Merljivi kriterijumi prihvatanja:**

1. 0.2 kg A sa 5 kgCO2e/kg +0.3 kg B sa 1 kgCO2e/kg daju 1.3 kgCO2e poznatog subtotala, 0.65 za 2 porcije.
2. Dodatni nepoznat sastojak označava partial; unknown masa sprečava lažan 100% maseni coverage.
3. Faktori sa različitim boundary/method nemaju jednu zbirnu ocenu; datasetVersion i geography vidljivi su korisniku.
4. Offline bez faktora daje unavailable, bez AI izmišljenih brojeva.

**Konkretna verifikacija (planirana):**

1. Domain test-first kg/g, factor functional units, mismatched boundaries, missing mass, zero vs absent factor i double-count prepared food.
2. Fake adapter za missing ID/version/license i cache age; snapshot invalidation pri izmeni recepta.
3. UX test izvor/metod/pokrivenost i comparing partial vs complete upozorenje; bez stvarnih podataka tvrdnje o Srbiji.

**Rizici/granice:**

1. Francuski prosečni LCA faktori nisu dokazana lokalna Srbija procena; regionalna reprezentativnost, dataset prava i pokrivenost ostaju otvoreni.

**Zavisnosti:** `F046`, `F002`, `G-PROVENANCE`, `G-DATA-LICENSE`.

**Dokaz izvora:** `web:AGRIBALYSE`.

## F088 — Lične automatizacije, ograničen API i webhooks (P3)

**Postojeće:** SyncedWriter outbox je account-scoped klijentski sync red, ne stabilan domen event stream; čita sadržaj u trenutku slanja. Nema integration credentials/subscriptions/event delivery tabele. UI ne sme direktno komunicirati sa n8n.

**Tačne Tavli tačke:** `lib/sync/synced_writer.dart: SyncedWriter.upsert`; `lib/sync/uploader.dart`; `lib/data/meal_plan_repository.dart`; `lib/account/account_api.dart`; `supabase/migrations/20261102120000_plan_and_shopping.sql`.

**Predloženi ugovor/model:**

1. Predlog IntegrationGrant(id, ownerUserId, householdId, tokenHash, scopes, resourceIds, expiresAt, revokedAt). Početno scopes plan:read, events:plan.confirmed; bez write/admin/ostava/profil sadržaja. Opaque token vezan za tačne resurse i aktivno članstvo proveravati pri svakom zahtevu; token nije Supabase user session.
2. DomainEvent(id, type, schemaVersion, resourceId, revision, occurredAt, payloadProjection) stvara server tek po uspešnom autorizovanom potvrđivanju plana, u istoj transakciji sa zapisom i UNIQUE idempotency key. Uploader retry ne pravi novi događaj. Offline odobrenje stiže do servera kasnije; payload nosi occurredAt i acceptedAt. Klijentski mutable outbox ne koristiti za istorijski payload.
3. WebhookSubscription(events, endpoint, allowedFields, grantId), Delivery(eventId, subscriptionId, attempt, nextAttemptAt, status). Slati minimalni snapshot izabranih polja; at-least-once, stabilan eventId, exponential backoff+jitter, max attempts/dead-letter, pregled statusa i izričit replay. Order po resource revision, ne obećavati globalni exactly-once.
4. Signature HMAC-SHA256 nad stabilnim eventId.timestamp.rawBody; verzionisani secret uz rotaciju, constant-time receiver verification i vremenski replay prozor. Delivery endpoint zahteva https, server SSRF/public-address proveru posle DNS resolution-a i svakog redirekta (ili zabranu redirect-a), size/time limits. n8n private LAN nije podrazumevano dostupan cloud dispatcher-u; nuditi read-only polling sa ograničenim tokenom kad inbound endpoint nije moguć.
5. Revoke/expiry/uklonjeno članstvo proveriti neposredno pre dispatch i svakog API read-a; pending delivery stop, nema daljeg čitanja. Secrets prikazati jednom; ne logovati URL auth/token/payload; audit samo bezbedni identifikatori/status. Capability probe endpoint handshaking/test event bez privatnih podataka; offline čuva nacrt konfiguracije, ne tvrdi uspešnu integraciju.

**Mali vertikalni koraci:**

1. Read-only ograničen grant + minimalni API projection -> manual token revoke.
2. Server transaction event plan.confirmed + idempotency -> webhook test receiver.
3. Retry/dedup/replay/signature rotation i field selection -> n8n ili polling capability probe.

**Merljivi kriterijumi prihvatanja:**

1. Token za plan A ne čita plan B, recepte van A ni profile; read-only token ne menja ništa.
2. Jedno offline odobrenje uz 3 upload retry-a daje jedan DomainEvent; neuspešna transakcija daje 0.
3. Receiver dobija isti eventId pri retry-u; tampered body/stari timestamp/unknown key odbijeni su u lokalnom receiver testu.
4. Grant revoke i uklanjanje iz domaćinstva zaustavljaju sledeći API read i pending dispatch; endpoint koji resolve-uje na 127.0.0.1/link-local/private odbija se.
5. UI status pending/retrying/failed/delivered razlikuje prihvatanje događaja od potvrđenog prijema kod primaoca.

**Konkretna verifikacija (planirana):**

1. Local DB transaction tests i dva naloga RLS za grants/subscriptions/events; unique idempotency/revision.
2. Fake HTTP receiver: 2x500 pa 200, timeout, 429 retry-after, redirect-to-private, DNS rebinding simulation i response size limit.
3. Known signature test vector nad tačnim bytes bez stvarnih secret-a; rotation overlap, time injection, replay rejection.
4. Uploader/meal plan repository regression i signed-out/revoked token tests; n8n workflow demo tek posle capability probe, nije izveden ovde.

**Rizici/granice:**

1. Nije potrebno davati n8n-u ceo user JWT niti pristup Supabase tabelama. Standard Webhooks dokumentacija daje obrazac zaštite; nije audit konkretnog budućeg dispatch koda.

**Zavisnosti:** `G010`, `G-SERVER`, `F064`.

**Dokaz izvora:** `web:StandardWebhooks`.

## Pinovani upstream dokazi i odluke o ponovnoj upotrebi

Svaki zaključak ispod je iz navedenog koda na pinovanom commit-u; README nije korišćen kao dokaz funkcije. HEAD je snimak javnog repozitorijuma tokom ovog istraživanja, ne obećanje kompatibilnosti svih izdanja. Cache je izvan Tavli repo-a.

### cookbook

Repo: [https://github.com/nextcloud/cookbook](https://github.com/nextcloud/cookbook), commit `3bea56e33d284a752a8fd9893f901163ff7a4ef5`. Licenca: `AGPL-3.0-only OR AGPL-3.0-or-later`; dokaz COPYING + SPDX zaglavlja svih navedenih PHP fajlova.

- [`lib/Service/RecipeService.php`](https://github.com/nextcloud/cookbook/blob/3bea56e33d284a752a8fd9893f901163ff7a4ef5/lib/Service/RecipeService.php), `RecipeService.addRecipe/parseRecipeFile`: Piše JSON u recipe.json u folderu recepta; parse postavlja id foldera i prolazi checkRecipe. Ovo nije account backup.
- [`lib/Service/JsonService.php`](https://github.com/nextcloud/cookbook/blob/3bea56e33d284a752a8fd9893f901163ff7a4ef5/lib/Service/JsonService.php), `JsonService.isSchemaObject/isSchemaContext`: Proverava schema context http/https i podržava @type niz uz uniqueType opciju.
- [`lib/Helper/Filter/JSON/SchemaConformityFilter.php`](https://github.com/nextcloud/cookbook/blob/3bea56e33d284a752a8fd9893f901163ff7a4ef5/lib/Helper/Filter/JSON/SchemaConformityFilter.php), `SchemaConformityFilter.apply`: Postavlja context i Recipe tip.
- [`lib/Helper/Filter/JSON/FixRecipeYieldFilter.php`](https://github.com/nextcloud/cookbook/blob/3bea56e33d284a752a8fd9893f901163ff7a4ef5/lib/Helper/Filter/JSON/FixRecipeYieldFilter.php), `FixRecipeYieldFilter.apply`: recipeYield može biti null; heuristike za string/niz mogu izabrati broj ili fallback 1. Tavli treba sačuvati dvosmislenost.
- [`lib/Helper/Filter/Output/EnsureNutritionPresentFilter.php`](https://github.com/nextcloud/cookbook/blob/3bea56e33d284a752a8fd9893f901163ff7a4ef5/lib/Helper/Filter/Output/EnsureNutritionPresentFilter.php), `EnsureNutritionPresentFilter.apply`: Dodaje NutritionInformation type čak i kad nema vrednosti: prisutan nutrition objekat nije dokaz nutritivne pokrivenosti.

**Odluka:** Proučeno i citirano; bez kopiranja AGPL koda. Samostalni Dart adapter prema standardu i sintetičkim fixtures.

### mealie

Repo: [https://github.com/mealie-recipes/mealie](https://github.com/mealie-recipes/mealie), commit `471c7936d3c782a431fd2081b632f404cb3dbb1a`. Licenca: `AGPL-3.0-only`; dokaz LICENSE GNU Affero GPL v3 i `pyproject.toml` license="AGPL-3.0-only".

- [`mealie/services/backups_v2/backup_v2.py`](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/services/backups_v2/backup_v2.py), `BackupV2.backup/restore/_copy_data`: database.json + data u ZIP; restore drop_all pa restore i data copy, RESTORE_FILES uključuje administrativnu tajnu. Ne primenjivati na multi-tenant Tavli.
- [`mealie/services/backups_v2/backup_file.py`](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/services/backups_v2/backup_file.py), `BackupContents.validate/schema_version; BackupFile.__enter__`: Validira data folder/database.json, čita alembic_version; extract u privremeni direktorijum. Nije graph/hash/cross-account validator.
- [`mealie/services/backups_v2/alchemy_exporter.py`](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/services/backups_v2/alchemy_exporter.py), `AlchemyExporter.convert_types/clean_rows/dump`: Typed date/time/UUID konverzija i FK provere za restore; održavanje novih datetime kolona je poseban rizik.
- [`mealie/services/migrations/nextcloud.py`](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/services/migrations/nextcloud.py), `NextcloudDir.from_dir/NextcloudMigrator._migrate`: Čita JSON i full.* po direktorijumu, mapira keywords/url/time; grupisanje po slug može spojiti istoimene izvore.
- [`mealie/services/migrations/utils/migration_helpers.py`](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/services/migrations/utils/migration_helpers.py), `extract_zip/safe_local_path/import_image`: Predprovera expanded size i containment slika; ne preuzimati globalni limit kao mobilni Tavli limit.
- [`mealie/schema/recipe/recipe_nutrition.py`](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/schema/recipe/recipe_nutrition.py), `Nutrition`: Opciona string nutrient polja sa camel alias; nema dokaza da svaka vrednost potiče iz potvrđenog food composition proračuna.
- [`mealie/routes/recipe/shared_routes.py`](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/routes/recipe/shared_routes.py), `get_shared_recipe/get_shared_recipe_as_zip`: Lookup tokena i expiry provera, zatim RecipeOut i opcioni ZIP. Tavli treba užu allowlist.
- [`mealie/schema/recipe/recipe_share_token.py`](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/schema/recipe/recipe_share_token.py), `RecipeShareTokenCreate.is_expired/RecipeShareTokenOut`: expires_at podrazumevano +30 dana i is_expired; bibliotečki model nije dokaz Tavli capability pravila.

**Odluka:** AGPL: samo proučavanje obrazaca, bez kopiranih fajlova. Backup/restore pisati kao ovlašćeni domenski snapshot, nikad admin database replacement.

### recipya

Repo: [https://github.com/reaper47/recipya](https://github.com/reaper47/recipya), commit `f8d13a0e9627ca374a01c54de24646adff4bd04e`. Licenca: `unknown` za precizan SPDX only/or-later izbor; `LICENSE` potvrđuje GNU GPL v3 porodicu. Nijedan fajl nije kopiran.

- [`internal/services/files_apps.go`](https://github.com/reaper47/recipya/blob/f8d13a0e9627ca374a01c54de24646adff4bd04e/internal/services/files_apps.go), `Files.extractJSONRecipes/processRecipeFiles/detectApp`: Više import formata; JSON objekat/niz i Mealie fallback, uz početni-byte dispatch. Pattern za registry, ne garancija lossless migracije.
- [`internal/services/files.go`](https://github.com/reaper47/recipya/blob/f8d13a0e9627ca374a01c54de24646adff4bd04e/internal/services/files.go), `exportRecipesJSON/exportRecipesPDF/recipeToPDF`: JSON koristi Recipe.Schema, PDF zasebno renderovanje; pokazuje razliku portable machine formata i čitljivog kuvara.
- [`internal/models/backup.go`](https://github.com/reaper47/recipya/blob/f8d13a0e9627ca374a01c54de24646adff4bd04e/internal/models/backup.go), `UserBackup`: Sadrži DeleteSQL/InsertSQL/ImagesPath/Recipes/UserID. SQL iz tuđeg backupa ne ulazi u Tavli restore ugovor.

**Odluka:** GPL: samo istraživanje i citiranje. Nijedan parser/PDF/SQL kod nije kopiran; Rust naslednik nije auditovan.

### cooklang

Repo: [https://github.com/cooklang/cooklang-rs](https://github.com/cooklang/cooklang-rs), commit `5b8c8dab6d01cfea50a7db1b9a8ea3050117cffc`. Licenca: `MIT`; dokaz LICENSE: Copyright (c) 2023-2024 Francisco J. Sanchez; Cargo.toml license=MIT.

- [`src/scale.rs`](https://github.com/cooklang/cooklang-rs/blob/5b8c8dab6d01cfea50a7db1b9a8ea3050117cffc/src/scale.rs), `Recipe.scale/scale_to_servings/scale_to_yield; Value.scale`: Razdvaja faktor, servings i yield; čuva tekstualne quantities. scale obilazi i cookware/timers i nema Tavli pan geometriju; ne koristiti slepo.
- [`src/model.rs`](https://github.com/cooklang/cooklang-rs/blob/5b8c8dab6d01cfea50a7db1b9a8ea3050117cffc/src/model.rs), `RecipeReference/Ingredient.group_quantities`: Ingredient ima opcioni recipe reference; grupisanje quantities iz references.
- [`src/ingredient_list.rs`](https://github.com/cooklang/cooklang-rs/blob/5b8c8dab6d01cfea50a7db1b9a8ea3050117cffc/src/ingredient_list.rs), `Recipe.group_ingredients/IngredientList.from_recipe`: Razlikuje definicije/references i grupisanje kompatibilnih quantities.
- [`src/analysis/event_consumer.rs`](https://github.com/cooklang/cooklang-rs/blob/5b8c8dab6d01cfea50a7db1b9a8ea3050117cffc/src/analysis/event_consumer.rs), `resolve_reference/conflicting_reference_quantity_error/parse_reference`: Proverava reference i konflikt definicione/reference količine; parse_reference prepoznaje relativne putanje recepta, ne Tavli graph IDs.

**Odluka:** MIT: kompletan src/scale.rs i LICENSE kopirani neizmenjeni samo kao referenca; nema Rust dependency niti runtime integracije. Ostale fajlove samo citirati.

### recipe-scrapers

Repo: [https://github.com/hhursev/recipe-scrapers](https://github.com/hhursev/recipe-scrapers), commit `80266d1db324d58f1426d78facbe2e342662b990`. Licenca: `MIT`; dokaz LICENSE: Copyright (c) 2015 The recipe-scrapers contributors.

- [`recipe_scrapers/_schemaorg.py`](https://github.com/hhursev/recipe-scrapers/blob/80266d1db324d58f1426d78facbe2e342662b990/recipe_scrapers/_schemaorg.py), `SchemaOrg._find_entity/ingredients/_ingredient_to_string/_extract_howto_instructions_text/nutrients`: Parser prepoznaje @graph, više tipova i PropertyValue sastojke, flatten instrukcije; nutrients čisti source strings, ne računa nutriciju niti dokazuje source truth.
- [`recipe_scrapers/_grouping_utils.py`](https://github.com/hhursev/recipe-scrapers/blob/80266d1db324d58f1426d78facbe2e342662b990/recipe_scrapers/_grouping_utils.py), `normalize_fractions/best_match/group_ingredients`: Unicode fraction normalization i fuzzy grouping; similarity nije stvarni OCR confidence niti automatski bezbedan ingredient identity.

**Odluka:** MIT: kompletan _schemaorg.py i LICENSE neizmenjeni kao referenca. Python/extruct i package helpers nisu instalirani ni pokrenuti. Dart adapter sopstvena implementacija; robust type/depth checks obavezni.

### Dopunski primarni izvori (web, bez kopiranog koda)

- **web:FDC** — [USDA FoodData Central API Guide](https://fdc.nal.usda.gov/api-guide/): food search/details, API key i rate-limit odgovori; Licensing odeljak navodi CC0/public domain. Koristiti samo kao kandidat adaptera i data provenance; nisu poslati API zahtevi i nije potvrđena srpska pokrivenost.
- **web:AGRIBALYSE** — [zvanična metodologija ACV](https://doc.agribalyse.fr/documentation/les-donnees/methodologie-acv.md) objašnjava životni ciklus i više indikatora; [dokumentacija programa](https://doc.agribalyse.fr/documentation/) vodi na izdanje podataka. Ne izvoditi lokalni faktor niti dataset licencu iz samog opisa metode. Nema preuzetog dataset-a/koda.
- **web:AndroidWidgets** — [Android App widgets overview](https://developer.android.com/develop/ui/views/appwidgets/overview): native home-screen projekcija i različite veličine. Minimalni OS i konkretni update mehanizam tek u implementaciji.
- **web:AppleWidgets** — [WidgetKit keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date): stranica je pronađena, ali web alat dobija JS wrapper, a markdown link nije uspešno pročitan. Nema citiranja nedostupnog body-ja; precizan refresh budžet ostaje neproveren.
- **web:StandardWebhooks** — [Standard Webhooks](https://www.standardwebhooks.com/): relevantne granice su spoofing, replay, SSRF i pouzdana isporuka. Potpisni payload/queue ovde su predloženi Tavli ugovor, a ne prekopirana/auditovana implementacija standarda.
- [schema.org/Recipe](https://schema.org/Recipe): recipeIngredient može biti tekst i PropertyValue, instructions tekst/HowTo objekti i yield tekst/QuantitativeValue. Izvoz koristiti konzervativni interoperabilni podskup; standard se može menjati i import ne sme zahtevati samo jedan oblik.

## Kolekcija koda

Preuzeta su dva kompletna, neizmenjena korisna upstream modula i njihove MIT licence. Nema proprietary sadržaja, AGPL/GPL koda, fixture recepata ili medija. `scale.rs` zahteva cooklang crate tipove i converter + serde/thiserror; `_schemaorg.py` zahteva recipe_scrapers helpers/settings i extruct. Ovo su kompletni fajlovi iz većih paketa, **nisu samostalno izvršivi paketi**. Dependencies nisu instalirane. Ostatak biblioteka nije vendorizovan niti je kod povezan sa Tavli runtime-om.

Posebno: Cooklang scale obilazi i timers/cookware i nema eksplicitnu proveru svakog Tavli finite/positive uslova. SchemaOrg parser sadrži heurističko matching/flattening i type assumptions. Nijedan fajl nije bezuslovna preporuka za direktno izvršavanje. Korisnost je pregledna referenca za ugovore, fixture matricu i sopstvenu Dart implementaciju.

- `research/reference-code/F/cooklang/scale.rs` ← [src/scale.rs](https://github.com/cooklang/cooklang-rs/blob/5b8c8dab6d01cfea50a7db1b9a8ea3050117cffc/src/scale.rs); SHA-256 `1cee050a49de136908d92a68ed810fef7239a4ab031a78d063d78edd8439f8a6`; licenca `research/reference-code/F/cooklang/LICENSE`.
- `research/reference-code/F/cooklang/LICENSE` ← [LICENSE](https://github.com/cooklang/cooklang-rs/blob/5b8c8dab6d01cfea50a7db1b9a8ea3050117cffc/LICENSE); SHA-256 `f642ae2627c79e63a5d624125bbd02da6868aa8ddfbb1b7e98687c0f8d3db592`; licenca `research/reference-code/F/cooklang/LICENSE`.
- `research/reference-code/F/recipe-scrapers/_schemaorg.py` ← [recipe_scrapers/_schemaorg.py](https://github.com/hhursev/recipe-scrapers/blob/80266d1db324d58f1426d78facbe2e342662b990/recipe_scrapers/_schemaorg.py); SHA-256 `70b6bc5257d283f7fce437685a75538b50410f0df5c6f684e6a057f343ce5f70`; licenca `research/reference-code/F/recipe-scrapers/LICENSE`.
- `research/reference-code/F/recipe-scrapers/LICENSE` ← [LICENSE](https://github.com/hhursev/recipe-scrapers/blob/80266d1db324d58f1426d78facbe2e342662b990/LICENSE); SHA-256 `de5dd1698c31b1b789b2859c8ea4b637dff98ca7bce95eb282f2492603c3c8f9`; licenca `research/reference-code/F/recipe-scrapers/LICENSE`.

## Migracioni redosled i rizici kompatibilnosti

1. Dogovoriti revision/ingredient provenance sa A/E/C, zatim backward decoder-e; tek onda nova schema i serializacija. Stari RecipeSource enum ne dopunjavati bez migracije svih čitača.
2. F022 prenosivost pre F023; F065 ima sopstveni verzionisani format i ne zavisi od lossless schema.org round-trip-a. `SyncEntity.toRemote` nije stabilan dugoročni archive format.
3. Sve reference remapirati: plan entries, recipe/version IDs i embedded snapshots, shopping sources/contributions, sourceShoppingItemId, allocation foreign keys i asset paths. Sačuvati civil dates odvojeno od UTC timestamps.
4. Snapshot-only/deleted recipe sadržaj mora preživeti backup i imati svoje slike. Nikad tiho skratiti više istorije nego što izvor stvarno sadrži; postojeći sistem već ima cap 30.
5. Derived estimates, trial status i consistency report su vezani za revision/metod, ne globalno Recipe ID. AI izmena invalidira aktuelne derived podatke i ne prepisuje source claims.
6. Sharing/event projekcije ne smeju serijalizovati ceo Recipe.toJson ili user profile po automatizmu. Pravo iz arhive ne postaje novo pravo pristupa; restore destination proverava aktivnu autorizaciju.
7. Svaki feature čuva phone/wide/2x text i offline ponašanje; server/device zavisni koraci nude eksplicitno unavailable/pending stanje. Nema uklanjanja postojećih animacija i efekata.

## Otvorena pitanja

- Tačno izdanje/fixture skup za Mealie/Paprika/Nextcloud migraciju mora se pinovati u implementacionoj specifikaciji; pregledan je javni HEAD, ne instalirana aplikacija.
- FDC srpski food/brand matching, stvarna lokalna pokrivenost i retention metod nisu validirani; korišćena je dokumentacija, bez API zahteva.
- AGRIBALYSE tačno dataset izdanje, license/attribution uslovi i reprezentativnost Srbije nisu potvrđeni; nema preuzetih faktora.
- Widget OS minimumi, App Groups/entitlements i real-device refresh ponašanje zahtevaju platform probe; Apple dokumentacija nije dala čitljiv body u web alatu.
- Backup maksimalna veličina, memory budget, snapshot/export server koordinacija i opcioni encrypted archive UX zahtevaju poseban spec; same SQLite kopije nisu potpuni backup.
- Gubitak field strukture pri schema.org round-trip-u mora biti prikazan; generičan format ne čuva sve Tavli category/note/ID semantike.
- Canonical revision hash i stable ingredient IDs moraju biti zajednički usaglašeni sa A/E/C pre menjanja schema; trenutno ne postoje.
- Public share/webhook hosting, kvote i background worker pouzdanost nisu testirani; nema potvrđene n8n integracije niti produkcijskih poziva.

- Recipya: GPL v3 porodica jeste potvrđena, ali precizan only/or-later grant nije; konzervativni SPDX status ostaje unknown i nema kopiranog koda.

## Izvršena validacija ovog prolaza

Manifest je generisan kao JSON i proverava se parsiranjem, obaveznim poljima i tačnošću 15 ID-jeva iz streams.json. Sva četiri kopirana fajla proverena su byte-for-byte prema pinovanom cache-u i SHA-256; dva koda imaju svoju kompletnu MIT licencu sa originalnim copyright-om. Dodatni provenance dokument u reference-code/F/ opisuje zavisnosti i ograničenja. Flutter/backend/upstream testovi nisu izvršeni jer aplikacija nije menjana i upstream se ne pokreće. Ovo istraživanje ne tvrdi da je bilo koji od 15 predloga implementiran.
