# 022 — Režim kuvanja

**Branch:** 022-cooking-mode · **Status:** Implementirano; draft PR

## Opseg i odluke

Osoba pokreće kuvanje iz sačuvanog recepta ili odobrenog snimka obroka u planu. Sastojci i koraci imaju nezavisne ček-liste, a prethodni/sledeći menjaju istaknuti korak. Oznake važe samo za otvorenu sesiju i mogu se poništiti; izlazak ih odbacuje. Nema upisa u recept, plan, nabavku ili ostavu. Snimak iz plana ostaje izvor i kada je recept obrisan, a količine prate porcije obroka. Bez koraka prikaz to jasno kaže; dopunjavanje koraka iz plana je zaseban još nedovršen tok 010.

Postojeći izbor „Ne gasi ekran” ostaje dostupan i zapamćen. Režim oslobađa svoj wake lock po izlasku; pri povratku u detalj recepta postojeće pravilo otvorenog recepta ponovo važi. Telefon prikazuje sastojke i korake redom, širok prozor sastojke levo i korake desno. Sve radi offline.

## Prihvatanje

1. Otvoriti recept, označiti i vratiti sastojak i korak, kretati se kroz korake i zatvoriti; podaci recepta i ostave se ne menjaju, nova sesija je prazna.
2. Otvoriti kuvanje iz plana: prikazati snimak i količine prema porcijama, uključujući obrisan izvor; bez koraka prikazati jasnu poruku.
3. Sa uključenim ekranom prelaz i izlazak oslobađaju zahtev režima; postojeća opcija i ponašanje detalja recepta ostaju funkcionalni.
4. Proveriti telefon i široki ekran, prazan sadržaj, dostupnost kontrola i postojeće susedne tokove.

## Novi UI tekst

„Kreni sa kuvanjem”, „Kuvanje”, „Sastojci”, „Priprema”, „Korak {n} od {ukupno}”, „Prethodni”, „Sledeći”, „Nema sastojaka.”, „Koraci pripreme nisu uneti.”, „Oznake važe samo tokom ovog kuvanja.”, „Ne gasi ekran: uključeno”, „Ne gasi ekran: isključeno”.
