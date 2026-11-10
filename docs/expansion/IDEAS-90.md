# Tavli: 90 predloga iz sličnih projekata i njihovih obrazaca

Datum istraživanja: 9. novembar 2026.
Osnova za poređenje: `anjahubac/tavli`, `main`, commit `1eca2c3d14fb5dd9b25a42958aa018c8d8dfbb94`.

Ovo je izbor 30 relevantnih uzora i po jedne konkretne adaptacije za Tavli, prema svakodnevnoj koristi, uklapanju u postojeću arhitekturu i složenosti. Nije objektivna rang-lista svih aplikacija na tržištu. Funkcije izvora proverene su u zvaničnim opisima, dokumentaciji i README fajlovima; aplikacije nisu pojedinačno instalirane niti su njihovi backend sistemi auditovani. Predlozi za Tavli su naša procena, a ne tvrdnja da izvori imaju identično ponašanje.

P1 = prvi ciklus posle stabilizacije postojeće specifikacije 010; P2 = naredni ciklus uz navedene zavisnosti; P3 = kasnije proširenje. Redni broj je identifikator predloga, ne ocena kvaliteta izvora.

## Izbor 30 uzora i adaptacija

| ID | Izvor | Predlog za Tavli | Prioritet | Veza sa postojećim kodom / zavisnost |
|---|---|---|---|---|
| 01 | [Mealie](https://github.com/mealie-recipes/mealie) | Uvoz recepta sa URL-a, sa poreklom i pregledom pre čuvanja. Prvo strukturisani podaci stranice; AI samo kao rezervni način. | P1 | Proširiti postojeći unos i AI preview; sačuvati preko RecipeRepository. Potrebna zaštita serverskog preuzimanja URL-ova. |
| 02 | [Tandoor](https://docs.tandoor.dev/features/automation/) / [GitHub](https://github.com/TandoorRecipes/recipes) | Rečnik potvrđenih sinonima sastojaka i jedinica, npr. beli luk / češnjak. | P1 | Nadograditi ingredientKey i postojeće grupisanje količina. Naziv i fizička kompatibilnost ostaju odvojene provere. |
| 03 | [Paprika](https://www.paprikaapp.com/) | Sačuvane kombinovane pretrage: do 30 minuta, sa piletinom, bez određenog sastojka. | P1 | Nadograditi postojeći spisak/pretragu recepata i repozitorijum; bez zasebne biblioteke. |
| 04 | [SuperCook](https://apps.apple.com/us/app/supercook-recipe-by-ingredient/id1477747816) | „Mogu danas da skuvam”: recepti za koje postoje potvrđene količine, uz zaseban prikaz „nedostaje 1–2 sastojka”. | P1 | Koristiti postojeće demandFor/allocateSupply i ostavu. Ne predstavljati nepoznatu količinu kao dovoljnu. |
| 05 | [Samsung Food+](https://samsungfood.com/food-plus/) | „Potroši prvo”: prioritet receptima koji koriste namirnice pred istekom. | P1 | Datum isteka već postoji u PantryItems; prvo završiti ekran i potvrđivanje ostave iz 010. |
| 06 | [Grocy](https://grocy.info/) / [GitHub](https://github.com/grocy/grocy) | Minimalna zaliha za redovne namirnice i predlog dopune kad padne ispod praga. | P2 | Nadograditi PantryRepository; predlog dopune prikazati i potvrditi, bez dupliranja nabavke. |
| 07 | [AnyList](https://blog.anylist.com/2026/01/meal-plan-update/) | Šabloni nedelje: sačuvaj uspešan plan, primeni na nove datume i prilagodi porcije. | P1 | MealPlanRepository i postojeći pregled odobrenja; novi ID-jevi izvora i preračun nabavke. |
| 08 | [Umami](https://www.umami.recipes/) | Režim kuvanja sa ček-listom sastojaka i koraka. | P1 | Nadograditi RecipeView i planirani cooking flow iz 010. Sačuvati postojeću opciju „Ne gasi ekran”. |
| 09 | [Crouton](https://crouton.app/) | Više imenovanih tajmera vezanih za korake, npr. „pirinač” i „riba”. | P1 | Nadogradnja režima kuvanja; odrediti ponašanje pri zaključavanju/gašenju aplikacije. |
| 10 | [Bring!](https://www.getbring.com/en/features) | Fotografija, brend i napomena uz stavku nabavke da član domaćinstva kupi pravi proizvod. | P1 | ShoppingRepository i postojeći outbox/photo storage obrasci; migracija i pravila pristupa za nove podatke. |
| 11 | [KitchenOwl](https://github.com/TomBursch/kitchenowl) | Zajednička lista sa brzim ažuriranjima između članova i jasnim stanjem sinhronizacije. | P2 | Nastavak 008/009: pozivnice, članstvo, realtime i konflikti. KitchenOwl navodi delimičnu offline podršku; Tavli zadržava svoj offline model. |
| 12 | [Eat This Much](https://help.eatthismuch.com/help/how-do-i-automate-leftovers) | Povezani ostaci: večera za četiri osobe postaje dva ručka narednog dana, bez ponovne kupovine sastojaka. | P2 | Proširiti izvore potražnje i snimke obroka. Potražnja za sastojcima nastaje pri kuvanju, ne pri svakoj konzumaciji. |
| 13 | [Plan to Eat](https://learn.plantoeat.com/help/app-freezer-cooking) | Zamrznuti gotovi obroci: porcije, datum zamrzavanja i podsetnik za pripremu/odmrzavanje. | P2 | Razlikovati zalihu gotovog obroka od sirovih sastojaka; postojeći plan i ostava ostaju nosioci podataka. |
| 14 | [Sorted Sidekick](https://help.sortedfood.com/hc/en-gb/articles/4638394094482-What-do-I-get-from-Sidekick) | Grupe od 3–5 jela koja zajedno potroše kupljena pakovanja namirnica. | P2 | Nadograditi rangiranje plana; potrebni podaci o pakovanjima. Konačne količine računati kodom. |
| 15 | [MealBoard](https://www.mealboard.com/features.html) | Podsetnici za pripremu pre obroka, npr. potapanje pasulja ili mariniranje. | P2 | Dodati vremenske obaveze na postojeći obrok, uz lokalne notifikacije i izbor korisnika. |
| 16 | [OurGroceries](https://www.ourgroceries.com/user-guide) | Glasovni unos nabavke na srpskom: „dodaj dva litra mleka”, sa pregledom pre upisa. | P2 | Isti servis za unos kao kucanje; proveriti dostupnost srpskog prepoznavanja govora na ciljnim platformama. |
| 17 | [Open Food Facts](https://github.com/openfoodfacts/openfoodfacts-server) / [API](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/) | Barkod dopunjava naziv i pakovanje proizvoda, uz ručni unos ako proizvod ne postoji. | P2 | Integracioni adapter + keš; korisnik potvrđuje pre dodavanja u ostavu. Pokrivenost Srbije nije proverena ovim istraživanjem. |
| 18 | [Open Prices](https://github.com/openfoodfacts/open-prices) / [Dokumentacija](https://openfoodfacts.github.io/open-prices/) | Cene sa prodavnicom, datumom i dokazom iz računa/etikete; istorija i procena pokrivenosti korpe. | P2 | Nova vertikala za cene. Prvo proveriti dostupnost relevantnih podataka u Srbiji i vezu namirnica–proizvod–pakovanje. |
| 19 | [RecipeSage](https://github.com/julianpoy/RecipeSage) | Uvoz recepta iz PDF-a ili nalepljenog teksta u isti postojeći pregled pre čuvanja. | P2 | Proširiti postojeći foto/AI unos; sačuvati poreklo i nejasne količine ostaviti za proveru. |
| 20 | [CookBook](https://cookbookmanager.com/features/translate-recipes) | Prevod uvezenog recepta na srpski uz očuvan original. | P2 | Koristiti postojeću istoriju verzija; ne menjati brojeve i mere bez posebne potvrde. Podrška izvora za srpski nije pretpostavljena. |
| 21 | [Recipe Keeper](https://www.recipekeeperonline.com/) | Izvoz odabranih recepata u porodični PDF kuvar. | P3 | Read-only izvoz iz RecipeRepository; korisnik bira šta deli. |
| 22 | [Nextcloud Cookbook](https://github.com/nextcloud/cookbook) | Prenosivi recepti u schema.org/Recipe JSON formatu i povratni uvoz. | P1 | Adapter za postojeći Recipe model, bez promene unutrašnjeg modela samo radi izvoza. Standardni JSON nije puna rezervna kopija naloga. |
| 23 | [Recipya](https://github.com/reaper47/recipya) | Uvoz postojećih kolekcija iz drugih aplikacija sa izveštajem o duplikatima i preskočenim poljima. | P3 | Izgraditi na uvozu/izvozu iz 22. Recipya Go najavljuje prelazak na Rust; koristiti kao uzor migracionog toka. |
| 24 | [Copy Me That](https://chromewebstore.google.com/detail/copy-me-that/lgjinjcobiflbbnhenlfkcjpeeacklfl) | Sačuvaj recept tokom pregledanja kroz dodatak za browser ili sistemski Share meni. | P2 | Isti tok URL importa iz 01; ne praviti novi sistem čuvanja recepata. |
| 25 | [Pestle](https://pestlechef.app/) | Uvoz recepta iz objave na društvenim mrežama sa izvornim linkom i obaveznim pregledom. | P3 | Tek posle stabilnog importa teksta, URL-a i fotografija; nepotpun sadržaj se ne predstavlja kao pouzdano rekonstruisan recept. |
| 26 | [Mela](https://mela.recipes/help/) | Praćenje odabranih kulinarskih blogova kroz RSS, uz eksplicitno čuvanje izabranog recepta. | P3 | Odvojiti predloge iz feeda od korisnikove zbirke; koristiti URL importer. |
| 27 | [Cooklang / CookCLI](https://github.com/cooklang/cookcli) / [Vodič](https://cooklang.org/guides/shopping/) | Podrecepti: sos ili testo se koristi u više recepata i pravilno ulazi u zbir nabavke. | P3 | Proširiti strukturu recepta i izračun potražnje; sprečiti kružne reference i zadržati odobrene snimke. |
| 28 | [kitshn](https://github.com/kitshn-app/kitshn) | Povezivanje sastojaka sa korakom u kome se koriste, tako da kuvar vidi količine uz taj korak. | P2 | Nadograditi model koraka ili dodati vezu sa stabilnim ID-jevima sastojaka; prikaz i fallback za stare recepte. |
| 29 | [SideChef](https://www.sidechef.com/download/) | Fotografija ili kratak video uz pojedinačan korak pripreme. | P3 | Nadogradnja režima kuvanja; prvo završiti razliku između originalnog dokumenta i fotografije jela. |
| 30 | [BigOven](https://support.bigoven.com/hc/en-us/articles/209710913-How-do-I-find-Use-Up-Leftovers) | Brza akcija „Potroši ove 3 namirnice”, bez obaveznog popunjavanja cele ostave. | P1 | Drugi ulaz u postojeću pretragu/rangiranje iz 04, a ne odvojeni preporučivač. |

## Preduslovi pre širenja

1. Završiti proveru celog toka iz specifikacije 010 i otvorene UX/offline/migracione zadatke. README i roadmap trenutno zaostaju za delimično implementiranim kodom.
2. Ograničenja ishrane moraju pratiti sve AI korake i konačnu proveru sastojaka. Trenutno se `request.wishes` šalje rasporedu, ali se ne šalje generisanju sažetaka novih recepata.
3. Za distribuirano izdanje sa zajedničkim AI ključevima: serverski posrednik, provera naloga, ukupni rok i budžet pokušaja. Obezbediti da prekid zaista prekine aktivan poziv.
4. CI dopuniti lokalnim Supabase testovima prava pristupa i migracija; postojeći workflow pokreće analizu i Flutter testove.

## Redosled prvog ciklusa

Najpre **02 → 03 → 04/30 → 05**, jer stvaraju jedinstvenu osnovu sastojaka, pretrage i ostave. Potom **01 → 22**, za unos i prenosivost recepata. Zatim **07 → 08 → 09 → 10**, kao nezavisne funkcije, svaka proverena pre naredne. Ovo je predlog redosleda; nije procena trajanja.

Ne duplirati već postojeće skaliranje porcija, kalendar, AI preview, verzionisanje recepata, outbox i sinhronizaciju. Svaki novi tok čita istu lokalnu bazu i piše preko postojećih repozitorijuma. Nove tabele/kolone traže Drift migraciju, serversku migraciju, RLS i proveru izolacije dva naloga prema pravilima repozitorijuma.

## Minimalni kriterijumi prihvatanja za prvi ciklus

- **01, URL import:** poznata test stranica daje očekivane sastojke i izvor; neispravan URL ne pravi recept; nejasni podaci ostaju označeni za pregled. Serverski importer ne sme pristupati internim adresama.
- **02, sinonimi:** dve potvrđene varijante iste namirnice se spoje; različite vrste mleka i nekompatibilne mere ostaju odvojene. Promena rečnika ne menja tiho odobrene snimke ranijih planova.
- **03, pretraga:** sačuvan filter vraća isti skup nakon ponovnog pokretanja i radi offline; nedostajući podatak se ne tretira kao pozitivan pogodak.
- **04/30, ostava i brzi izbor:** recept zahteva 600 g brašna, ostava ima 400 g; prikazuje manjak od 200 g. Ista zaliha ne može da pokrije dva istovremeno odabrana obroka dvaput.
- **05, rokovi:** uz ubrizgan sat redosled predloga je ponovljiv; podatak o roku ili količini koji nedostaje ostaje nepoznat, ne procenjuje se kao siguran.
- **07, šabloni:** kopiranje na nove datume pravi nove identitete; za duple porcije nabavka se preračuna; stari plan i kupljene stavke ostaju očuvani.
- **08, kuvanje:** čekiranje koraka ne menja recept ili stanje ostave; izlazak oslobađa wake lock; prikaz je upotrebljiv na telefonu i širokom ekranu.
- **09, tajmeri:** dva tajmera rade nezavisno; prekid jednog ne prekida drugi; ponašanje pri gašenju aplikacije je eksplicitno prikazano i provereno na uređaju.
- **10, fotografija stavke:** offline dodatak se sinhronizuje nakon povratka veze; drugi nalog nema pristup fotografiji; promena brenda ne menja traženu količinu.
- **22, JSON:** izvoz–uvoz test zadržava naziv, sastojke, mere i korake; nedostajuća polja i duplikati prikazuju izveštaj. Fotografije, planovi, verzije i ostava zahtevaju poseban format pune rezervne kopije.

## Granice istraživanja

Pokrivenost Open Food Facts i Open Prices za srpske prodavnice i proizvode nije izmerena. Ne treba obećavati „najjeftiniju prodavnicu” pre provere datuma cena, veličina pakovanja i potpunosti poređene korpe. U prvoj verziji prikazati stvarno pokrivene stavke, izvor i datum.

Izbor je namenjen adaptaciji ponašanja u Tavlijevoj arhitekturi. Nijedan tuđ kod nije kopiran i nijedna predložena funkcija nije ovim istraživanjem implementirana.

## Drugi izbor: predlozi 31–60

Ovaj nastavak dodaje 30 drugih funkcija i nadogradnji. Provereni uzori navedeni su po oblasti. Konkretno ponašanje Tavlija je naš predlog: ne tvrdimo da svaki izvor već ima svaku navedenu adaptaciju. Posebno su dodeljivanje nabavke, glasanje, objašnjenja preporuka, provera skena i paralelni tok kuvanja predlozi za naš proizvod.

### Planiranje

Uzori: [AnyList Queue](https://help.anylist.com/articles/meal-plan-queue/), [AnyList plan i beleške](https://help.anylist.com/articles/getting-started/), [Mealie pravila planiranja](https://mealie.io/documentation/getting-started/features/), [Eat This Much podešavanje vremena](https://blog.eatthismuch.com/eat-this-much-tutorial-6-editing-and-creating-custom-meal-types/).

| ID | Predlog | Konkretno ponašanje | Prioritet |
|---|---|---|---|
| 31 | Red „Želim uskoro da kuvam” | Recepti čekaju raspoređivanje bez datuma, a korisnik ih prevlači u plan kad odluči. | P1 |
| 32 | Pravila po danima | Npr. ponedeljak bez mesa, petak riba; generator poštuje pravilo, korisnik može eksplicitno da ga promeni. | P2 |
| 33 | Obrok van kuće | „Restoran”, „kod roditelja”, „preskačem”: termin je zauzet, ali ne stvara potražnju za namirnicama. | P1 |
| 34 | Raspoloživo vreme po danu | Utorak najviše 20 minuta aktivnog rada, nedelja do 90; razlikovati aktivno i ukupno vreme. | P1 |
| 35 | Kontrola ponavljanja kroz više nedelja | Koristiti istoriju stvarno skuvanih jela, ne samo nazive u tekućem nacrtu; korisnik bira dozvoljenu učestalost. | P2 |

### Ostava

Uzori: [Grocy tutorial](https://github.com/grocy/grocy-docs/blob/master/tutorials/food.md), [Grocy istorija razvoja](https://grocy.info/changelog), [Cooklang pantry](https://cooklang.org/guides/pantry/). Dnevnik otpada je naša nadogradnja inventara.

| ID | Predlog | Konkretno ponašanje | Prioritet |
|---|---|---|---|
| 36 | Lokacije namirnica | Frižider, zamrzivač, ostava; filtriranje i premeštanje iste zalihe bez duplog upisa. | P1 |
| 37 | Otvoreno pakovanje | Evidentirati datum otvaranja i rok koji korisnik unese ili potvrdi sa deklaracije, odvojeno od fabričkog roka. | P2 |
| 38 | Odvojene ture iste namirnice | Dva mleka imaju različite rokove; za raspodelu se prvo predlaže raniji potvrđeni rok. | P2 |
| 39 | Brza provera inventara | „Imam”, „nestalo”, „ne znam količinu”; potvrđen podatak ima datum provere. | P1 |
| 40 | Dnevnik bačene hrane | Količina, razlog i opcioni trošak; razlikovati bačeno od pojedeno da buduće dopune budu korisnije. | P2 |

### Nabavka

Uzori: [Tandoor supermarket ordering](https://docs.tandoor.dev/features/shopping/), [Grocy rounding i jedinice](https://grocy.info/changelog), [AnyList cene i tekući zbir](https://help.anylist.com/articles/getting-started/), [AnyList favorites/master list](https://www.anylist.com/features). Dodeljivanje stavki je naša nadogradnja deljenog domaćinstva.

| ID | Predlog | Konkretno ponašanje | Prioritet |
|---|---|---|---|
| 41 | Redosled prema konkretnoj prodavnici | Isti spisak menja redosled kategorija prema izabranom rasporedu rafova. | P1 |
| 42 | Kupovina celih pakovanja | Za 750 g pirinča i poznato pakovanje od 500 g predložiti 2 pakovanja, uz jasno prikazan višak od 250 g. | P2 |
| 43 | Budžet tokom kupovine | Zbir unetih cena kupljenog i procena preostalog; nepoznate cene ostaju odvojene od potvrđenog zbira. | P2 |
| 44 | Ko kupuje koju stavku | Član preuzima pojedine stavke, a ostali vide ko ih kupuje; preuzimanje nije isto što i potvrda kupovine. | P2 |
| 45 | Lista redovne kupovine | „Moja osnovna korpa” sa omiljenim artiklima koje korisnik bira za sledeću kupovinu, nezavisno od minimalne zalihe. | P1 |

### Recepti i podaci

Uzori: [Cronometer recept i porcije](https://support.cronometer.com/hc/en-us/articles/360018510311-Create-Custom-Recipe), [Mealie organizacija i alati](https://mealie.io/documentation/getting-started/features/), [Mealie klijent sa cooking timeline](https://github.com/Walfrosch92/Mealie-Recipes-APP), [Bring sezonske ideje](https://www.getbring.com/en/features). Uporedni pregled skena je naša nadogradnja postojećeg AI preview-a.

| ID | Predlog | Konkretno ponašanje | Prioritet |
|---|---|---|---|
| 46 | Nutritivne vrednosti po porciji | Proračun iz poznatih podataka o sastojcima; navesti izvor i pokrivenost, ne izmišljati vrednosti modelom. | P2 |
| 47 | Dnevnik kuvanja | Datum, rezultat, fotografija i lična beleška odvojeni od teksta recepta i istorije njegovih izmena. | P1 |
| 48 | Sezonski izbor | Lokalno prilagođen kalendar namirnica utiče na predloge; sezonski podatak ima definisan region i poreklo. | P2 |
| 49 | Sken uz izdvojeni tekst | Uporedni prikaz originalne fotografije i parsiranog recepta; označiti neprepoznate/nevalidne količine bez izmišljene ocene pouzdanosti. | P1 |
| 50 | Oprema koju posedujem | Recepti i planovi filtriraju se prema potrebnoj rerni, blenderu i drugoj opremi. | P2 |

### Kuvanje

Uzori: [Paprika hands-free i konverzije](https://www.paprikaapp.com/), [CookBook alati za kuvanje](https://cookbookmanager.com/), [SuperMealPlanner batch cooking](https://github.com/GeiserX/SuperMealPlanner). Raspored paralelnih koraka, merenje vremena i pomoć tokom izvršavanja su naše adaptacije; nisu tvrdnje o identičnim funkcijama u svim izvorima.

| ID | Predlog | Konkretno ponašanje | Prioritet |
|---|---|---|---|
| 51 | Temperature i režim rerne | Jasno razlikovati °C/°F i ventilator/statički režim; ne menjati temperature automatski bez prikaza promene. | P2 |
| 52 | Paralelna priprema više jela | Pregled kada počinje koji korak i gde se jela takmiče za istu rernu ili ringlu; korisnik potvrđuje raspored. | P3 |
| 53 | Glasovno vođenje kuvanja | „Sledeći korak”, „ponovi”, „pokreni tajmer”; odvojeno od prethodno predloženog glasovnog unosa nabavke. | P2 |
| 54 | Moje stvarno vreme pripreme | Posle nekoliko kuvanja prikazati lični vremenski raspon; pauze i rad u pozadini ne računati slepo kao aktivan rad. | P2 |
| 55 | Pitanje o tekućem koraku | AI dobija trenutni korak, recept i potvrđena ograničenja; pomoć se ne upisuje kao trajna izmena recepta. | P3 |

### Domaćinstvo i svakodnevni pristup

Uzori: [Mealie households i calendar feed](https://mealie.io/documentation/getting-started/features/), [SuperMealPlanner personalizacija domaćinstva](https://github.com/GeiserX/SuperMealPlanner), [Paprika widgets](https://www.paprikaapp.com/), [AnyList kalendar](https://www.anylist.com/meal-planning). Glasanje, promenljiv sastav gostiju i proverljivo objašnjenje izbora su naši predlozi.

| ID | Predlog | Konkretno ponašanje | Prioritet |
|---|---|---|---|
| 56 | Glasanje za predloge | Ukućani biraju između nekoliko jela; rezultat glasanja pomaže planeru, ali ne nadjačava obavezna ograničenja. | P2 |
| 57 | Ko jede ovaj obrok | Broj prisutnih i gostiju po konkretnom terminu, umesto jedne stalne vrednosti za celo domaćinstvo. | P2 |
| 58 | „Zašto je ovo predloženo?” | Prikaz stvarno izračunatih razloga: raspoložive količine, potvrđeni rok, vreme i poslednje kuvanje. | P1 |
| 59 | Widget „Danas” | Obrok i preostala nabavka na početnom ekranu, uz datum poslednjeg osvežavanja. | P2 |
| 60 | Pretplata na kalendar | Read-only ICS feed za Google/Apple Calendar, sa opozivom privatnog linka i bez dupliranja događaja. | P2 |

Iz ovog drugog izbora prvi bih razradio 31, 33, 34, 39, 41, 47 i 58. 58 traži da informacije o izboru budu proverljive u aplikaciji; slobodno AI obrazloženje nije dokaz da je ograničenje poštovano. 44/56/57 zavise od članstva i prava pristupa iz 008, a deljena istovremena upotreba zahteva rad iz 009. 42/43 traže podatke o pakovanjima i cenama i ostaju nadogradnja postojećeg obračuna potražnje.

## Treći izbor: predlozi 61–90, bez ponavljanja prvih 60

Proverene su sve prethodne stavke. Ovaj izbor uvodi druge korisničke radnje i ishode; veza sa ranijim funkcijama navedena je radi razgraničenja. Uzori nisu dokaz da svaki navedeni proizvod već implementira tačno naš predlog. Funkcije označene kao naše kompozicije predstavljaju ideje za Tavli, a dostupnost lokalnih komercijalnih integracija nije proverena.

| ID | Predlog | Konkretno ponašanje | Razlika u odnosu na prethodnih 60 |
|---|---|---|---|
| 61 | Poređenje nacrta planova | Prikaži dva ili tri nacrta paralelno, sa uporedivim troškom, brojem kupovina i aktivnim vremenom; prihvati jedan. | Poređenje celih scenarija, umesto šablona nedelje (07) ili objašnjenja pojedinačnog predloga (58). |
| 62 | Poništi izmenu celog plana | Jednom akcijom vrati poslednju potvrđenu izmenu plana i povezanu potražnju; postojeće kupovine se ponovo usklađuju, ne brišu se. | Undo plana kao celine, umesto postojeće istorije izmena pojedinačnog recepta. |
| 63 | Više nezavisnih domaćinstava | Prebacivanje između sopstvenog stana, vikendice ili drugog domaćinstva bez mešanja planova, ostave i nabavke. | Odvojeni prostori podataka, umesto više članova jedne zajedničke liste (11). |
| 64 | Privremeno deljenje bez naloga | Jedan recept dostupan preko opozivog linka sa rokom isteka; bez pristupa ostatku zbirke. | Kontrolisan pristup sa opozivom, umesto PDF kuvara (21) ili trajnog članstva (11). |
| 65 | Potpuna rezervna kopija i obnova | Obnovi recepte, slike, istoriju, planove, ostavu i veze između njih iz verzionisane arhive, uz izbor odredišta. | Oporavak celog prostora podataka, umesto izvoza samih recepata u standardni JSON (22). |
| 66 | Razduživanje zajedničkih troškova | Zabeleži ko je platio kupovinu, izuzmi lične artikle i izračunaj ko kome duguje. | Finansijsko poravnanje između ljudi, umesto budžeta jedne korpe (43). |
| 67 | Slanje korpe online prodavnici | Poveži stavke sa proizvodima, pregledaj zamene i izvezi korpu podržanom trgovcu; kupovinu potvrđuje korisnik. | Izvršiv tok poručivanja, umesto samog poređenja cena (18). |
| 68 | Kartice lojalnosti | Sačuvane barkod kartice prodavnica dostupne uz otvorenu nabavku. | Nova funkcija za kasu; ne odnosi se na barkod identifikaciju namirnice (17). |
| 69 | Podsetnik blizu prodavnice | Uz dozvolu uređaja, obavesti kada si blizu izabrane radnje i imaš nekupljene stavke. | Podsetnik na osnovu lokacije, umesto pripremnih podsetnika vezanih za obrok (15). |
| 70 | Stvarna isplativost obilaska prodavnica | Uporedi jednu i više radnji uz cenu prevoza i dozvoljeno vreme obilaska; prikaži pretpostavke. | Trošak puta i više stanica, umesto najnižeg zbira cena artikala. |
| 71 | Kuponi i uslovne akcije | Cena važi uz karticu, dve kupljene jedinice ili do određenog datuma; sistem primenjuje uslove eksplicitno. | Izvršavanje pravila promocije, umesto beleženja jedne cene (18). |
| 72 | Povratna ambalaža i kaucije | Evidencija flaša/gajbi, uplaćene kaucije i vraćene ambalaže; nije ograničeno na jedan lokalni sistem. | Obrnuti tok vraćanja i novca, umesto zalihe hrane ili kupljenih stavki. |
| 73 | Poravnanje kupovine sa računom | Iz fotografije/digitalnog računa predloži stvarno kupljene artikle i količine, poveži sa spiskom i traži potvrdu. | Potvrda realizovane kupovine i dopune ostave, umesto računa kao dokaza pojedinačne cene (18). |
| 74 | Težina posude i neto sadržaj | Zapamti težinu prazne tegle; korisnik unese ukupnu težinu, a sistem izračuna preostali sadržaj. | Poseban obračun tare, umesto procene „imam/nemam” ili brojanja pakovanja. |
| 75 | Stvarni prinos nakon kuvanja | Izmeri gotov lonac/jelo i evidentiraj porcije u gramima prema konačnoj masi. | Prinos i porcionisanje gotovog jela, umesto skaliranja ulaznih sirovina ili nutritivnog prikaza (46). |
| 76 | Povezivanje sa kompatibilnom vagom | Preuzmi izmerenu masu direktno sa podržane Bluetooth vage i uporedi je sa traženom masom sastojka. | Integracija sa mernim uređajem; računanje tare (74) radi i bez nje. |
| 77 | Povezivanje sa termometrom | Prikaz stvarnog očitavanja kompatibilne sonde i obaveštenje na zadatoj vrednosti. | Praćenje merene temperature, umesto vremenskog tajmera (09) ili konverzije režima rerne (51). |
| 78 | Slanje postavki pametnoj rerni | Uz podržan API i potvrdu korisnika, pošalji režim i temperaturu odabranog koraka. | Upravljanje podržanim uređajem, umesto filtriranja po opremi (50) i samog prikaza temperature (51). |
| 79 | Kalkulator veličine kalupa | Preračun sastojaka prema geometriji kalupa i željenoj visini testa, uz prikaz pretpostavki. | Geometrija pečenja, umesto uobičajenog menjanja broja porcija. |
| 80 | Pekarski procenti | Prikaz recepta za testo prema masi brašna, ciljnoj masi i hidrataciji, uključujući brašno/vodu iz startera kad su poznati. | Specijalizovana formula za testo, umesto podrecepata (27) ili opšteg skaliranja. |
| 81 | Put učenja kuvanja | Niz kratkih zadataka po nivou: veština, praktičan zadatak, proverljiv kriterijum i napredak. | Kurikulum kroz više sesija, umesto vođenja kroz jedan recept. |
| 82 | Kulinarski rečnik | Dodir na „deglazirati” ili „blanširati” otvara kratko uređeno objašnjenje i primer. | Referentni pojmovnik, umesto AI razgovora o tekućem koraku (55) ili video-priloga (29). |
| 83 | Dostupnost konkretnih proizvoda | Obeleži da li je proizvod dostupan za određenu poslovnicu/termin, sa vremenom provere. | Stanje prodavnice, umesto stanja kućne ostave ili cene proizvoda. |
| 84 | Provera unutrašnje doslednosti recepta | Pronađi namirnicu pomenutu u koracima koja nedostaje u spisku, ili količinu koja se ne slaže; prikaži problem autoru. | Semantička kontrola sadržaja svakog recepta, umesto vizuelne provere OCR skena (49). |
| 85 | Status testiranog recepta | Razlikuj uvezen/generisan recept od verzije koju je neko zaista testirao za određene porcije i opremu. | Dokaz testiranja vezan za tačnu verziju i uslove, umesto ličnog dnevnika kuvanja (47). |
| 86 | Procena ekološkog uticaja | Prikaži procenu za sastojke sa poznatim podacima i jasno označi nepokriveni deo; navedi metod i izvor. | Ekološki pokazatelj, umesto nutritivnih vrednosti (46) ili količine bačene hrane (40). |
| 87 | Ponudi višak hrane | Napravi ponudu za prijatelje/komšije sa količinom, potvrđenim informacijama i terminom preuzimanja. | Prenos hrane izvan sopstvenog domaćinstva, umesto njene potrošnje, bacanja ili interne sinhronizacije. |
| 88 | Lične automatizacije preko API-ja | Npr. potvrđen plan šalje događaj kućnoj tabli kroz n8n; korisnik bira događaje, podatke i ograničena prava. | Opšti događaji i integracije, umesto unapred definisanog widgeta (59) ili ICS feeda (60). |
| 89 | Novo planiranje bez interneta i AI-ja | Lokalni algoritam sastavlja nov plan od sačuvanih recepata uz dostupna pravila; rezultat se pregleda i odobrava. | Generisanje novog plana offline, umesto samo čitanja/uređivanja ranije sačuvanih planova. |
| 90 | Uvažavanje zauzetosti iz kalendara | Uz dozvolu čitaj samo slobodno/zauzeto i predloži raspoloživ termin kuvanja oko obaveza. | Čitanje zauzetosti u planiranje, umesto izvoza obroka u kalendar (60) ili ručno zadatog trajanja (34). |

### Provereni uzori za treći izbor

- [KitchenOwl](https://github.com/TomBursch/kitchenowl): praćenje zajedničkih troškova i salda (66).
- [Mealie](https://mealie.io/documentation/getting-started/features/): domaćinstva, rezervne kopije i webhooks (63, 65, 88); pristup deljenju je dodatna adaptacija za 64.
- [Bring](https://www.getbring.com/en/features): kartice lojalnosti i ponude (68, 71).
- [AnyList lokacijski podsetnici](https://help.anylist.com/articles/location-reminders/): uzor za 69.
- [Grocy](https://grocy.info/changelog): tare weight i inventarske transakcije kao uzor za 74.
- [Cronometer cooked recipe weight](https://support.cronometer.com/hc/en-us/articles/4407646573588-Mobile-Set-a-Cooked-Recipe-Weight): konačna masa gotovog recepta (75).
- [Acaia Android SDK](https://github.com/acaia/acaia_sdk_android): podržani modeli, očitavanje mase i tare komanda (76); nije univerzalna podrška za sve vage.
- [Combustion developer resources](https://combustion.inc/pages/developer): protokoli i mobilni SDK-ovi za termometre (77).
- [Samsung SmartThings oven](https://www.samsung.com/us/support/answer/ANS10002317/): postavke i slanje na podržane modele rerni (78); dostupnost API-ja za Tavli mora posebno da se proveri.
- [CookBook pan converter](https://cookbookmanager.com/tools/baking-pan-converter) i [baker's percentage calculator](https://cookbookmanager.com/tools/bakers-percentage-calculator): uzori za 79 i 80.
- [King Arthur Baking School](https://www.kingarthurbaking.com/baking-school): inspiracija za strukturisano učenje (81), ne izvor slobodnog sadržaja za kopiranje; 82 zahteva naš uređeni rečnik.
- [Open Food Facts environmental computation](https://github.com/openfoodfacts/openfoodfacts-web/blob/main/lang/en/texts/ecoscore-computation.html): metodološki uzor za 86; ne pretpostaviti da prosečni podaci pokrivaju svako srpsko jelo.
- [Olio](https://olioapp.com/en/): inspiracija za ponudu viška hrane (87); nije tvrdnja da postoji integracija ili lokalna pokrivenost.

61, 62, 70, 72, 73, 83, 84, 85, 89 i 90 su naše konkretne kompozicije ili proširenja, a ne tvrdnje o identičnim gotovim funkcijama u navedenim izvorima. Dostupnost trgovaca, uslovi kupona, očitavanje računa i hardverske integracije zahtevaju proveru po dobavljaču. Iz ove ture najpre bih razradio 66, 73, 74, 79 i 84.
