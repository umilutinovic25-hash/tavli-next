# Plan

Domen `lib/domain/time_budget.dart`: `DayBudget` (dan 1–7, limit aktivnog rada po obroku, prozor u minutima od ponoći), `checkTime` → staje / preko / nepoznato sa razlozima, provere unosa. `Recipe` i `RecipeSnapshot` dobijaju `activeMinutes` i `totalMinutes` (JSON ključevi samo kad postoje, pa stari zapisi ostaju isti); vreme se čita samo iz sačuvanog zapisa, a AI izmena zadržava potvrđeno vreme. Lokalno drift v13: kolone u `recipes` i tabela `day_time_budgets` (id `<domaćinstvo>-<dan>`); na serveru migracija 20261110120700 (kolone sa proverama, tabela sa RLS-om po članstvu, grants samo authenticated, tragovi brisanja, jedan red po danu). `TimeBudgetRepository` piše red i outbox u istoj transakciji. Prikaz: `TimeCheckNote` u predlogu, kartici i obroku; ekran `/plan/time`. Bez novih zavisnosti.

schemaVersion: grane 019–027 zauzimaju v6–v12, pa ova uzima v13; korak je idempotentan. Serverska migracija dolazi posle 027 (20261110120600).

## Constitution Check

I: srpski Latin; II: keš i outbox, RLS, grants, pgTAP sa dva naloga; III: AI se ne menja osim čuvanja potvrđenog vremena pri izmeni; IV: bez tajni; V: domen sa unapred poznatim rezultatima (utorak 20: 15/60 staje, 25/30 ne; prozor 18:00–18:45 i 60 ukupno; granice 20/21; staro vreme pripreme je nepoznato; nedelja 90 ne menja utorak), repozitorijum, migracije, mapiranje i widget testovi na telefonu i širokom ekranu; VI: oznake tekstom i ikonom, ne samo bojom; VII: jedan commit; VIII: jedan spec i grana iz main; IX: nova migracija, generisan drift kod, hook i provere.
