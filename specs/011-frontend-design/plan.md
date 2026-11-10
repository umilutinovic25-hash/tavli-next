# Plan

Nadograditi Flutter Material 3 i postojeće tokene iz app_theme/TavliColors.
Dodati mali zajednički zaglavni element i brend u navigaciju; zatim naslov
Plana i kartice, pa zaglavlja Recepti/Nabavka. Bez novih zavisnosti.

Reference pregledane vizuelno 9.11.2026:
- https://crouton.app/ — vidljivi detalj recepta: jasni metapodaci, odvojena
  glavna akcija i čitljivi sastojci. Preuzimamo princip hijerarhije.
- https://www.umami.recipes/ — vidljiva kolekcija: sadržaj i nazivi su primarni,
  praznina razdvaja grupe. Ne kopiramo fotografije, kod ili brend.
- Lokalni docs/product-design.md određuje Tavli izgled i ponašanje.

## Provera ustava I–IX
I srpski Latin; II postojeći repozitorijumi/outbox bez izmena; III bez novih AI
poziva; IV bez ključeva; V postojeći i novi widget testovi; VI oba rasporeda;
VII jedna vizuelna funkcija; VIII posebna specifikacija/grana iz origin/main;
IX bez zavisnosti, generisanih fajlova ili izmena podataka. Nema odstupanja.

## Provera
Format, analyzer, puni Flutter testovi; vizuelni prikazi generisani iz stvarnih
Flutter widgeta sa probnim podacima. macOS debug build zahteva pun Xcode.
