# 039 — Alergije po osobi i zaštitna provera AI recepata

Plan posle 036, tačka 2. Danas su alergije jedan tekstualni spisak domaćinstva koji ide AI-ju samo kroz uputstvo; ništa ne proverava šta je AI vratio. Posle 039 svaki član upisuje svoje alergije, za svaki obrok važe sve zajedno, a kod proverava svaki AI recept preko kataloga namirnica (036) pre nego što ga osoba vidi.

## Odluke (Uroš, 2026-11-12)
- AI recept sa alergenom se **odbija i traži se novi**.
- **Svako upisuje svoje** alergije; važe **sve zajedno** (unija članova aktivnog domaćinstva) za svaki obrok.
- Unos: izbor sa **14 EU alergena** + **slobodan unos** za ostalo.
- Sastojak koji katalog ne prepoznaje: recept se **prihvata uz oznaku** „Nepotvrđeno, proveri alergene“.
- Recept sa **fotografije ili linka** se ne odbija (osoba uvozi baš taj recept); dobija jasno upozorenje.
- Postojeće alergije domaćinstva prelaze osobi koja ih je upisala (`updated_by`), inače vlasniku; zajednički spisak se prazni.
- Ostali članovi vide tvoje alergije (potrebno za proveru); politika privatnosti to navodi.

## Pravilo provere (domen, čist Dart)
Za sastojak se namirnica uzima iz `foodId`, inače iz tačnog aliasa (`FoodCatalog.match`).
- **EU alergen** pogađa sastojak čija namirnica ima taj kod u katalogu.
- **Slobodan unos** pogađa sastojak kad (a) termin u katalogu pokazuje na istu namirnicu, ili (b) normalizovan naziv sastojka sadrži sve reči termina kao cele reči („sveže jagode“ ⊇ „jagode“). Ovde je lažna uzbuna prihvatljiva, propust nije.
- **Nepotvrđeno**: postoji bar jedna alergija u domaćinstvu i bar jedan sastojak bez poznate namirnice. Ne odbija recept.
- Bez alergija u domaćinstvu provera ne radi ništa (nema oznaka).

## Prihvatanje
1. **Moje alergije** (Profil → Preferencije): čipovi za 14 EU alergena i lista „Ostalo“ (do 30, do 40 znakova). Upis kroz outbox, radi offline. Ispod: „Važi za sve obroke: …“ sa unijom svih članova.
2. **Po nazivu** i **izmena kroz razgovor**: recept sa alergenom → AI se pita još jednom, uz spisak sastojaka i alergena koje mora izbaciti. Ako i drugi odgovor ima alergen, recept se ne prikazuje; poruka „Nije pronađen recept bez alergena članova domaćinstva (…). Promeni zahtev i pokušaj ponovo.“ Najviše jedan ponovni zahtev. Kod izmene se odbijaju samo **novi** alergeni: pogodak koji je već bio u trenutnom receptu (npr. uvezenom sa slike) ne odbija izmenu (odluka Claude, P1).
3. **Plan obroka**: recepti iz biblioteke sa alergenom se ne nude AI-ju. Novi recepti iz sažetaka sa alergenom traže se još jednom, samo oni. Ako i tada imaju alergen, ta mesta ostaju prazna i generisanje staje sa istom porukom; nastavak traži samo prazna mesta.
4. **Fotografija i link**: pregled pre čuvanja i detalj recepta pokazuju „Sadrži alergen člana: …“ (istaknuto); recept se može sačuvati.
5. Uz alergije u domaćinstvu i nepotvrđen sastojak pregled i detalj pokazuju „Nepotvrđeno, proveri alergene“.
6. AI upit dobija uniju alergija (EU nazivi na engleskom + slobodan unos), kao i do sada prvu i zabranjenu.
7. Član koji napusti domaćinstvo (ili bude uklonjen) više ne nosi alergije u njega: server briše njegov red.
8. Lični izvoz sadrži sopstvene alergije (`allergies`), format 3 → 4.

## Novi tekst
„Moje alergije“, „Važi za sve obroke kad kuvaš za domaćinstvo. Ostali članovi vide tvoje alergije.“, „Ostalo“, „Npr. jagode. Proverava se po nazivu sastojka.“, „Dodaj alergiju“, „Važi za sve obroke: …“, „Niko u domaćinstvu nije upisao alergije.“, „Sadrži alergen člana: …“, „Nepotvrđeno, proveri alergene“, „Nije pronađen recept bez alergena članova domaćinstva (…). Promeni zahtev i pokušaj ponovo.“; politika privatnosti: „Alergije koje upišeš vide ostali članovi domaćinstva, da bi aplikacija mogla da proveri recepte za sve.“

## Van opsega
Ko jede koji obrok (predlog 57); dijeta i „ne volim“ po osobi; provera dijete u kodu; promena AI šeme odgovora (037).
