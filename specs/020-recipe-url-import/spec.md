# 020 — Uvoz recepta sa adrese

Korisnik unosi javnu adresu recepta, pregleda izvučeni recept i izričito ga čuva u postojeću zbirku. Izvorna adresa ostaje uz recept i kroz izmene, verzije i sinhronizaciju. Neispravna adresa, nedostupan sajt ili nedostatak strukturisanog recepta ne stvaraju zapis. Količine koje nije moguće pouzdano razdvojiti ostaju kao izvorni tekst sastojka i označene su za proveru. Porcije bez pouzdane vrednosti imaju naznačenu početnu vrednost 2.

Preuzimanje je serversko; svaki URL i preusmerenje se ograničava na HTTP(S) i javne adrese, a konekcija se vezuje za proverenu adresu. Bez slanja kolačića i korisničkih zaglavlja; vreme, broj preusmerenja i veličina odgovora su ograničeni. Podržava se schema.org Recipe JSON-LD; AI se ne koristi dok bezbedan fallback nije potvrđen. Uvoz zahteva mrežu, sačuvani recept radi offline.

UI tekst: „Sa internet adrese“, „Adresa recepta“, „Pregledaj recept“, „Proveri uvezene sastojke i porcije pre čuvanja.“, „Izvor“, „Nije moguće učitati recept sa ove adrese. Proveri adresu i pokušaj ponovo.“, „Na stranici nije pronađen strukturisan recept.“, „Previše uvoza zaredom. Sačekaj malo pa pokušaj ponovo.“, „Sačuvaj“, „Odbaci“.

Prihvatanje: JSON-LD primer vraća očekivan naziv, sastojke, korake i adresu; neuspeh ne upisuje recept; korisnik može da ispravi uvoz pre čuvanja; adresa ostaje u bazi, sinhronizaciji i verzijama; privatne, lokalne, specijalne IP adrese i preusmeravanja na njih ne mogu da se učitaju, uključujući DNS rebinding; ograničenja važe na telefonu i širokom ekranu.
