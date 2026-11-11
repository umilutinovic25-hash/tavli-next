-- 036: zajednički katalog iz seed migracije (supabase/catalog/foods.csv).
begin;
select * from no_plan();

select ok((select count(*) from public.foods where household_id is null) between 150 and 250,
  'zajednički katalog ima 150–250 namirnica');
select is(
  array(select alias from public.food_aliases where food_id = 'f_jaje' order by alias),
  array['jaja', 'jajce', 'jaje', 'jajeta'],
  'jaje: naziv i aliasi'
);
select is((select food_id from public.food_aliases where alias = 'češnjak'), 'f_beli_luk', 'češnjak je beli luk');
select is((select factor_micros from public.food_conversions where food_id = 'f_beli_luk' and unit = 'čen'),
  5000000::bigint, 'čen belog luka = 5 g');
select is((select count(*) from public.foods f
           where f.household_id is null
             and not exists (select 1 from public.food_aliases a where a.food_id = f.id and a.alias = f.name)),
  0::bigint, 'naziv svake namirnice je i njen alias');
select is((select count(*) from public.food_aliases where alias in ('luk', 'sir', 'pavlaka')), 0::bigint,
  'dvosmisleni aliasi nisu u katalogu');
select is((select array_agg(allergen_code order by allergen_code) from public.food_allergens where food_id = 'f_psenicno_brasno'),
  array['gluten'], 'brašno: gluten');

select * from finish();
rollback;
