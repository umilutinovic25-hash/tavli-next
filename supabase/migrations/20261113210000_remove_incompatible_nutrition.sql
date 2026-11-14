-- Pogrešno stanje namirnice nije približna nutritivna vrednost: mlevena
-- kafa/čaj nisu napitak, kokosovo brašno nije sirov kokos, prezle nisu mek
-- hleb, a lisnato testo u receptu nije već pečeno. Do pregledanog zapisa
-- vrednosti ostaju nepoznate. Primenjene seed migracije se ne menjaju.
-- Ne gazimo eventualnu naknadnu ispravku iz drugog izvora ili USDA zapisa.
update public.foods f
set kcal_100 = null, protein_100 = null, fat_100 = null, carbs_100 = null,
    nutrition_source = null, nutrition_ref = null
from (values
  ('f_kafa', '171890'),
  ('f_caj', '173227'),
  ('f_kokos', '170169'),
  ('f_prezle', '174924'),
  ('f_lisnato_testo', '172738')
) as incompatible(id, nutrition_ref)
where f.id = incompatible.id
  and f.household_id is null
  and f.nutrition_source = 'usda-sr-legacy-2018-04'
  and f.nutrition_ref = incompatible.nutrition_ref;
