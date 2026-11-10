# Provera
- Test-first red korak: novi ugovor nije postojao, test nije mogao da se učita.
- 11 novih testova sa lažnim skladištem, bez pristupa sistemskom Keychain-u.
- 573 testa samostalne grane prolaze; flutter analyze bez nalaza.
- 652 testa zajedničkog pregleda 011–017 prolaze; analiza bez nalaza.
- Native macOS build sa lokalnim preview flag-om prolazi.
- Stvarna aplikacija: lokalna OTP prijava, unos imena, Plan, Profil, AI ključevi.
  Posle normalnog zatvaranja i ponovnog otvaranja sesija je vraćena, bez novog
  zahteva za ranije Keychain stavke. Sačuvana izabrana tema korisnika.
- Postojeći normalni ključevi nisu pročitani, izmenjeni, migrirani ili obrisani
  tokom ove verifikacije. Local OTP kodovi/tokeni nisu ispisivani.
- GitHub CI čeka prethodno odloženo sređivanje naplate/limita; bez merge-a.
