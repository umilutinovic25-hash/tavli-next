# 019 — Sačuvane pretrage recepata

Korisnik kombinuje naziv, najveće vreme pripreme, obavezni i isključeni sastojak u postojećoj zbirci, čuva imenovanu pretragu, ponovo je primenjuje i briše. Pretrage su lične, sinhronizuju se kroz postojeći outbox i dostupne su iz lokalne baze bez mreže i nakon restarta.

Kriterijumi: svi zadati uslovi važe istovremeno; nepoznato vreme ne zadovoljava ograničenje, prazan/nepoznat spisak sastojaka ne zadovoljava filter uključivanja ni isključivanja. Poređenje sastojaka je normalizovano po postojećoj pretrazi, kao tekst sadržan u nazivu; ne tvrdi semantičko razumevanje ili sigurnost za alergije. Rezultati se ponovo računaju iz aktuelne zbirke. #02 rečnik sinonima nije u main i nije zavisnost ove grane; može se kasnije povezati bez promene sačuvanih kriterijuma.

UI: „Filteri“, „Do minuta“, „Sa sastojkom“, „Bez sastojka“, „Primeni“, „Sačuvaj pretragu“, „Naziv pretrage“, „Sačuvaj“, „Otkaži“, „Sačuvane pretrage“, „Pretraga po nazivu sastojka; nije provera alergena.“, „Sačuvane pretrage nisu učitane.“, „Obriši pretragu“, „Očisti filtere“, „Nema recepata za izabrane filtere.“, „Unesi pozitivan broj minuta.“, „Unesi naziv pretrage.“, „Pretraga nije sačuvana. Pokušaj ponovo.“, „Pretraga nije obrisana. Pokušaj ponovo.“
