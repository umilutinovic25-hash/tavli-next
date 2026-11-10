# Provera

Samostalna 016 grana iz origin/main: 574 testa prolaze; analiza bez nalaza.
Zajednička 011/012/013/014/015/016 prezentacija: 641 test prolazi; analiza bez nalaza.
Native macOS debug build sa postojećim gitignored lokalnim podešavanjima prolazi.
Aplikacija ponovo otvorena, prijava ostaje sačuvana, novi desktop prikaz vizuelno
pregledan u stvarnom prozoru. Backend iz 015 ostaje lokalni, nema hosted izmena.

Pregledani renderi: popunjeni Recepti, Ostava i Potroši prvo; prazan Plan;
širine 320/390/768/1024/1440; tekst 2×; Bosiljak, Šafran i Borovnica u tamnom
režimu. Novi testovi proveravaju izbor taba, Apple sistemski font, Reduce Motion
i stabilan naslov sekcije nakon promene teme u Profilu.

Dve postojeće funkcionalne provere sada skroluju do podatka koji može biti ispod
početnog viewport-a. Sve izvorne provere upisa, rezultata i brisanja su očuvane.
Postojeća dva hit-test upozorenja u modalnom izboru recepta postoje i u prethodnoj
baznoj zbirci (stari logovi 014); broj nije povećan. Nisu
menjani nepovezani modalni testovi ili produkcioni tokovi radi tih upozorenja.

Prikazi i pravila integracije: docs/apple-polish/README.md.
CI i merge ostaju blokirani prethodno potvrđenom naplatom naloga, koju je vlasnik
odložio; lokalna provera se ne predstavlja kao zelen GitHub Actions rezultat.

Završni detalj: macOS ikonica izvozi isti postojeći TavliBrand. Provereno svih
sedam dimenzija i alpha ivice; originalni asset katalog/putanje su očuvani.
