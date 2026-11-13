# 046 — Kalorije i makroi po porciji recepta

**Status**: Implementirano. Trello: „Kalorije i makroi po porciji recepta“ (Dev 1).
Zavisi od 045 (nutritivne vrednosti uz namirnicu).

Recept sa povezanim sastojcima prikazuje „Po porciji ~420 kcal · proteini 25 g
· masti 12 g · ugljeni hidrati 50 g“ i pokrivenost („Računato za 7 od 8
sastojaka.“) ispod sastojaka na ekranu recepta. Recept bez ijednog pokrivenog
sastojka ne prikazuje ništa umesto pogrešnog broja.

## Računanje (na uređaju)
`recipeNutritionPerServing(ingredients, servings:, catalog:)` u
`lib/domain/recipe_nutrition.dart` (koriste ga i Dev 2 i Dev 3). Težina
sastojka u gramima: konverzija namirnice (čen), pa mase (g, kg, dkg) direktno,
zapremine (ml, dl, kašika…) preko gustine ml namirnice, komadi preko težine
komada. Grami / 100 × vrednost namirnice, zbir / porcije.
Sastojak bez namirnice, bez vrednosti, bez količine ili sa jedinicom koja se ne
može pretvoriti u grame (npr. čaša brašna bez konverzije, jogurt bez gustine)
ne ulazi u zbir i vidi se u pokrivenosti. Nepoznato nije nula.

## Težine (iz USDA porcija, CC0)
- Gustina ml namirnica (17) iz reda sa zapreminom (`fl oz`, `cup`, `tbsp`,
  `tsp`); jogurt nema volumenski red, pa ostaje nepoznat.
- Težina komada (14), prosečne težine koje je potvrdio Uroš 13.11.2026:
  limun 58 g, limeta 67 g, pomorandža 131 g, jabuka 182 g, kruška 178 g, banana
  118 g, breskva 150 g, kajsija 35 g, avokado 201 g, jaje 50 g (USDA „large“,
  jestivi deo), lepinja 60 g, kifla 43 g (donja procena), tortilja 49 g, supa
  kocka 4 g.
- Podaci: `supabase/catalog/unit_weights.csv` → `scripts/nutrition_seed.dart`
  (čita USDA `food_portion.csv`); server migracije `…200000_food_unit_weights.sql`
  (kolone `unit_grams`, `unit_grams_source`) i `…200100_…_seed.sql`; uređaj
  drift v22.

## Van opsega
- Prikaz u planu obroka i trackeru (kartice Dev 2/Dev 3 koriste funkciju).
- Alkohol i vlakna: kcal je objavljena USDA energija, ne 4/9/4.
