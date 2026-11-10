# Verifikacija — 9.11.2026.

Flutter 3.47.9 / Dart 3.13.7, postojeći pubspec i lock bez promena.

- `flutter analyze --no-pub`: bez problema.
- Puni skup grane 012: **587 testova prolazi**.
- Zajednički pregled 011 + 012 u izolovanoj kopiji: **595 testova prolazi**,
  analyzer bez problema. Patch-evi se primenjuju bez konflikata.
- Naknadne preciznije provere fokusiranja tastaturom i istekle/nulte zalihe
  u predlogu plana: 41 povezani test prolazi.
- Pet širina (320/390/768/1024/1440), tekst 2×, duga kategorija, tri tamne
  teme; postojeća animacija praznog frižidera ostaje.
- CRUD, pretraga bez kvačica, filteri rokova, decimalni zarez, nepoznata i
  mala precizna količina, odustajanje od uklanjanja, nedostajući id.
- Greška upisa čuva unos i dozvoljava ponovni pokušaj. Greška tokom
  preračuna Nabavke vraća Ostavu, Nabavku i outbox u prethodno stanje.
- Izolacija domaćinstva; sve lokalne izmene stvaraju postojeće outbox
  operacije. Backend u testovima je lažan, produkcija nije kontaktirana.
- Nabavka → Ostava, bez dupliranja; uklanjanje primljene poznate i nepoznate
  količine ne oživljava staru kupovinu. Promena naziva/jedinice oslobađa
  prethodno pokriće. 1 kg − 250 g = 750 g provereno nezavisno.
- Galerija: sva tri izbora učitavaju slike u browseru; stvarni prikazi
  liste i forme pregledani nakon završetka animacija.

Test iz grane 011 prilagođen je u njenom zasebnom commitu `d35d3be`: čeka
stvarne podatke Ostave umesto fiksnog čekanja na stari placeholder.

## Otvoreno pre merge-a
`flutter build macos --debug --no-pub` blokira nedostajući puni Xcode.
Native smoke nije prošao i aplikacija nije objavljena. CI mora proći pre
spajanja. Postojeći server sync/RLS nije menjan; novi hosted testovi nisu rađeni.

GitHub [PR provera](https://github.com/umilutinovic25-hash/tavli-next/actions/runs/42670474633)
završava sa `startup_failure`. Lokalno uspešni testovi ne predstavljaju zelen CI.
