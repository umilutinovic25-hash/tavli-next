# 035 — Predlog plana poštuje vreme po danu (predlog 34)

Dopuna 028: vreme po danu („Vreme po danu“ u Planu) sada ulazi u AI predlog plana, a ne samo u prikaz posle predloga. Ništa se ne menja u bazi ni na serveru; nema novog teksta u aplikaciji.

## Prihvatanje
- Predlog plana, ponovni predlog i zamena jednog obroka šalju AI-ju ograničenje svakog traženog dana (najviše aktivnog rada po obroku i prozor za kuvanje). Dani bez ograničenja se ne pominju.
- Recepti iz biblioteke se nude AI-ju zajedno sa potvrđenim aktivnim i ukupnim vremenom, kad postoji.
- Ako AI za neki dan izabere recept iz biblioteke čije potvrđeno vreme prekoračuje taj dan, ta mesta se traže još jednom, uz spisak predugih recepata. Drugih mesta se ponovni zahtev ne tiče.
- Ako ni ponovljen predlog ne staje, obrok ostaje i u pregledu ima postojeću oznaku „Preko vremena“ (028). Nema trećeg zahteva.
- Recept bez potvrđenog vremena se ne traži ponovo; ostaje „Vreme nepoznato“ (028). Novi AI recepti i dalje nemaju potvrđeno vreme.
- AI pozivi idu kroz `AIRouter`; greške se prikazuju kao i do sada.

## Testovi
- `test/ai/meal_plan_ai_test.dart` (grupa „vreme po danu“): ograničenje i vreme recepta u upitu; ponovni zahtev samo za mesto koje ne staje; najviše jedan ponovni zahtev; nepoznato vreme bez ponovnog zahteva.
- `test/features/planning/time_budget_test.dart`: „Predloži plan“ šalje AI-ju vreme po danu.
