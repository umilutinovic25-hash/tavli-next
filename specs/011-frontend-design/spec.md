# 011 — Vizuelni jezik glavnih ekrana

## Cilj
Unaprediti postojeći Flutter frontend: prepoznatljiv Tavli identitet, jasna
hijerarhija glavnih ekrana i čitljiviji plan. Isti podaci, rute i akcije.

## Dizajn ugovor
- Publika: domaćinstvo koje planira obroke i kupovinu.
- Glavna akcija: napraviti plan, zatim otvoriti povezanu nabavku.
- Topla pozadina, postojeća zelena tema, lokalni Plus Jakarta Sans font.
- Miran raspored: veliki naslov, kratko objašnjenje, primarna akcija,
  kompaktan kalendar i pregledne kartice obroka. Bez dekorativnih metrika.
- Navigacija: četiri postojeća taba; na širokom ekranu brendirani bočni meni.
- Postojeće teme, animacije, smanjeno kretanje i prijava ostaju funkcionalni.
- Ostava ostaje iskreno označena kao planirana funkcija.

## Prihvatanje
1. Plan, Nabavka i Recepti imaju jasne naslove i razumljivu sledeću akciju.
2. Kartice prikazuju postojeće porcije, vreme i tekstualne statuse.
3. Telefon 320/390 px, tablet 768 px i desktop 1024/1440 px nemaju overflow;
   najskučeniji prikaz radi uz tekst 2×.
4. Postojeći tok Plan → obrok → nabavka, pretraga i avatar rade kao ranije.
5. Svetle i tamne postojeće teme koriste iste semantičke tokene.

## Novi UI tekst
„Tvoja nedelja, lakše.“; „Plan obroka“; „Sve za sledeći obrok, na jednom mestu.“;
„Tvoja kuhinja“; „Recepti“; „Sačuvaj ideje kojima se rado vraćaš.“;
„Nabavka“; „Od plana do pune korpe.“; „Izaberi obrok“.

## Van opsega
Implementacija 90 budućih funkcija, izmišljene fotografije i statistike,
novi backend ili novi sistem stanja. Ovo je prva implementacija vizuelnog pravca.
