# Contract: `supabase/catalog/foods.csv` → seed migracija

Jedan red = jedna zajednička namirnica. UTF-8, zaglavlje obavezno, separator `,`, polja sa zarezom pod navodnicima.

| kolona | primer | pravilo |
|---|---|---|
| id | `f_jaje` | `^f_[a-z0-9_]{1,60}$`, jedinstven, nikad se ne menja ni ne briše |
| name | `jaje` | nominativ jednine, mala slova; automatski i alias |
| category | `mlečni proizvodi i jaja` | iz `ingredientCategories` |
| base_unit | `kom` | `kom` \| `g` \| `ml` |
| aliases | `jaja\|jajce\|jajeta` | normalizovani, `\|`-odvojeni; jedinstveni u celom fajlu |
| conversions | `čen=5000000` | `jedinica=factor_micros`, `\|`-odvojeni; prazno dozvoljeno |
| allergens | `eggs` | kodovi iz `euAllergens`, `\|`-odvojeni |

Generator (`dart run scripts/catalog_seed.dart`) odbija fajl (izlaz ≠ 0) kad: id ili alias nije jedinstven, kategorija/jedinica/alergen nije poznat, konverzija pokriva već pokrivenu jedinicu. Izlaz je SQL sa `insert … on conflict (id) do nothing`; postojeći id se nikad ne menja kroz seed — ispravka zajedničke namirnice je nova, ručno pisana migracija.
