# Tavli: komercijalna konkurencija, provera 9. novembra 2026.

Pregled devet proizvoda i statusa Mealime-a. Koristio sam samo zvanične sajtove, dokumentaciju i objave izdavača za nalaze. Ovo je provera javnih deklaracija, ne praktičan test aplikacija. Nepostojanje funkcije u izvoru nije dokaz da je aplikacija nema. Cene nisu osnov poređenja jer zavise od države, poreza i prodavnice.

Polazna tačka Tavlija iz zadatka: Flutter, offline Drift/outbox i Supabase; Plan, Shopping i Recipes; novi pantry CRUD, rokovi, filter i transfer kupovine u zalihe; AI recept iz slike/naziva preko router-a. Web import još ne postoji; pozivi u domaćinstvo i realtime su budući rad. Draft PR nije dokaz objavljene funkcije.

## 1. Paprika

**Provereno:** aktuelni zvanični sajt i vodič sada opisuju Paprika 4. Recepti sa veba, planiranje, spajanje istih stavki kupovine i sinhronizacija više platformi čine osnovu. Pantry čuva količinu, datum kupovine, rok i stanje; sastojci iz zaliha automatski se odznačavaju pri dodavanju recepta/plana u kupovinu. Postoje lokacije, sortiranje po roku i mobilni barcode unos.

**Granica plana:** Free ima 50 recepata, nema cloud sync i dopušta samo po jednu listu, kuvar i pantry lokaciju. Raniji kupci dobijaju Standard sa neograničenim receptima, sync-om i dodatnim listama/lokacijama bez obavezne pretplate; Premium otključava sve funkcije. Ne koristiti stari zaključak „Paprika = jednokratna kupovina po platformi“ kao aktuelni poslovni model.

**Za Tavli:** količine, rokovi i osnovni transfer u zalihe jesu važni, ali nisu sami po sebi diferencijacija. Sledeći korak je proverljivo povezivanje zaliha sa potrebnom kupovinom; barcode unos mora ostaviti pregled pre čuvanja.

Izvori: [proizvod](https://www.paprikaapp.com/), [Paprika 4 planovi](https://paprikaapp.com/help/v4/ios/pricing/), [pantry vodič](https://paprikaapp.com/help/v4/ios/pantry/).

## 2. Samsung Food / Food+

**Provereno:** osnovni proizvod objedinjuje recepte, zajedničke planove i kupovinu. Food+ oglašava personalizovan sedmodnevni plan, AI izmene recepata, nutritivne ciljeve, sačuvane planove i automatsko održavanje Food List-e. Pretraga po toj listi prioritizuje sastojke kojima uskoro ističe rok. Zvanična stranica navedene napredne funkcije označava kao ekskluzivne za mobilnu aplikaciju.

**Granica:** postoji web planer, ali paritet nije potpun: ni promena početnog dana nedelje iz proverene podrške nije dostupna u web aplikaciji.

**Za Tavli:** „AI + pantry“ već ima velikog konkurenta. Korisnija početna razlika je kratak, pouzdan tok „ovo prvo potroši → ovaj recept → kupi samo nedostajuće“, sa jasnom potvrdom promena zaliha.

Izvori: [Food+ funkcije](https://samsungfood.com/food-plus/), [besplatni planer](https://samsungfood.com/meal-planner/), [podrška za planer](https://support.samsungfood.com/hc/en-us/articles/35369657798548-Getting-Started-with-Meal-Planner).

## 3. AnyList

**Provereno:** aplikacija povezuje zajedničke liste, zbirku recepata i planiranje. Free dozvoljava pet direktnih web uvoza, Complete neograničeno. Planiranje i web/Mac pristup su Complete funkcije. Plan može da generiše listu za izabrani raspon datuma; promene zajedničkih recepata i plana odmah su vidljive članovima domaćinstva.

Novije zvanične objave navode queue, personalizovane predloge, šablone, pretragu plana i planiranje ostataka hrane. To je signal zrelosti planera, ne samo postojanja kalendara.

**Za Tavli:** household pozivi i sinhronizacija važni su za konkurentnost porodične kupovine. Beleške poput „ostaci“ i ponovljivi planovi verovatno donose vrednost pre naprednog automatskog generisanja jelovnika. U pregledanim izvorima nisam potvrdio namenski inventar sa rokovima.

Izvori: [poređenje paketa](https://www.anylist.com/features), [recepti i deljenje](https://www.anylist.com/recipes), [planiranje](https://www.anylist.com/meal-planning), [objava iz januara 2026.](https://blog.anylist.com/2026/01/meal-plan-update/), [web](https://www.anylist.com/web/about).

## 4. Plan to Eat

**Provereno:** uvoz recepata sa sajtova i društvenih mreža, kalendar, ponovljivi meniji i automatska kupovina po prodavnici/prolazu. Jedna pretplata uključuje sve funkcije i platforme, uz 14 dana probe bez kartice. Domaćinstvo može koristiti jedan nalog na više uređaja; to ne treba poistovetiti sa zasebnim korisničkim pozivima i ulogama.

Offline mobilna aplikacija podržava dodavanje/izmenu/prikaz recepata, izmene plana i ručno dodavanje, uređivanje i označavanje kupovine.

**Za Tavli:** offline je dobra osnova, ali nije jedinstven tržišni argument. Kvalitet uvoza, sabiranje količina i brzina pretvaranja plana u kupovinu moraju biti dobri. Namenski inventar sa rokovima nije potvrđen ovim izvorima.

Izvori: [paket i funkcije](https://www.plantoeat.com/pricing/), [offline mogućnosti](https://learn.plantoeat.com/help/app-offline-capabilities).

## 5. KitchenPal

**Provereno:** direktan konkurent za pantry: zalihe, rokovi, upozorenja, predlozi recepata po zalihama, kupovina, planer i porodično deljenje. Zvanični FAQ navodi Free ograničenje do 100 kuhinjskih stavki i do 50 barcode skeniranja. Premium uključuje sopstvene recepte/uvoz, izvoz zaliha/lista, prilagođene prostore i kategorije, neograničeni planer i skeniranje. Postoje mesečni, godišnji i lifetime paketi, uključujući porodični.

**Oprez:** stranica o rokovima tvrdi da su praćenje, upozorenja i predlozi uključeni besplatno, ali se i dalje primenjuju ograničenja naloga iz FAQ-a. Marketinške tvrdnje o procentu smanjenja otpada nisu nezavisno proverene i nisu dokaz uštede. Običan unos proizvoda barkodom ne treba predstavljati kao pouzdano očitavanje konkretnog roka sa pakovanja.

**Za Tavli:** samo pantry CRUD ne sustiže ovaj obim. Bitan je mali broj koraka za održavanje tačnih zaliha, obrada istog proizvoda u različitim serijama/rokovima i upotreba podataka pri izboru obroka.

Izvori: [FAQ i limiti](https://kitchenpalapp.com/en/homepage-faq.html), [praćenje rokova](https://kitchenpalapp.com/en/expiry-date-tracker.html), [pregled podrške](https://kitchenpalapp.com/en/help/index.html), [FAQ o kuhinji](https://kitchenpalapp.com/en/faqs/kitchen.html).

## 6. SuperCook

**Provereno:** zvanični Android opis na SuperCook domenu opisuje glasovni unos sastojaka, pantry i preporuke prema onome što korisnik ima. Kad sastojak nestane, korisnik ga uklanja, a rezultati se prilagođavaju. Izdavač navodi preko 11 miliona recepata na 20 jezika; broj je njihova deklaracija, ne nezavisno brojanje.

**Granica verifikacije:** glavni web sajt je alatu vratio samo JavaScript fallback. Iz dostupnog zvaničnog opisa nisam potvrdio količine, konkretne rokove, porodični sync, cenovne nivoe ili pun planer. Ne označavati ih kategorički kao nepostojeće.

**Za Tavli:** „šta mogu da skuvam od ovoga“ je poseban važan posao koji korisnik želi da obavi. Tavli može kombinovati sopstvene recepte i stvarne količine/rokove, ali ta prednost tek zahteva precizno mapiranje sastojaka.

Izvori: [zvanični opis Android aplikacije](https://www.supercook.com/android/), [web](https://www.supercook.com/).

## 7. Recipe Keeper

**Provereno:** ručni recepti, uvoz sa veba, skeniranje fotografisanih recepata, nedeljni/mesečni planer i dodavanje sastojaka na kupovinu. Mobilne i desktop platforme uključuju iOS, Android, Windows i Mac. Zvanična stranica navodi dostupnost recepata online i offline, porodično/prijateljsko deljenje recepata i izradu kuvara.

**Granica:** na pregledanoj zvaničnoj početnoj stranici nije potvrđen tačan besplatni limit ili aktuelna cena. Deljenje recepta imejlom ne dokazuje zajednički realtime inventar/listu.

**Za Tavli:** web import i čuvanje korisnikovih postojećih recepata važniji su osnovni konkurentski kriterijum od same AI generacije. OCR porodičnih recepata ima drugačiju vrednost od AI generisanja recepta iz fotografije jela.

Izvor: [zvanični proizvod](https://www.recipekeeperonline.com/).

## 8. Crouton

**Provereno:** Apple platforme; web uvoz, OCR kuvara, skaliranje, konverzija jedinica, više tajmera, nedeljni plan i automatsko sastavljanje plana iz sačuvanih recepata. iCloud omogućava sync i deljenje sa domaćinstvom; zvanični press kit navodi kupovinu iz sastojaka recepata.

**Granica:** osnovni sajt nije prikazao cenovnik. Podrška Combustion-a opisuje Basic do pet recepata, jednokratni Plus i pretplatni Discover, ali tu podršku treba dodatno povezati sa aktuelnom Crouton kupovinom pre korišćenja kao konačan cenovnik. Pouzdano potvrđene mogućnosti iz Crouton-ovog sajta važe nezavisno od tog ograničenja.

**Za Tavli:** jednostavan cooking mode, tajmeri i skaliranje jačaju svakodnevno korišćenje. Automatski plan ne mora početi generativnim AI-jem: može krenuti izborom iz korisnikove proverene zbirke.

Izvori: [Crouton](https://crouton.app/), [zvanični press kit](https://crouton.app/press-kit.html). Dodatna, uslovna potvrda nivoa: [Combustion podrška](https://combustioninc.gorgias.help/en-US/crouton-plans-features-and-benefits-2142748).

## 9. CookBook

**Provereno:** Free ima 20 recepata, 20 smart import-a, dve ograničene liste i cloud sync na iOS-u, Androidu i vebu. Pro nudi neograničene recepte/uvoze, planer, AI kreiranje/varijacije, nutritivni kalkulator i deset lista. Smart import obuhvata web, društvene mreže i OCR. Planer podržava porcije, beleške/obroke bez recepta, više prikaza i kupovinu razvrstanu po prolazima.

**Važna granica:** posle isteka pretplate vide se 20 poslednjih recepata i dve liste; stariji sadržaj se zaključava do ponovne pretplate, ali izvoz svih recepata ostaje dostupan. Izvoz je dostupan i besplatnom nalogu.

**Za Tavli:** AI recepti više nisu retka funkcija. Jednostavan izvoz i jasna pravila pristupa podacima mogu biti smislenija razlika; preporuka je da korisnik uvek može izneti svoje recepte i zalihe.

Izvori: [planovi i ograničenja](https://cookbookmanager.com/pricing), [podrška za planove](https://help.cookbookmanager.com/en/article/how-much-does-cookbook-cost-1jpgfai/), [planer](https://help.cookbookmanager.com/en/article/does-cookbook-have-a-meal-planner-86smls/).

## Mealime: promenjen status

Zvanično obaveštenje kaže da se samostalni Mealime ukida od **21. oktobra 2026.** i korisnike usmerava u Meals Hub u Albertsons Companies aplikacijama i na njihovim sajtovima. Navodi besplatne recepte, dijetetske preferencije, planiranje i kupovinu; navodi i brisanje ličnih podataka pri gašenju. Zato Mealime 9. novembra 2026. ne treba porediti kao aktivnu samostalnu aplikaciju. Dostupnost obaveštenja i starih recepata ne dokazuje da stara aplikacija radi.

**Za Tavli:** dugoročna dostupnost, lokalni rad i izvoz podataka imaju razumljivu vrednost. Ovo nije dokaz da je ukidanje konkurenta stvorilo merljivu potražnju za Tavlijem.

Izvor: [Mealime: prelazak na Meals Hub i FAQ](https://www.mealime.com/closing).

## Prioriteti koji proizlaze iz poređenja

1. Stabilizovati ceo tok Plan → količinski ispravna Shopping lista → potvrđeni transfer u pantry. Uračunavanje zaliha zahteva istovetnost sastojaka i jedinica, a ne samo tekstualno spajanje.
2. Dodati web import sa pregledom i ispravkom pre čuvanja. Konkurenti time koriste korisnikove postojeće recepte i smanjuju potrebu za ručnim unosom.
3. Učiniti zalihe korisnim pri odluci: „prvo potroši“, „mogu sada“ i „nedostaje još“. Jasno razlikovati AI generisan recept od uvezenog/proverenog izvora.
4. Završiti household pozive i pouzdan sync pre obećavanja zajedničke kuhinje. Jedan deljeni nalog, slanje recepta i zasebni članovi domaćinstva nisu ista mogućnost.
5. Sačuvati offline osnovu i ponuditi izvoz. Offline sam po sebi nije jedinstven, ali u kombinaciji sa jednostavnošću i kontrolom podataka može biti uverljiv proizvodni izbor.

Navedeni prioriteti su moja procena na osnovu poređenja i zadatog Tavli stanja, ne rezultat intervjua sa korisnicima ili merenja tržišne potražnje. Ne predstavljati ih kao nove implementirane ili objavljene Tavli funkcije.
