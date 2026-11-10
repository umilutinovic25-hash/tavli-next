# Plan

Stavka plana (`meal_plan_entries`) dobija `kind` (`cook`/`away`, podrazumevano `cook` za sve postojeće redove), `away_reason` i `away_note`; lokalno drift v11, na serveru nova migracija 20261110120500 sa proverama (away traži razlog, cook nema razlog ni napomenu, napomena 1–80). Postojeći RLS i grants tabele važe. Nabavka (`reconcilePlan`) pravi izvor samo za `cook`, pa prelazak u `away` briše izvor kroz postojeći put (kupljeno ostaje); `isPlanned` ne broji obrok van kuće. `regenerableSlots` štiti `away`; `approve` pri izričitoj zameni vraća `kind = cook`. Nepoznata vrsta sa novije verzije zauzima mesto bez nabavke. Snimak kod `away` čuva prethodno jelo za `restoreMeal`. Bez novih zavisnosti.

schemaVersion: grane 019–025 zauzimaju v6–v10, pa ova uzima v11; korak je idempotentan. Serverska migracija dolazi posle 025 (20261110120400).

## Constitution Check

I: srpski Latin; II: keš i outbox, postojeći RLS, pgTAP sa dva naloga; III: nema AI; IV: bez tajni; V: domen (parser vrste, naslov, zaštita od ponovnog predloga), repozitorijum (0 potražnje, kupljeno ostaje, vraćanje jela, zaključan obrok, tuđi plan, izričita zamena), migracije, mapiranje i widget testovi na telefonu i širokom ekranu; VI: dijalog i dugmad rade tastaturom; VII: jedan commit; VIII: jedan spec i grana iz main; IX: nova migracija, generisan drift kod, hook i provere.
