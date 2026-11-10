# 030 — Brza provera Ostave (predlog 39)

Korisnik proverava pojedinačnu turu namirnice direktno iz Ostave, bez ponovnog unosa naziva, kategorije i roka. Podaci ostaju u postojećoj tabeli i idu kroz isti outbox.

## Prihvatanje
- „Proveri namirnicu“ nudi „Imam“, „Nestalo“ i „Ne znam količinu“.
- „Imam“ otvara pregled količine i jedinice. Korisnik potvrđuje pozitivan konačan broj; decimalni zarez radi. Odustajanje ništa ne upisuje.
- „Nestalo“ čuva nultu količinu i datum provere; stavka nestaje iz aktivne Ostave. Identitet prijema kupovine ostaje pa ponovljen prijem ne vraća zalihu.
- „Ne znam količinu“ čuva nepoznatu količinu i datum provere; ne umanjuje nabavku ni manjkove predloga.
- Datum „Provereno: d.m.gggg.“ je vidljiv i za proverenu nepoznatu količinu; bez datuma piše „Još nije provereno“.
- Menja se samo izabrana tura u sopstvenom domaćinstvu. Naziv, kategorija, rok i poreklo ostaju.
- Upis, outbox i preračun nabavke su jedna transakcija. Greška ostavlja stanje nepromenjeno i omogućava ponovni pokušaj.
- Telefon, široki ekran i tekst 2× rade; postojeće uređivanje ostaje dostupno.

## Tekstovi
„Proveri namirnicu“, „Imam“, „Nestalo“, „Ne znam količinu“, „Proveri količinu“, „Količina“, „Jedinica“, „Potvrdi“, „Odustani“, „Unesi broj veći od nule.“, „Provereno: …“, „Još nije provereno“, „Stanje je provereno.“, „Provera nije sačuvana. Pokušaj ponovo.“, „Namirnica nije pronađena.“
