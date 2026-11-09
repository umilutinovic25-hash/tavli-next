# Tavli — konkurencija na webu i GitHubu

Datum provere: **9. novembar 2026.** Obuhvat: **18 aplikacija/ekosistema i 2
GitHub alata**, uz posebno beleženje ukidanja Mealime-a i migracije Recipya.
Najbliži konkurenti birani su prema poslu koji korisnik obavlja: recepti,
planiranje, stvarne zalihe, kupovina i porodično deljenje.

## Zaključak

Najkorisniji uzori za naredni korak Tavlija su **Paprika, Samsung Food+,
KitchenPal, KitchenOwl, Grocy i Mealie**. AI, offline rad i inventar već
postoje u različitim konkurentskim proizvodima. Naša prilika je njihova jasna
veza na srpskom: **potroši prvo → odaberi obrok → kupi samo nedostajuće**.
To je predlog pozicioniranja, ne dokazana jedinstvena tržišna prednost.

### Metod i granice

- Pročitane su zvanične stranice, vodiči i GitHub README/licence/metapodaci.
  Nisu kupljene pretplate niti praktično testirane sve aplikacije.
- „Nije potvrđeno“ znači da pregledani izvor to ne potvrđuje, ne da funkcija
  sigurno ne postoji. Funkcije mobilne aplikacije nisu automatski funkcije veba.
- GitHub stars i datum push-a predstavljaju trenutni snimak; nisu dokaz
  kvaliteta, upotrebe, bezbednosti ili datuma poslednjeg stabilnog izdanja.
- Tavli stanje uključuje kod originala i draft PR #2/#3; ne tvrdimo da su
  promene objavljene. Novi pantry CRUD nije nova buduća ideja.
- Ovo istraživanje ne dodaje funkcije aplikaciji i ne preuzima tuđi kod.

## 1. Web i komercijalne aplikacije — 10 proizvoda

| Proizvod | Najrelevantnija potvrđena mogućnost | Zaključak za Tavli |
|---|---|---|
| [Paprika 4](https://www.paprikaapp.com/) | Recepti, plan, kupovina, inventar/rokovi i barcode. | Merilo za kompletan lični tok. [Planovi](https://paprikaapp.com/help/v4/ios/pricing/) sada razlikuju Free, Standard za ranije kupce i Premium; stari opis kupovine nije dovoljan. |
| [Samsung Food / Food+](https://samsungfood.com/food-plus/) | Food+ pretražuje recepte po zalihama i prioritetu roka, uz personalizovane planove i AI. Napredni tokovi označeni su kao mobilni. | Najbliži veliki konkurent kombinaciji AI + ostava; razlikovati besplatno i Food+. |
| [KitchenPal](https://kitchenpalapp.com/en/homepage-faq.html) | Inventar, rokovi, upozorenja, barcode, recepti i porodične funkcije. | Održavanje tačne zalihe mora biti brzo. Free limiti ne znače da je sve neograničeno. |
| [AnyList](https://www.anylist.com/meal-planning) | Zajedničke liste i plan koji pravi kupovinu iz raspona datuma. | Deljenje mora da radi jednako dobro kao lična lista. Planer je deo Complete paketa. |
| [Plan to Eat](https://www.plantoeat.com/pricing/) | Uvoz zbirke, kalendar, ponovljivi meniji i kupovina. [Offline mogućnosti](https://learn.plantoeat.com/help/app-offline-capabilities) su dokumentovane. | Offline je važan kriterijum, ali već postoji na tržištu. |
| [SuperCook](https://www.supercook.com/android/) | Izbor recepata prema sastojcima i glasovni unos ostave. | Potrebno je dugme „Šta mogu da skuvam?“. Ovim izvorom nisu potvrđeni tačni rokovi i količine. |
| [Recipe Keeper](https://www.recipekeeperonline.com/) | Uvoz sa veba, skeniranje pisanih recepata, planer i kupovina. | Sken porodičnog recepta i prepoznavanje fotografije jela imaju različitu namenu. |
| [Crouton](https://crouton.app/) | Uvoz/OCR, skaliranje, više tajmera i nedeljni planer na Apple platformama. | Dobar uzor za tok kuvanja; cene nisu zaključene iz glavnog sajta. |
| [CookBook](https://cookbookmanager.com/pricing) | Smart import, OCR, planer i AI funkcije, sa jasno podeljenim nivoima. | Uvoz i jasan izvoz podataka važni su uz AI. [Podrška](https://help.cookbookmanager.com/en/article/how-much-does-cookbook-cost-1jpgfai/) objašnjava pristup sadržaju nakon pretplate. |
| [Umami](https://www.umami.recipes/) | Web uvoz, porodične zbirke, cooking checklist i više izvoznih formata. | Jednostavna organizacija i izvoz korisnikovih recepata imaju veliku praktičnu vrednost. |

Detaljni nalazi, granice paketa i izvori za prvih devet proizvoda:
[web istraživanje](competition-web-details-2026-11-09.md).

## 2. GitHub aplikacije i ekosistemi — 8 projekata

| Projekat | Uloga u poređenju | Potvrđeno | Korisno za Tavli | GitHub stanje 9.11.2026. | Licenca / deklaracija |
|---|---|---|---|---|---|
| [mealie-recipes/mealie](https://github.com/mealie-recipes/mealie) | Najbliži uzor za uvoz i organizaciju zbirke | URL i AI uvoz, kalendar sa pravilima, kupovina, domaćinstva i API. | Uvoz URL-a uz pregled; sačuvani filteri i pravila plana. | 13,859 stars; push 2026-11-09 | AGPL-3.0 |
| [TandoorRecipes/recipes](https://github.com/TandoorRecipes/recipes) | Uzor za kvalitet podataka i planiranje | Recepti, plan i kupovina; sinonimi hrane/jedinica; AI za slike/PDF/tekst i kontrola troška. | Potvrđeni sinonimi sastojaka i jedinica, uvoz, raspored prodavnice. | 8,727 stars; push 2026-11-01 | AGPL-3.0 + Commons Clause prema LICENSE.md |
| [TomBursch/kitchenowl](https://github.com/TomBursch/kitchenowl) | Najbliži tehnički i porodični uzor | Flutter klijent, Flask backend; deljeni plan/lista/recepti, troškovi i delimičan offline. | Pozivi članova, pouzdan zajednički spisak i brzo dodavanje. | 3,829 stars; push 2026-11-08 | AGPL-3.0 |
| [grocy/grocy](https://github.com/grocy/grocy) | Najvažniji uzor za stvarnu zalihu | Količine, rokovi, nabavka i plan; barcode, minimalne zalihe i Due Score. Glavni web PWA nema offline rad. | Potroši prvo, dopuna minimuma i potvrđene transakcije zalihe. | 9,670 stars; push 2026-09-16 | MIT |
| [julianpoy/RecipeSage](https://github.com/julianpoy/RecipeSage) | Uvoz, deljenje i prenosivost | URL/slika/PDF/tekst, zajednički plan i kupovina; README navodi offline pretragu zbirke. | Migracija recepata, spajanje sastojaka, pretraga i izvoz. | 995 stars; push 2026-11-09 | Posebni uslovi: personal-use AGPL / zasebna licenca za ostalo prema README i LICENSE.md |
| [reaper47/recipya-rs](https://github.com/reaper47/recipya-rs) | Jednostavna zbirka i migracije | Rust nastavak Recipya; uvoz, papirni recepti, konverzije i prikaz recepata. | Pregledan uvoz i migracija; planiranu kupovinu ne tretirati kao gotovu funkciju. | 40 stars; push 2026-11-08 | AGPL-3.0 |
| [nextcloud/cookbook](https://github.com/nextcloud/cookbook) | Otvoren format podataka | Recepti kao schema.org JSON fajlovi i uvoz sa URL-a u Nextcloud okruženju. | Standardni JSON izvoz/uvoz; nije zamena za Tavli bazu i outbox. | 653 stars; push 2026-11-09 | AGPL-3.0 (proveriti SPDX u pojedinačnim fajlovima) |
| [cooklang/cookcli](https://github.com/cooklang/cookcli) | Lokalni podaci i pravila bez AI-ja | Tekstualni recepti, CLI i web server; nabavka, ostava, rokovi i minimumi. Pantry.conf još ne čita mobilna aplikacija. | Transparentna pravila za količine, tekstualni izvoz i preporuke po zalihama. | 1,435 stars; push 2026-11-07 | MIT |

Primarni izvori za specifične nalaze:
[Mealie funkcije](https://mealie.io/documentation/getting-started/features/),
[Tandoor sinonimi](https://docs.tandoor.dev/features/automation/),
[Tandoor AI](https://docs.tandoor.dev/features/ai/),
[Tandoor kupovina](https://docs.tandoor.dev/features/shopping/),
[KitchenOwl](https://kitchenowl.org/),
[Grocy funkcije](https://grocy.info/),
[Cooklang ostava](https://cooklang.org/guides/pantry/),
[RecipeSage README](https://github.com/julianpoy/RecipeSage/blob/master/README.md),
[Recipya Rust README](https://github.com/reaper47/recipya-rs/blob/main/README.md),
[Nextcloud Cookbook README](https://github.com/nextcloud/cookbook/blob/master/README.md).

Licence su zabeležene kako ih projekti deklaršu; ovo nije potvrda da se
njihov kod može neposredno preneti u Tavli. Posebno se razlikuju standardna
AGPL oznaka i dodatni uslovi u Tandoor/RecipeSage dokumentima.
Metapodaci i pregledani HEAD commit-i:
[GitHub snimak](competition-github-snapshot-2026-11-09.json).

## 3. GitHub alati — 2 dodatna projekta

| Alat | Potvrđeno | Praktična primena |
|---|---|---|
| [recipe-scrapers](https://github.com/hhursev/recipe-scrapers) | Python parser za receptne HTML/strukturisane podatke; MIT. [Spisak](https://docs.recipe-scrapers.com/getting-started/supported-sites/) navodi preko 745 sajtova. | Kandidat za serverski URL uvoz ili referencu parsera, uz zasebno preuzimanje HTML-a. Nije Flutter paket niti kompletna aplikacija. |
| [recipe-bridge](https://github.com/carllvin/recipe-bridge) | Beta dodatak Mealie/Tandoor sistemima za uvoz i uređivanje pomoću LLM-a; podržava različite provajdere i budžet. | Uzor za pregled pre čuvanja i kvalitet biblioteke. GitHub API nije vratio licencu; preuzimanje koda nije razmatrano. |

Za recipe-scrapers u proverenom spisku nisu pronađeni nazivi Coolinarika
i recepti.com. To ne dokazuje da generički parser ne može obraditi njihove
stranice; znači da lokalni skup sajtova treba proveriti uz stvarne primere.

## 4. Šta se promenilo u odnosu na ranije preporuke

1. **Mealime nije aktivan samostalni konkurent.** Izdavač navodi ukidanje od
   21.10.2026. i prelaz na Meals Hub u Albertsons aplikacijama.
   [Zvanično obaveštenje](https://www.mealime.com/closing).
2. **Paprika 4 ima novi model nivoa pristupa.** Free, Standard za ranije
   kupce i Premium razlikuju se u ograničenjima. Cena zavisi od regiona.
   [Zvanični vodič](https://paprikaapp.com/help/v4/ios/pricing/).
3. **Recipya se prepisuje u Rust.** Stari Go repo najavljuje buduće
   arhiviranje i upućuje na novu verziju. Rust projekat treba pratiti zasebno;
   tvrdnju autora o spremnosti nightly verzije nismo nezavisno testirali.
   [Stari repo i obaveštenje](https://github.com/reaper47/recipya).
4. **AI nije retka funkcija.** Postoje je u Samsung Food+, Mealie, Tandoor i
   CookBook; to menja razlog zbog kojeg bi korisnik odabrao Tavli.
5. **Instalabilan web ne znači offline.** Grocy to eksplicitno razdvaja;
   KitchenOwl navodi delimičan offline, Cooklang ograničava pantry na CLI/web.

## 5. Gde je Tavli danas

| Oblast | Stanje u našem kodu | Konkurentski značaj |
|---|---|---|
| Plan → Nabavka | Postoji sa porcijama i poreklom stavki. | Osnovni očekivani tok; meriti brzinu i tačnost. |
| Ostava | CRUD, pretraga, količine/jedinice, rokovi, prenos kupljenog; PR #3. | Dobra osnova za korisnu preporuku obroka. |
| Offline i sync | Postojeća Drift/outbox/Supabase arhitektura. | Važna pouzdanost; nije samostalna jedinstvena prednost. |
| AI unos | Naziv/slika, pregled i centralni router. | Dopuna uvozu i sopstvenoj biblioteci. |
| URL uvoz | Još nije implementiran. | Veliki jaz pri prebacivanju korisnikovih postojećih recepata. |
| Potroši prvo / mogu sada | Još nije završen predlog recepata po zalihama. | Najprirodniji nastavak nove Ostave. |
| Domaćinstvo | Account/scope postoje; pozivi i puni zajednički tok još slede. | Ne izjednačavati bazni model sa gotovim deljenjem. |
| Objavljena verzija | Frontend i Ostava su draft PR-ovi. | Kod i testovi nisu dokaz produkcionog izdanja. |

Izvori stanja: originalni kod i lokalne specifikacije 011/012;
[PR #2](https://github.com/umilutinovic25-hash/tavli-next/pull/2),
[PR #3](https://github.com/umilutinovic25-hash/tavli-next/pull/3).

## 6. Preporučeni redosled — procena za Tavli

Ovo su prioriteti razvoja iz već postojećih ideja, ne 20 novih funkcija i ne
rezultat istraživanja tržišne potražnje. Procena kombinuje korist, uklapanje
u postojeći kod i obim implementacije.

| Red | Sledeća funkcija | Uzor | Šta bi značilo da radi |
|---|---|---|---|
| 1 | „Potroši prvo“ i „Šta mogu da skuvam?“ | Grocy, Food+, SuperCook | Recepti iz naše zbirke rangirani po potvrđenim zalihama i rokovima; pokazati šta nedostaje, bez izmišljenih količina. Prvo može bez AI-ja. |
| 2 | URL uvoz uz pregled | Mealie, Paprika, recipe-scrapers | Sačuvati izvorni link, prikazati i dozvoliti ispravku sastojaka/koraka pre upisa. Proveriti reprezentativne domaće i strane stranice. |
| 3 | Kontrola kvaliteta sastojaka | Tandoor | Potvrđeni sinonimi uz bezbedne fizičke konverzije; ista namirnica se ne kupuje dvaput zbog različitog naziva. |
| 4 | Pozovi člana i podeli Nabavku | KitchenOwl, AnyList | Zasebni nalozi i uloge; dve osobe vide isto stanje i dobijaju razumljive konflikte. |
| 5 | Izvoz i uvoz sopstvenih podataka | Umami, Nextcloud Cookbook | Čitljiv izvoz recepata i Ostave, proverljiv povratni uvoz i bez dupliranja. |

Posle toga: podsetnici na rokove, barcode unos uz potvrdu konkretnog roka,
lokacije/serije namirnica i minimumi zaliha. Makroi, pametni uređaji i
velika mreža sadržaja imaju veći obim od prvih pet koraka.

## 7. Provere koje bi promenile prioritete

- Posmatrati pet korisnika u toku Ostava → obrok → Nabavka i izmeriti greške.
- Proveriti koliko brzo se unosi stvarna nedeljna kupovina i održava stanje.
- Napraviti skup 20 domaćih i stranih recepata za budući URL uvoz.
- Proveriti lokalnu dostupnost barcode podataka i kvalitet jedinica/rokova.
- Pregledati plaćene mobilne tokove najbližih konkurenata pre obećanja o
  cenama, ravnopravnosti platformi ili jedinstvenosti funkcije.
