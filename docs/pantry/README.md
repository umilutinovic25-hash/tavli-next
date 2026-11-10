# Funkcionalna Ostava

[Pregled ekrana](index.html) sadrži PNG prikaze stvarnih Flutter widgeta sa
probnom bazom u memoriji. Nije web verzija aplikacije.

- `/pantry`: postojeće namirnice domaćinstva, pretraga bez kvačica,
  kategorije, isteklo i rokovi u narednih sedam kalendarskih dana.
- `/pantry/new`, `/pantry/:id/edit`: naziv, opciona količina/jedinica/rok,
  kategorija, potvrđeno uklanjanje. Decimalni zarez i precizna količina se čuvaju.
- `PantryRepository` čita/piše postojeću `pantry_items` tabelu i outbox.
  U istoj transakciji preračunava postojeću Nabavku; neuspeh vraća sve izmene.
- Kupljeno → Ostava koristi postojeći prenos. Uklanjanje primljene namirnice
  čuva nultu evidenciju prijema kako stara kupovina ne bi ponovo postala zaliha.
  Ručno uneta namirnica se briše uz postojeću outbox delete operaciju.
- Nema nove šeme, migracija, zavisnosti, lažnih podataka u aplikaciji ili
  direktnih backend poziva iz UI-ja. Server koristi postojeći sync i RLS.
- Greške čuvaju unos; prazna Ostava zadržava postojeću animaciju i dobija
  akciju dodavanja. Forma i spisak rade pri tekstu 2×.

Za generisanje pregleda:
```sh
flutter test --dart-define=TAVLI_DESIGN_CAPTURE=true test/features/pantry/pantry_screen_test.dart
```
PNG fajlovi izlaze u `build/pantry-preview/`. Kopije iz `screens/` koriste
lokalni font i Material ikone. Detalji provera su u
[validation.md](../../specs/012-pantry/validation.md).

Grana 012 polazi od originalnog `main`; prethodni vizuelni rad je zaseban
PR #2. Funkcionalnost Ostave ne zavisi od spajanja tog PR-a.
