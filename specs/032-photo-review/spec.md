# 032 — Sken uz izdvojeni tekst (predlog 49)

Pre čuvanja recepta sa fotografije korisnik poredi izvorni dokument i prepoznati recept, pregleda nejasne količine i po potrebi ispravlja sastojke. Ne pravimo ocenu pouzdanosti niti obećavamo da pozitivan broj mora biti tačno prepoznat.

## Prihvatanje
- Široki ekran prikazuje „Originalna fotografija“ i „Prepoznati recept“ uporedo; telefon ih prikazuje jedno ispod drugog. Fotografija se uklapa cela, bez kropovanja teksta. Postojeće animacije prepoznatih sastojaka ostaju.
- „Uvećaj fotografiju“ otvara celu fotografiju sa pomeranjem, uvećavanjem i vraćanjem na ceo prikaz. Koristi se ista fotografija normalizovana pri unosu (orijentacija i JPEG do 1600 px), ne nova AI slika. Čuvanje slike prati postojeći format i tok.
- Nedostajuća ili neprepoznata količina ima vidljivu tekstualnu oznaku „Količina nije prepoznata — proveri original.“. Nulta, negativna i nekonačna količina ima oznaku „Neispravna količina — proveri original.“.
- Prazna količina sme da ostane nepoznata. Neispravan broj ne može da se sačuva ni pošalje u nabavku dok se ne ispravi ili izričito ostavi praznim. Bez izmišljanja količina ili procenta pouzdanosti.
- Svaki sastojak može da se ispravi u postojećem editoru sastojaka; promene su samo u otvorenom pregledu. Naziv, jedinica, kategorija i napomena ostaju dostupni. Isti objekat/sastojak ponovljen u listi uređuje se po svom indeksu.
- Editor u foto-pregledu odbija unetu nečitljivu, nultu, negativnu i nekonačnu količinu; prihvata decimalni zarez, razlomak i izričito praznu količinu. Odustajanje ništa ne menja. Foto-pregled i editor zadržavaju punu preciznost (npr. 0,001 g se ne prikazuje kao 0 g i ne zaokružuje pri promeni naziva).
- Poređenje, uvećavanje i ispravke ne pozivaju AI i ništa ne upisuju. „Sačuvaj“ upisuje poslednji pregledani recept i fotografiju. „Odbaci“ uklanja i ispravke; „Pokušaj ponovo“ ponavlja postojeći AI tok.
- Unos po nazivu i postojeći obični prikaz/ručni editor zadržavaju ponašanje. Telefon, široki ekran i tekst 2× rade, kao i tamni režim i smanjeno kretanje.

## Tekstovi
„Originalna fotografija“, „Prepoznati recept“, „Uporedi sastojke i korake sa fotografijom. Nejasne količine ostaju za proveru.“, „Uvećaj fotografiju“, „Uvećaj“, „Cela fotografija“, „Fotografija nije dostupna.“, „Količina nije prepoznata — proveri original.“, „Neispravna količina — proveri original.“, „Ispravi neispravne količine ili ih ostavi praznim pre čuvanja.“, „Izmeni sastojak: …“, „Unesi pozitivan broj ili ostavi prazno ako količina nije poznata.“
