# Plan

Nova tabela `CookSoonItems` (drift v10) i `cook_soon_items` na serveru (RLS po članstvu u domaćinstvu, `GRANT` samo za authenticated, tragovi brisanja, strani ključ na recept `on delete set null`). `CookSoonRepository` piše red i outbox u istoj transakciji; `schedule` pravi `PlanDraft` za jedno mesto (`scheduleDraft`) i poziva postojeći `MealPlanRepository.approve` unutar svoje transakcije, pa provera zastarelosti, zaštita zaključanih/skuvanih/prošlih obroka i usklađivanje nabavke ostaju na jednom mestu. Brisanje recepta lokalno prekida vezu i čuva snimak. Bez novih zavisnosti.

schemaVersion: grane 019–023 zauzimaju v6–v9, pa ova grana uzima v10; korak je idempotentan (pravi tabelu samo ako je nema). Serverska migracija 20261110120400 dolazi posle 023 (20261110120300).

## Constitution Check

I: srpski Latin; II: keš i outbox, RLS i grants, pgTAP sa dva naloga; III: nema AI; IV: bez tajni; V: testovi repozitorijuma (zastareo plan, zaključan obrok, obrisan recept, 0 izvora nabavke za 10 stavki), migracije, mapiranja i widget testovi na telefonu i širokom ekranu; VI: dijalog i meni rade tastaturom, bez prevlačenja; VII: jedan commit; VIII: jedan spec i grana iz main; IX: nova migracija, generisan drift kod, hook i provere.
