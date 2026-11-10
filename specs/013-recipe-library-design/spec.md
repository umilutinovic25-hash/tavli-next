# 013 — Pregled biblioteke po uzoru na proverene aplikacije

## Zadatak
Preuzeti korisne obrasce dizajna i primereno licenciran referentni kod,
proveriti korisnička iskustva i primeniti prvi mali deo u stvarnoj aplikaciji.

## Dizajn ugovor
Biblioteka recepata je kolekcija za brzo biranje, a lista daje gušći prikaz.
Zadržati postojeću listu i dodati izbor mreže. Crouton je uzor za mirnu
hijerarhiju, Umami za pregled kolekcije, Paprika za dostupne metapodatke.
Koristiti postojeći Material 3, Tavli palete i lokalni font. Nema novog brenda.

## Prihvatanje
- Lista/mreža koriste iste recepte, pretragu, izbor i rute.
- Porcije i vreme se vide i u mreži; nema izmišljenih fotografija.
- Sačuvana slika je slika recepta, ne tvrdnja o fotografiji gotovog jela.
- Mreža prilagođava broj kolona širini i koristi jednu pri velikom tekstu.
- Ostaju refresh animacija, postojeće teme i tok dodavanja.
- Telefon, tablet, desktop, tekst 2×, dugi nazivi i prazni rezultati rade.
- Preuzeti izvorni kod ima commit, hash i punu licencu; stoji van runtime-a.

## Novi UI tekst
„Prikaži listu“; „Prikaži mrežu“. Mreža zadržava postojeće nazive recepata,
porcije i vreme iz podataka. Tooltips i izabrano stanje su pristupačni.

## Granice
Ne kopirati tuđi brend ili komercijalni kod. Ne prenositi SQL/Rust/Python
direktno u bazu ili runtime. Ne menjati modele/podatke zbog vizuelnog prikaza.
Izveštaj o javnom sajtu nije analiza unutrašnjosti zatvorene mobilne aplikacije.
