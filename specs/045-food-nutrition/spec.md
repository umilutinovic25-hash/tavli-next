# 045 — Nutritivne vrednosti uz namirnicu

**Status**: Implementirano. Trello: „Nutritivne vrednosti uz namirnicu“ (Dev 1).

Svaka zajednička namirnica iz kataloga (036) dobija kcal, proteine, masti i
ugljene hidrate na 100 g, sa izvorom i oznakom zapisa. Nepoznato ostaje prazno,
nikad nula. Računanje po porciji recepta je posebna kartica („Kalorije i
makroi po porciji recepta“).

## Izvor i uslovi korišćenja
- **USDA FoodData Central, SR Legacy (april 2018), CSV.** Podaci su javno dobro,
  licenca **CC0 1.0 Universal**, bez obaveze navođenja izvora
  (https://fdc.nal.usda.gov/api-guide, odeljak Licensing; provereno 13.11.2026).
  Fajl: `FoodData_Central_sr_legacy_food_csv_2018-04.zip` (6 074 592 bajta) sa
  https://fdc.nal.usda.gov/download-datasets.
- **Uslove korišćenja je potvrdio čovek (Uroš) 13.11.2026.**
- **Ciqual (ANSES) nije uvezen.** Pokrivenost je 97% samo sa USDA. Ako se bude
  uvozio: „Licence Ouverte / Open Licence“ (Etalab) traži navođenje izvora;
  licencu novije verzije (2025) treba potvrditi na zvaničnoj stranici pre uvoza.
- AI ne daje brojeve. Mapiranje namirnica na USDA zapise je predlog koji se
  pregleda u `supabase/catalog/nutrition_map.csv`; brojeve čita skripta iz
  izvora, a opis u mapiranju mora da se poklapa sa USDA zapisom.

## Pokrivenost
166 od 171 namirnica (97%). Bez zapisa (vrednost ostaje nepoznata): ovseno
mleko, kajmak, vanilin šećer, začinska mešavina, ajvar (nema odgovarajućeg
generičkog USDA zapisa; nije izmišljeno). Pojedina mapiranja su najbliža
generička namirnica (npr. „kiselo mleko“ → cultured buttermilk, „kobasica“ →
sirova svinjska kobasica); kcal je objavljena USDA energija, ne 4/9/4.

## Podaci i kod
- Server: migracije `…190000_food_nutrition.sql` (kolone, ograničenja „sve ili
  ništa“ i opseg) i `…190100_food_nutrition_seed.sql` (generisana, ažurira samo
  zajedničke namirnice bez vrednosti).
- Uređaj: drift v21 (`foods`: `kcal100`, `protein100`, `fat100`, `carbs100`,
  `nutritionSource`, `nutritionRef`), sync, `Food.nutrition` (null = nepoznato).
- Izvoz se ne menja: izvozi se samo sopstvene namirnice domaćinstva, a one nemaju
  nutritivne podatke.

## Ponovno generisanje
Preuzmi i raspakuj SR Legacy CSV van repoa, pa:
`dart run scripts/nutrition_seed.dart <usda-direktorijum>`.
Ispravka vrednosti ili nova namirnica ide kroz novu migraciju, ne izmenom
postojeće.
