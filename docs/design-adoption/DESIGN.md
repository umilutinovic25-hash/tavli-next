# Tavli — dizajn preuzetih obrazaca

## Šta je pregledano

REA je 9.11.2026. pasivno pregledao **javne stranice** Croutona, Umamija i
Paprike i snimio viewport 1440×1000. Prikazi mobilnih aplikacija ugrađeni su
u njihove javne promotivne stranice; zatvorene mobilne aplikacije nisu
dekompajlirane niti su testirane iza naloga/pretplate.

Firecrawl CLI nije instaliran. Veština firecrawl-website-design-clone korišćena
je za strukturu dokaza i DESIGN.md, a korisnikov izričiti izbor REA ostvaren
je kroz stvarne `inspect_web_page` / `capture_web_screenshot` operacije.
Slike su stvarno dekodirane i vizuelno pregledane. `frontend-ui-engineering`
određuje prilagođavanje postojećem Flutter UI-ju.

| Referenca | Šta se vidi | Šta primenjujemo |
|---|---|---|
| [Crouton](https://crouton.app/) | Lista sa slikama, odvojen glavni Start, porcije i vremena kao male grupe; velika čitljiva hijerarhija na sajtu. | Miran raspored, dostupni metapodaci i jasna akcija. Cooking tajmeri ostaju naredna funkcija. |
| [Umami](https://www.umami.recipes/) | U prikazu telefona je pregledna mreža zbirke, kratki nazivi i dodavanje u kolekciju. | Opciona mreža naše biblioteke, ista pretraga i iste rute. |
| [Paprika 4](https://www.paprikaapp.com/) | Desktop sidebar i više načina prikaza; mobilni recept zadržava prostor za sadržaj uz manju sliku. | Zadržavanje informativne liste i izbor mreže; porcije/vreme ostaju odmah vidljivi. |

Ovo su vizuelno posmatrani obrasci, ne egzaktno izvučen CSS. Tačne fontove,
spacing, mobilne interakcije, hover i animacije nismo utvrdili iz ovih
desktop snimaka. Ne tvrdimo potpunu rekonstrukciju izvornog dizajn sistema.

### Slike i REA dokazi

- [Crouton snimak](evidence/crouton-desktop.png),
  [inspekcija](evidence/crouton-inspection.json),
  [screenshot manifest](evidence/crouton-screenshot.json).
- [Umami snimak](evidence/umami-desktop.png),
  [inspekcija](evidence/umami-inspection.json),
  [screenshot manifest](evidence/umami-screenshot.json).
- [Paprika snimak](evidence/paprika-desktop.png),
  [inspekcija](evidence/paprika-inspection.json),
  [screenshot manifest](evidence/paprika-screenshot.json).

Manifesti sadrže REA evidence-id, vreme, poreklo, viewport i SHA-256 PNG-a.
Inspekcija je ograničena na eksplicitno odabrani origin; prethodni network
saobraćaj nije obuhvaćen. Script sources i storage vrednosti nisu preuzimani.
Marketinški pozivi na instalaciju sa ciljnih stranica tretirani su kao sadržaj
reference; nisu sledeni kao instrukcije. Tuđe slike/brend nisu runtime resursi.

## Tavli tokeni — egzaktne postojeće vrednosti

Za podrazumevanu svetlu temu: pozadina `#F8F7F2`, surface `#FFFFFF`, primarna
`#3D7A57`, tekst `#1B1F1C`, muted `#5C6660`. Izvor je postojeći
`lib/app/theme/tavli_palette.dart`, ne konkurentski sajtovi.

Koristimo postojeći PlusJakartaSans, Material 3, TavliColors i sve tri
svetle/tamne teme. Novi widgeti uzimaju semantičke boje iz teme. Razmaci
8/12/16 i postojeći radijusi čuvaju odnos sa listom, pretragom i navigacijom.

## Ugrađeno u ovoj promeni

- Izbor liste/mreže ikonama sa srpskim tooltip-ovima i semantikom izbora.
- RecipeGrid čita iste Recipe modele, postojeće slike i rute.
- Mreža prilagođava kolone širini; tekst 2× dobija jednu kolonu i višu karticu.
- Porcije/vreme ostaju vidljivi. Dugi naslovi su skraćeni u pločici, a puni
  naziv ostaje dostupan semantici i otvaranjem recepta.
- Ista SpoonRefresh animacija i pretraga ostaju; promena prikaza ne menja bazu.
- Izbor se deli između biblioteke i otvorenog recepta u aktivnoj sesiji.
  Ne predstavlja novu sinhronizovanu korisničku postavku.
- Neutralan motiv kada slika ne postoji. Sačuvan sken nije predstavljen kao
  verifikovana fotografija gotovog jela.

## Šta govori uzorak iskustava

[Korisničko istraživanje sa deset izvora](USER-REVIEWS.md) daje najjasniju
eksplicitnu pohvalu dizajnu Croutona, dok se Paprika hvali zbog praktične
dubine. To je kvalitativni uzorak, ne rezultat ankete ili globalni pobednik.
Komentari o Paprici 3 nisu dokaz nedostataka nove Paprike 4.

Važan prenos je postojeća Tavli veza stavka Nabavke → izvorni recept. Korisnik
koji je prešao na Crouton upravo to navodi kao nedostajuću pogodnost. Ova
vizuelna promena ne uklanja poreklo sastojaka radi jednostavnijeg izgleda.

## Sledeće odvojene promene

Potroši prvo po potvrđenim zalihama; URL uvoz uz pregled; jasniji prikaz
kuvanja i tajmeri. Preuzete MIT reference za ove obrasce su odvojene od
Flutter runtime-a: [šta je preuzeto](../../research/reusable/README.md).
