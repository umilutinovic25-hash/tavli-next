# Poređenje cena korpe — početna provera izvora

Provera 13. 11. 2026. Polazna grana: main nakon PR #37.

## Postojeće stanje

Nabavka koristi ShoppingItemRow i postojeće liste po planu i receptu; otvorene stavke izdvaja ShoppingItemsList. Katalog namirnica povezuje nazive i jedinice, ali nije katalog trgovinskih proizvoda i njihovih pakovanja. Potrebna je potvrđena veza između stavke i proizvoda pre računanja cene.

## Izvori

- [Delhaize — data.gov.rs](https://data.gov.rs/sr/datasets/cenovnici-proizvoda-prema-pravilniku-o-uslovima-sadrzaju-i-nacinu-objavljivanja-cenovnika-delhaize-serbia-doo-beograd/): CSV dostupan na adresi trgovca; opis zahteva navođenje izvora i datuma preuzimanja.
- [Europrom — data.gov.rs](https://data.gov.rs/sr/datasets/cenovnici-proizvoda-prema-pravilniku-o-uslovima-sadrzaju-i-nacinu-objavljivanja-cenovnika-europrom-doo/): CSV dostupan preko javne adrese; isti zahtev za izvor i datum.

Oba URL-a su 13. 11. odgovorila CSV sadržajem. Zaglavlja sadrže proizvod, brend, barkod, jedinicu, format trgovca, datum, redovnu i sniženu cenu, datume sniženja i vrstu cenovnika. U početku datoteka nalaze se i istorijski redovi označeni MESECNI_PRESEK, tako da prvi red ili poslednji preuzeti fajl nisu dokaz aktuelne cene. Delhaize ima više formata (npr. Maxi i Maxi Online), koje ne treba objediniti kao istu ponudu.

Uzorkovani podaci sadrže količinu pakovanja u slobodnom nazivu (npr. 400g ili 250G), a jedinica mere i cena po jedinici nisu dovoljno pouzdani za zaključivanje veličine pakovanja bez dodatne provere. Primer: prvi uzorkovani red za proizvod od 400 g navodi cenu 399,99 i cenu po jedinici 399,99. Ne računati kupovnu cenu automatski iz ovih podataka bez potvrde pakovanja.

## Predlog početnog toka

1. Server preuzima odabrane zvanične cenovnike, čuva izvor i vreme preuzimanja, obrađuje format prodavnice, datum, vrstu cenovnika, redovnu cenu i vremenski važeću akciju. Proveriti stvarna pravila objava, duplikate i vremenske zone na reprezentativnom uzorku pre odabira najnovijeg reda.
2. Korisnik potvrđuje proizvod i veličinu pakovanja za svaku stavku. Barkod povezuje isti proizvod između lanaca; različita pakovanja se računaju zasebno. Nepoznate količine, jedinice ili pakovanja ostaju nepokrivene.
3. Za svaki lanac obračunati broj celih pakovanja potrebnih za potvrđenu količinu i sabrati cene. Prikazati pokrivene i nepokrivene stavke, izvor i datum. Poređenje ukupnih cena je smisleno tek za istu pokrivenost korpe.
4. Proveriti ručno izračunat primer, akcije, nepotpunu korpu, količine i različite formate prodavnica; ne slati sadržaj korisnikove korpe trećem licu pri osvežavanju cenovnika.

Ovo je istraživanje, ne implementacija ni potvrda da su svi cenovnici potpuni ili aktuelni.
