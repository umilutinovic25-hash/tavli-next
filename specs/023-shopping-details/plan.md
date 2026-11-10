# Plan

Nadograditi ShoppingItems, ShoppingRepository i postojeći outbox i privatni photo storage. Lokalna migracija čuva stare redove, serverska dodaje opcione kolone postojećoj RLS tabeli. Fotografije koriste jedinstvene postojeće putanje, članstvo i pravila privatnog bucket-a. Proveriti ažuriranje, uklanjanje, offline ponovni pokušaj, izolaciju dva domaćinstva, migraciju, UI i obračun. Bez novih zavisnosti.

## Constitution Check

I: srpski Latin; II: keš i outbox, privatni storage i RLS; III: nema AI; IV: bez tajni; V: testovi i lokalni pgTAP; VI: prilagodljiv dijalog; VII: jedan commit; VIII: jedan spec i grana iz main; IX: migracije i generisani drift kod, hook i provere.

Grane 012/014 ostaju nezavisne; nisu preduslov. Pri integraciji proveriti da li njihove izmene nad istim redovima i migracijama zahtevaju usklađivanje verzije.
