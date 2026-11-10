# YouTube „ai cookbook” — korisni nalazi i granice dokaza

Upit koji je korisnik dostavio: https://www.youtube.com/results?search_query=ai+cookbook

Datum pregleda: 9. novembar 2026. Web fetch je bio throttled, pa je pretraga otvorena u browseru i pročitani su naslovi, autori i kratki opisi 18 video-rezultata. [Strukturisana evidencija](youtube-search.json) čuva kanonske linkove i nivo dokaza.

**Nisu gledani celi video-snimci.** Posle pretrage pročitani su relevantni segmenti dostupnog engleskog titla za video How To Cook That; ostali kandidati ostaju metadata-only. Nisu testirane implementacije iz videa. Revenue i „works” tvrdnje iz naslova nisu verifikovane. Nikakav video, recept, ilustracija ili pun transkript nije kopiran u aplikaciju/repozitorijum.

## Korisni kandidati

| Video | Šta je stvarno posmatrano | Preporuka za Tavli |
|---|---|---|
| [AI Cooking Disasters: Debunking Facebook’s Fake Recipes — How To Cook That](https://www.youtube.com/watch?v=SVaYJgmPvCg) | Pročitani relevantni engleski titlovi; segmenti oko 02:02 i 03:37–04:10 opisuju neusaglašenost dobijenog jela i ilustracije i probleme praktične pripreme. | F084/F085: proveru strukture dopuniti stvarnim cook-test dokazom; slika i uverljiv tekst nisu potvrda izvodljivosti. |
| [I Tested AI Generated Recipes! — Honeysuckle](https://www.youtube.com/watch?v=Ci-Evf8nQH4) | Metapodaci opisuju praktično testiranje AI recepata. | F047/F085: cook log vezati za tačnu verziju, porcije i opremu; razlikovati iskustvo osobe od univerzalne potvrde ispravnosti. |
| [I turned a 222-yr-old cookbook into an AI knowledge base — Scott Bartnick](https://www.youtube.com/watch?v=pO4otuMr5tc) | Naslov najavljuje bazu znanja iz starog kuvara; prihod nije proveren. | F019/F058/F084: ingest sa izvorom na nivou stranice/odlomka, jedinice i kontekst; retrieval mora vratiti pravi recept/verziju. Ne zaključiti da je bilo koji konkretan sadržaj slobodan za kopiranje. |
| [How to Make a Cookbook or Recipe Book with Inkfluence AI — Inkfluence AI](https://www.youtube.com/watch?v=zPZ8RZ4tqZY) | Naslov/opis se odnose na izradu ilustrovanog kuvara. | F021: korisnik uređuje raspored stranica, sadržaj i naslovnu stranu; proveriti prelom, srpska slova i razliku između stvarne fotografije i generisane ilustracije. |

## Šta dodaje planu, bez veštačkog proširivanja broja 90

1. **Poreklo na nivou tvrdnje:** sastojak/količina/korak imaju page/timestamp locator ili eksplicitno „AI predlog”; uvezeno i generisano se ne stapaju bez oznake. Ovo precizira F019/F025/F028/F058.
2. **Kvalitet kroz izvršavanje:** neusaglašeni sastojci, neizvodljivi koraci i neproverene zamene ulaze u eval fixtures. F085 dobija dokaz testiranja, ne samo ikonicu.
3. **Originalni medij ostaje referenca:** video-import treba segment/timestamp i dovoljan transkript, a ne rekonstrukciju zamišljenih mera iz same slike. F025 ostaje uslovan i pregledan.
4. **Ilustracija nije rezultat kuvanja:** generisana naslovna slika kuvara ili jela ima jasnu oznaku i ne koristi se kao dokaz uspešno napravljenog recepta.
5. **PDF je završna obrada:** ulepšavanje kuvara tek nakon stabilnog recipe modela, validacije i čitljivog print layout-a; ne preskače proveru sadržaja.

## Manje relevantni rezultati

Veći deo prvog skupa odnosi se na prodaju AI PDF/KDP kuvara i marketing, a pojedini koriste „cookbook” kao naziv zbirke AI programerskih recepata. To nisu dokazi o kvalitetu meal-planning arhitekture, bezbednosti hrane ili finansijskom uspehu. Njihov marketinški kod/sadržaj nije preuzet.

## Sledeći proverljivi korak

Za odabrani video zabeležiti datum, naslov, autora i dozvoljeno dostupan transkript/tačne segmente; svaku preporuku povezati sa segmentom i lokalnim acceptance scenarijem. Ako transkript nije dostupan, kandidat ostaje metadata-only i ne postaje potvrđena implementaciona referenca.

## Jedna proverena tekstualna opservacija

Video `SVaYJgmPvCg`, kanal How To Cook That, metadata datum objave 21.03.2025. Preuzet je samo dostupni ručni engleski titl radi čitanja, bez video/audio datoteke. Relevantni pročitani segmenti: 02:02–02:19, 03:37–04:10 i 04:36–05:08. Oni podržavaju zahtev da ilustracija nije dokaz rezultata i da sadržaj treba proveriti praktičnom pripremom. To ne predstavlja nezavisni eksperiment Tavli tima niti dokaz o svim AI receptima. Naslov, autor i tekstualni segmenti su provereni; prijavljeni rezultati iz videa nisu samostalno ponovljeni.
