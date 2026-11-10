# 021 — Šabloni nedelje

Korisnik čuva izabranu nedelju sačuvanog plana kao imenovan šablon i primenjuje je na drugu nedelju, uz izbor broja porcija. Pre potvrde vidi datume i obroke; potvrda pravi zaseban plan, nove obroke i izvore nabavke. Snimci recepata ostaju upotrebljivi i posle izmene ili brisanja recepta. Prazna mesta ostaju prazna; stanje skuvano i zaključano se ne prenosi. Postojeći planovi i kupljene stavke ostaju netaknuti. Čuvanje i primena rade offline i sinhronizuju se u domaćinstvu.

## Kriterijumi

- Šablon obuhvata izabranu kalendarsku nedelju (presek plana); ne može se sačuvati bez obroka sa snimkom. Sačuvani snimak je nezavisan od kasnijih izmena plana.
- Datumi se mapiraju po danu u nedelji; primena bira buduću ili tekuću nedelju i 1–20 porcija za svaki novi obrok. Korisnik potvrđuje pregled pre upisa.
- Svaka primena ima nove identitete plana i obroka; ponovljene primene su zasebni planovi. Nabavka se izračunava postojećim mehanizmom iz novih obroka i izabranih porcija; postojeće kupovine ostaju očuvane.
- Izolacija dva domaćinstva, lokalna migracija, outbox i sinhronizacija imaju testove. Test sa 1 kg za 4 porcije i primenom na 8 porcija očekuje 2 kg.

## Tekst interfejsa

„Sačuvaj nedelju kao šablon“, „Naziv šablona“, „Sačuvaj“, „Šabloni nedelje“, „Primeni šablon“, „Nedelja“, „Porcije po obroku“, „Pregled“, „Sačuvaj plan“, „Otkaži“, „Nema sačuvanih šablona“, „Šablon je sačuvan“, „Šablon nije sačuvan. Pokušaj ponovo.“, „Plan nije sačuvan. Pokušaj ponovo.“, „U ovoj nedelji nema obroka koje možeš sačuvati.“

Dodatne poruke: „Šablon“, „Šabloni trenutno nisu dostupni.“, „U ovoj nedelji nema obroka sa sačuvanim receptom ili neki recept nedostaje.“ Ako bar jedan obrok u izabranoj nedelji nema sačuvan snimak recepta, šablon se ne čuva delimično.
