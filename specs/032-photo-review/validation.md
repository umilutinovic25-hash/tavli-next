# Provera — 10. novembar 2026.

- Domen test-first: početni pad jer klasifikacija količina još nije postojala.
- `scripts/check.sh`: format ispravan; `flutter analyze` bez problema.
- `flutter test`: svih 681 testova prolazi, uključujući foto-unos, unos po nazivu, ručno uređivanje, pregled sastojaka, nabavku i animacije.
- Domen razlikuje nedostajuće/nečitljivo od nulte/negativne/nekonačne količine. Prazno, „po ukusu“ i nečitak broj nisu procenjeni brojevi; decimalni zarez i razlomak ostaju podržani.
- Fotografija se prikazuje sa `BoxFit.contain`; na 1200 px sa običnim tekstom proverene su dve kolone i njihov stvarni položaj. Telefon koristi jedan skrol prikaz.
- Uvećavanje menja transformaciju, vraćanje na celu sliku vraća razmeru 1; izvorna fotografija i broj AI zahteva ostaju nepromenjeni.
- Neispravni brojevi u foto-pregledu blokiraju čuvanje i slanje u nabavku. Popravka u editoru ili izričito prazno polje rešava blokadu; nepoznato ostaje vidljivo označeno.
- Ispravka 250,5 g čuva očekivanu količinu 250.5 i jedinicu/kategoriju/napomenu; ispravke ne pišu pre potvrde celog recepta. Recept čuva source=photo i postojeću fotografiju.
- Preciznost: 0,001 g se prikazuje kao 0,001 g i ostaje 0.001 nakon promene samo naziva i čuvanja. Podrazumevani formatter i ručni unos zadržavaju ranije ponašanje.
- Provereni otkazivanje editora, odbacivanje ispravljenog pregleda, ponovljeno AI čitanje i zaseban indeks kada je isti objekat sastojka ponovljen u listi.
- Widget tokovi rade na 320 i 1440 px sa tekstom 2× i tamnom temom. Postojeći PhotoScan/MotionBuilder i njihove animacije ostaju u toku; postojeći testovi animacija prolaze.
- „Originalna fotografija“ označava izvorni dokument normalizovan postojećim unosom (orijentacija i JPEG do 1600 px), ne sačuvan raw fajl ili sirovi OCR transkript.
- Ručna provera na fizičkom uređaju nije izvedena.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build macos --debug`: uspešno napravljen `tavli.app`; sistemska Xcode putanja nije menjana.
