# Provera 9.11.2026.

Alat: Flutter 3.47.9 / Dart 3.13.7, bez izmene pubspec/lock fajlova.

- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub`: 570 testova prolazi.
- Novi testovi: 320, 390, 768, 1024 i 1440 px, Plan → Nabavka, tabovi,
  pretraga recepata; postojeća Ostava; sve tri tamne teme.
- Postojeći testovi: 320 px i tekst 2×, kalendar, porcije, zamena jela,
  zaključavanje, kupovina/undo/ostava, profil, animacije i keep-screen-on.
- Test ručnog dodavanja prilagođen skrolovanju do stavke ispod novog
  zaglavlja; i dalje proverava stvarno dodavanje i brisanje, bez preskakanja.
- Stvarni Flutter prikazi vizuelno pregledani, fontovi i ikone učitani.
- Galerija u browseru: sva četiri izbora učitavaju obe PNG slike,
  dugmad ažuriraju aria-pressed i opise. Ne simulira akcije aplikacije.
- `git diff --check`: prolazi.

`flutter build macos --debug --no-pub` nije prošao: Xcode nije instaliran
(dostupni samo Command Line Tools). Native smoke i CI ostaju otvorene provere.
Ne tvrditi da je native aplikacija pokrenuta, objavljena ili spremna za merge.
