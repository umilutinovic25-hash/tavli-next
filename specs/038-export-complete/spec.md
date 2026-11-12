# 038 — Potpun lični izvoz (sve tabele + sopstveno članstvo)

Dopuna izvoza ličnih podataka (privatnost, 036 format 2). „Profil → Izvezi moje podatke“ sada izvozi sve podatke **aktivnog** domaćinstva i podatke same osobe, uključujući njeno članstvo. Format izvoza 2 → 3. Bez promena baze i servera.

Novi tekst (politika privatnosti, „Vaša prava“ → Izvoz): „Obuhvata podatke aktivnog domaćinstva i vaše članstvo u njemu, bez podataka drugih članova.“

## Odluke (Uroš, 2026-11-12)
- Samo **sopstveno** članstvo: bez spiska članova, imena ni imejlova drugih ljudi.
- Samo **aktivno** domaćinstvo; druga domaćinstva osobe ne ulaze.
- Ocene: samo ocene same osobe, za recepte aktivnog domaćinstva.
- Poreklo nabavke (izvori, doprinosi, raspodela zalihe) ulazi, da izvoz bude potpun.

## Prihvatanje
- Nove sekcije, posle postojećih: `membership` (objekat), `recipeVersions`, `ratings`, `weekTemplates`, `cookSoonItems`, `householdPreferences`, `tasteProfile` (objekat ili null), `shoppingSources`, `shoppingContributions`, `supplyAllocations`.
- `membership`: `householdId`, `householdName`, `role`, `joinedAt` (iz keša članstva; `null` ako reda nema). Nikad drugi članovi.
- `ratings`: `userId` = osoba i recept iz aktivnog domaćinstva. Tuđe ocene i ocene recepata drugih domaćinstava ne ulaze.
- `tasteProfile`: red profila čiji je id `userId` osobe; JSON kao objekat.
- Sve ostale nove sekcije: redovi sa `householdId` aktivnog domaćinstva; JSON kolone kao objekti (neispravan JSON ostaje tekst).
- Postojeće sekcije i njihova polja se ne menjaju.
- Van izvoza ostaju: podešavanja aplikacije, stanje modela, outbox, kursori sinhronizacije, keš članova (imena drugih ljudi), tabela naloga. AI ključevi i tokeni nikad.
- Politika privatnosti i `docs/architecture.md` pominju format 3 i šta izvoz sadrži.

## Testovi (`test/data/personal_export_test.dart`)
- prazan izvor: redosled svih sekcija, `formatVersion` 3, `membership` i `tasteProfile` null.
- `collectPersonalExport`: nove sekcije sadrže samo redove aktivnog domaćinstva; ocene samo sopstvene i samo za recepte domaćinstva; članstvo samo sopstveno za aktivno domaćinstvo; imena iz keša članova nisu u fajlu.
- JSON kolone novih sekcija su objekti.

## Convergence 1 (2026-11-12)
- [x] T001 Bez reda u kešu članstva `membership` dolazi iz naloga sa `joinedAt: null` po spec: Prihvatanje/`membership` (partial)
