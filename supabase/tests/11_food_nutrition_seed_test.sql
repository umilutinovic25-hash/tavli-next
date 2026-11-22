begin;
select * from no_plan();

select is(
  (select count(*) from public.foods where household_id is null),
  334::bigint,
  'reviewed initial catalog has 334 shared foods'
);
select is(
  (select count(*) from public.foods
   where household_id is null and kcal_per_100g is not null
     and protein_grams_per_100g is not null
     and fat_grams_per_100g is not null
     and carbs_grams_per_100g is not null
     and nutrition_source = 'USDA FoodData Central'
     and nutrition_source_version = 'SR Legacy 2018-04'
     and nutrition_source_ref is not null),
  308::bigint,
  'at least 90 percent have four attributed nutrition values'
);
select is(
  (select count(*) from public.foods
   where household_id is null and kcal_per_100g is null
     and protein_grams_per_100g is null
     and fat_grams_per_100g is null
     and carbs_grams_per_100g is null),
  26::bigint,
  'unmapped foods remain unknown'
);
select ok(
  (select count(*) from public.food_aliases where household_id is null) > 300,
  'reviewed shared aliases are seeded'
);

select * from finish();
rollback;
