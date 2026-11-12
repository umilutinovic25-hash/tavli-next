-- 036 (SC-003): jednokratno mapiranje postojećih podataka. Namirnica se
-- postavlja samo po tačnom aliasu zajedničkog kataloga; tekst, snimci i
-- izbor osobe ostaju isti, a updated_by se zadržava.
begin;
select * from no_plan();

select tests.create_user('a@test.local') as ua \gset
select tests.household_of(:'ua') as ha \gset
select tests.clear_auth();

-- Sopstvena namirnica domaćinstva se ne koristi za mapiranje.
insert into public.foods (id, household_id, name, category, base_unit)
  values ('own-zv', :'ha', 'zmajevo voće', 'voće i povrće', 'g');
insert into public.food_aliases (id, food_id, household_id, alias)
  values ('own-zv:a', 'own-zv', :'ha', 'zmajevo voće');

insert into public.recipes (id, household_id, title, servings, source, ingredients, steps, updated_by)
values
  ('r1', :'ha', 'Omlet', 2, 'manual',
   '[{"name": "Jaja", "quantity": 3, "unit": "kom"},
     {"name": "zmajevo voće", "quantity": 1, "unit": "kom"},
     {"name": "  Beli   luk ", "quantity": 1, "unit": "čen", "foodId": ""},
     {"name": "jaje", "quantity": 1, "unit": "kom", "foodId": "own-zv"}]', '[]', :'ua'),
  ('r2', :'ha', 'Voda', 1, 'manual', '[{"name": "voda iz bunara", "quantity": 1, "unit": "l"}]', '[]', :'ua');
insert into public.recipe_versions (id, household_id, recipe_id, recipe_json, change_kind)
  values ('rv1', :'ha', 'r1', '{"ingredients": [{"name": "Jaja"}]}', 'create');
insert into public.pantry_items (id, household_id, name, quantity, unit, category, added_at, updated_by)
values
  ('p1', :'ha', 'Jaja', 10, 'kom', 'mlečni proizvodi i jaja', now(), :'ua'),
  ('p2', :'ha', 'zmajevo voće', 1, 'kom', 'voće i povrće', now(), :'ua'),
  ('p3', :'ha', 'jaja', 2, 'kom', 'mlečni proizvodi i jaja', now(), :'ua');
update public.pantry_items set food_id = 'own-zv' where id = 'p3';
insert into public.shopping_lists (id, household_id, name) values ('l1', :'ha', 'Lista');
insert into public.shopping_items (id, household_id, list_id, name, quantity, unit, category, updated_by)
values
  ('s1', :'ha', 'l1', 'Češnjak', 2, 'čen', 'voće i povrće', :'ua'),
  ('s2', :'ha', 'l1', 'nešto treće', null, null, 'ostalo', :'ua');
insert into public.shopping_sources (id, household_id, list_id, kind, recipe_snapshot, servings, recipe_id)
  values ('src1', :'ha', 'l1', 'recipePreparation', '{"ingredients": [{"name": "Jaja"}]}', 2, 'r1');

create temp table before_text as
  select 'r:' || r.id || ':' || (e.ord)::text as k, e.v->>'name' as name, e.v->>'quantity' as quantity, e.v->>'unit' as unit
    from public.recipes r, jsonb_array_elements(r.ingredients) with ordinality as e(v, ord)
  union all select 'p:' || id, name, quantity::text, unit from public.pantry_items
  union all select 's:' || id, name, quantity::text, unit from public.shopping_items;
create temp table before_hash as select
  (select md5(string_agg(t::text, '|' order by id)) from public.recipe_versions t) as versions,
  (select md5(string_agg(t::text, '|' order by id)) from public.shopping_sources t) as sources,
  (select updated_at from public.recipes where id = 'r1') as r1_updated,
  (select updated_at from public.recipes where id = 'r2') as r2_updated;

select lives_ok('select private.map_food_ids()', 'mapiranje prolazi');

select is((select ingredients->0->>'foodId' from public.recipes where id = 'r1'), 'f_jaje', '„Jaja“ → f_jaje');
select ok(not (select ingredients->1 ? 'foodId' from public.recipes where id = 'r1'),
  '„zmajevo voće“ bez ključa (sopstveni alias se ne koristi)');
select is((select ingredients->2->>'foodId' from public.recipes where id = 'r1'), 'f_beli_luk',
  'prazan foodId i razmaci: beli luk');
select is((select ingredients->3->>'foodId' from public.recipes where id = 'r1'), 'own-zv', 'izbor osobe ostaje');
select is((select ingredients from public.recipes where id = 'r2'),
  '[{"name": "voda iz bunara", "quantity": 1, "unit": "l"}]'::jsonb, 'nepoznat sastojak netaknut');
select ok((select updated_at from public.recipes where id = 'r1') > (select r1_updated from before_hash),
  'mapiran recept dobija novi updated_at (sync)');
select is((select updated_at from public.recipes where id = 'r2'), (select r2_updated from before_hash),
  'nepromenjen recept zadržava updated_at');

select is((select food_id from public.pantry_items where id = 'p1'), 'f_jaje', 'Ostava: Jaja → f_jaje');
select is((select food_id from public.pantry_items where id = 'p2'), null, 'Ostava: nepoznato ostaje null');
select is((select food_id from public.pantry_items where id = 'p3'), 'own-zv', 'Ostava: postojeća namirnica ostaje');
select is((select food_id from public.shopping_items where id = 's1'), 'f_beli_luk', 'Nabavka: Češnjak → f_beli_luk');
select is((select food_id from public.shopping_items where id = 's2'), null, 'Nabavka: nepoznato ostaje null');

select set_eq(
  $$select 'r:' || r.id || ':' || (e.ord)::text as k, e.v->>'name' as name, e.v->>'quantity' as quantity, e.v->>'unit' as unit
      from public.recipes r, jsonb_array_elements(r.ingredients) with ordinality as e(v, ord)
    union all select 'p:' || id, name, quantity::text, unit from public.pantry_items
    union all select 's:' || id, name, quantity::text, unit from public.shopping_items$$,
  'select k, name, quantity, unit from before_text',
  'name/quantity/unit nepromenjeni');
select is((select md5(string_agg(t::text, '|' order by id)) from public.recipe_versions t),
  (select versions from before_hash), 'recipe_versions nepromenjeni');
select is((select md5(string_agg(t::text, '|' order by id)) from public.shopping_sources t),
  (select sources from before_hash), 'shopping_sources nepromenjeni');
select is((select count(*) from (
    select updated_by from public.recipes union all select updated_by from public.pantry_items
    union all select updated_by from public.shopping_items) u where updated_by is distinct from :'ua'::uuid),
  0::bigint, 'updated_by zadržan');

select lives_ok('select private.map_food_ids()', 'ponovno pokretanje je bezbedno');
select is((select updated_at from public.recipes where id = 'r2'), (select r2_updated from before_hash),
  'ponovno pokretanje ne dira nepromenjeno');

select * from finish();
rollback;
