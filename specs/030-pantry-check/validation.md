# Provera — 10. novembar 2026.

- Testovi repozitorijuma napisani pre implementacije: početni pad zato što metoda još nije postojala.
- `scripts/check.sh`: format ispravan; `flutter analyze` bez problema.
- `flutter test`: 675 testova prolazi, uključujući postojeće tokove Ostave, Nabavke, predloga, sinhronizacije i migracija.
- Nova provera: pozitivan broj, promena jedinice, nepoznato i nula; sat pomeren za jedan dan potvrđuje osvežavanje datuma; naziv/kategorija/rok ostaju.
- Izračun: 600 g potrebe minus 400 g potvrđene zalihe daje 200 g nabavke; nepoznata ili nestala zaliha vraća 600 g.
- Provereni izolacija domaćinstva, odsutan zapis, nevalidne količine, atomski rollback pri grešci outbox-a i grešci tokom preračuna nabavke.
- Primljena kupovina zadržava identitet i nakon „Nestalo“; ponovljeni prijem ne vraća zalihu.
- Widget testovi: 320 i 1200 px uz tekst 2×; potvrda decimalnog zareza, nepoznato i nestalo; odustajanje, obavezan unos količine, zadržavanje unosa pri grešci i ponovni pokušaj.
- Widget testovi proveravaju raspored i ponašanje; ručna provera na fizičkom uređaju nije izvedena.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build macos --debug`: uspešno napravljen `tavli.app`; sistemska Xcode putanja nije menjana.
