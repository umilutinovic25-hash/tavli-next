# Frontend — prvi vizuelni korak

Otvori [galeriju](index.html) u browseru. Telefon i široki prikaz su slike iz
stvarnih Flutter widgeta, sa lokalnom bazom u memoriji i probnim nalogom.
Galerija nije drugi frontend niti web port aplikacije.

## Šta je implementirano
- Zajednički Tavli znak i brendirana široka navigacija.
- Hijerarhija Plana i preglednije kartice obroka, sa postojećim statusima.
- Zaglavlja Recepata i Nabavke; postojeće akcije i state su zadržani.
- Postojeće palete, ugrađeni font i animacije bez novih zavisnosti.

## Tokeni i komponente
TavliPalette → ColorScheme / TavliColors → TavliBrand, SectionHeading,
MealEntryCard. Nema lokalnih hardkodiranih boja u novim Flutter komponentama.
Razmaci: 8/16/24/32; kartice i njihov InkWell koriste isti radijus 20.
Pri velikom tekstu Plan izostavlja dekorativni uvod kako bi glavna akcija
ostala bliže vrhu. Bitni podaci plana ostaju prikazani.

## Reference
Veštine: frontend-ui-engineering i design-system. Vizuelno pregledani javni
prikazi [Crouton](https://crouton.app/) i [Umami](https://www.umami.recipes/)
poslužili su za hijerarhiju i razmak; kod i fotografije nisu preuzimani.
Tavli smer prati postojeći docs/product-design.md.

## Ponovljiv pregled
```sh
flutter test --dart-define=TAVLI_DESIGN_CAPTURE=true test/app/frontend_layout_test.dart
```
PNG izlaz je u `build/design-preview`. Sačuvani izbor u `screens/` potiče iz
tog pokretanja. Prikaz recepta i ostave velikim delom je postojeći UI.

## Sledeće zasebne funkcije
1. Ostava: prikaz stvarnih unosa, forme i postojeći repozitorijum/outbox.
2. Recepti: poboljšan početni prazan prikaz i tok dodavanja.
3. Kuhinjski prikaz: pregled koraka uz očuvanje keep-screen-on funkcije.
4. Funkcije iz registra 90 ideja uvoditi po prioritetima, svaku proveriti.

Makete ne potvrđuju implementaciju svih 90 ideja. macOS debug build zahteva
pun Xcode; ovom okruženju dostupni su samo Command Line Tools.

Lokalno prolaze analiza i svih 570 testova. Detalji i otvorene provere:
[izveštaj verifikacije](../../specs/011-frontend-design/validation.md).
