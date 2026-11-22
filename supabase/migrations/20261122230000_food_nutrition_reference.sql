-- 023 / D1-011: attributed reference nutrition on shared catalog foods.
-- This adds storage only; no unreviewed candidate values are seeded.
alter table public.foods
  add column kcal_per_100g double precision
    check (kcal_per_100g is null or kcal_per_100g >= 0),
  add column protein_grams_per_100g double precision
    check (protein_grams_per_100g is null or protein_grams_per_100g >= 0),
  add column fat_grams_per_100g double precision
    check (fat_grams_per_100g is null or fat_grams_per_100g >= 0),
  add column carbs_grams_per_100g double precision
    check (carbs_grams_per_100g is null or carbs_grams_per_100g >= 0),
  add column nutrition_source text,
  add column nutrition_source_version text,
  add column nutrition_source_ref text,
  add constraint foods_nutrition_has_source
    check (
      (kcal_per_100g is null
        and protein_grams_per_100g is null
        and fat_grams_per_100g is null
        and carbs_grams_per_100g is null)
      or (
        nullif(btrim(nutrition_source), '') is not null
        and nullif(btrim(nutrition_source_version), '') is not null
        and nullif(btrim(nutrition_source_ref), '') is not null
      )
    );
