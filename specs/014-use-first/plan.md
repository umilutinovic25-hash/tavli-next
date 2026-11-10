# Plan
Grana iz origin/main, nezavisna od nezavršenih 011/012/013. Koristiti isti
PantryRepository, postojeće tabele i rezervacije; novi read-only projection
spaja Ostavu i supply_allocations. Bez dupliranja CRUD-a grane 012.

1. Test-first pure domain: količine, partije, rokovi, rezerva i rangiranje.
2. Read-only repository projection i test izolacije/stream-a/bez upisa.
3. Riverpod spaja postojeću zbirku i projection sa injektovanim satom.
4. Ekran i globalni ulaz preko TabAppBar, postojeće rute recepata.
5. Testovi, vizuelni pregled, kompatibilnost svih prethodnih promena i PR.

Grocy MIT notice je u third_party/grocy; adaptira se princip iz 0225.sql,
ne njegova šema ili pravilo bodovanja isteka. Veštine: frontend-ui-engineering
i api-and-interface-design, za UI i mali read-only ugovor domenskog modula.

Ustav I–IX: srpski Latin; postojeći account/cache bez novih upisa; bez AI;
bez tajni; test-first domain, widget ključni tok; responsive; jedna funkcija;
nova spec/grana; bez zavisnosti, šeme ili generisanih fajlova. Nema odstupanja.
