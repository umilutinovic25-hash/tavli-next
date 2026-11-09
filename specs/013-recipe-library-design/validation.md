# Verifikacija — 9.11.2026.

- REA: tri javna origin-a, tri pasivne inspekcije i tri PNG snimka
  1440×1000; prikazi su vizuelno pregledani. Ograničenja su uz dokaze.
- `python3 tools/verify_design_adoption.py`: šest pinned upstream fajlova
  (tri source, tri originalne MIT licence), tri proverena REA PNG hash-a.
- Izveštaj korisničkih iskustava ima deset izvora i odvaja korisnike,
  developere i projektantsku procenu. Nema univerzalnog pobednika.
- `flutter analyze --no-pub`: bez problema.
- Puni skup originala + 013: 573 testa prolazi; zatim ciljane provere
  poslednjih vizuelnih izmena: 16 testova prolazi.
- Izolovana zajednička kopija 011 + 012 + 013: **606 testova prolazi**,
  analiza bez problema; patch-evi primenjeni bez konflikta.
- Pet širina (320/390/768/1024/1440), tekst 2×, dugi nazivi, tri tamne teme,
  nepostojeća slika, pretraga, prazan rezultat, promena prikaza i otvaranje.
- Na 1024 px prošireni rail ostavlja manje od 840 px za split; recept se
  otvara kao ceo ekran. Na širem prikazu izabrana mreža ostaje pored recepta.
- Slike u `docs/design-adoption/screens/` potiču iz stvarnih Flutter widgeta
  u zajedničkom pregledu 011/012/013 sa probnim podacima. To nisu konkurentske
  fotografije. Galerija u browseru proverena za telefon/široki/tamni prikaz.
- UI nije dodao backend pozive ili zavisnosti. Preuzeti SQL/Rust/Python su
  reference izvan runtime-a; njihove zavisnosti i funkcije nisu izvršavane.

Native macOS debug build zahteva puni Xcode koji nije instaliran. CI mora
proći pre spajanja; lokalni testovi nisu dokaz objavljene aplikacije.
