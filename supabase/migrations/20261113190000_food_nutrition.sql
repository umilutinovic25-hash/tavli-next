-- Nutritivne vrednosti namirnice na 100 g (kcal, proteini, masti, ugljeni
-- hidrati) sa izvorom. Prazno = nepoznato (nikad nula iz neznanja). Sve ili
-- ništa: vrednosti uvek dolaze sa izvorom i oznakom zapisa. Kolone nasleđuju
-- postojeći RLS i grantove tabele foods.
alter table public.foods
  add column kcal_100 numeric(7, 2),
  add column protein_100 numeric(7, 2),
  add column fat_100 numeric(7, 2),
  add column carbs_100 numeric(7, 2),
  add column nutrition_source text,
  add column nutrition_ref text;

alter table public.foods add constraint foods_nutrition_all_or_none check (
  (kcal_100 is null) = (protein_100 is null)
  and (kcal_100 is null) = (fat_100 is null)
  and (kcal_100 is null) = (carbs_100 is null)
  and (kcal_100 is null) = (nutrition_source is null)
  and (kcal_100 is null) = (nutrition_ref is null)
);
alter table public.foods add constraint foods_nutrition_range check (
  (kcal_100 is null or kcal_100 between 0 and 900)
  and (protein_100 is null or protein_100 between 0 and 100)
  and (fat_100 is null or fat_100 between 0 and 100)
  and (carbs_100 is null or carbs_100 between 0 and 100)
  and (nutrition_source is null or char_length(nutrition_source) between 1 and 60)
  and (nutrition_ref is null or char_length(nutrition_ref) between 1 and 60)
);
