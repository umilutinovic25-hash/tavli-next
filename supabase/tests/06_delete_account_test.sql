-- public.delete_account_data(uid): briše sve od naloga A (samostalno
-- domaćinstvo sa podacima, članstvo, ocene, profil ukusa, tragove, profil),
-- B ostaje netaknut; drugi poziv ne radi ništa; samo service_role (SC-008).
begin;
select plan(18);

select tests.create_user('a@test.local') as ua \gset
select tests.create_user('b@test.local') as ub \gset
select tests.household_of(:'ua') as ha \gset
select tests.household_of(:'ub') as hb \gset

insert into public.recipes (id, household_id, title, servings, source, ingredients, steps)
  values ('ra', :'ha', 'A', 1, 'manual', '[]', '[]'), ('rb', :'hb', 'B', 1, 'manual', '[]', '[]'),
         ('ra2', :'ha', 'A2', 1, 'manual', '[]', '[]');
insert into public.recipe_versions (id, household_id, recipe_id, recipe_json, change_kind)
  values ('va', :'ha', 'ra', '{}', 'ai'), ('vb', :'hb', 'rb', '{}', 'ai');
insert into public.pantry_items (id, household_id, name, category, added_at)
  values ('oa', :'ha', 'so', 'ostalo', now()), ('ob', :'hb', 'so', 'ostalo', now());
insert into public.ratings (id, user_id, recipe_id, stars, cooked_at)
  values ('ga', :'ua', 'ra', 5, now()), ('gb', :'ub', 'rb', 4, now());
insert into public.taste_profiles (user_id, profile) values (:'ua', '{}'), (:'ub', '{}');
insert into public.saved_recipe_searches (id, user_id, name) values ('search_a', :'ua', 'A'), ('search_b', :'ub', 'B');
delete from public.recipes where id = 'ra2'; -- trag za A
delete from public.pantry_items where id = 'ob'; -- trag za B

-- Ni anon ni authenticated ne mogu da je pozovu.
select tests.authenticate_anon();
select throws_ok(format('select public.delete_account_data(%L)', :'ua'), '42501', null, 'anon ne briše nalog');
select tests.clear_auth();
select tests.authenticate_as(:'ua');
select throws_ok(format('select public.delete_account_data(%L)', :'ua'), '42501', null, 'ni sopstveni nalog iz aplikacije');
select tests.clear_auth();

select tests.authenticate_as(:'ua');
select throws_ok(format('select public.solo_households(%L)', :'ua'), '42501', null, 'lista domaćinstava nije za aplikaciju');
select tests.clear_auth();

set local role service_role;
select is(
  array(select public.solo_households(:'ua')), array[:'ha'::uuid],
  'samostalna domaćinstva A (za brisanje slika)'
);
select lives_ok(format('select public.delete_account_data(%L)', :'ua'), 'service_role briše nalog');
select is(array(select public.solo_households(:'ua')), array[]::uuid[], 'posle brisanja nema domaćinstava');
reset role;

select is((select count(*) from public.households where id = :'ha'), 0::bigint, 'domaćinstvo A obrisano');
select is((select count(*) from public.household_members where user_id = :'ua'), 0::bigint, 'članstvo A obrisano');
select is((select count(*) from public.recipes where household_id = :'ha'), 0::bigint, 'recepti A obrisani');
select is((select count(*) from public.recipe_versions where household_id = :'ha'), 0::bigint, 'verzije A obrisane');
select is((select count(*) from public.pantry_items where household_id = :'ha'), 0::bigint, 'ostava A obrisana');
select is((select count(*) from public.saved_recipe_searches where user_id = :'ua'), 0::bigint, 'pretrage A obrisane');
select is((select count(*) from public.ratings where user_id = :'ua'), 0::bigint, 'ocene A obrisane');
select is((select count(*) from public.taste_profiles where user_id = :'ua'), 0::bigint, 'profil ukusa A obrisan');
select is(
  (select count(*) from public.deletions where household_id = :'ha' or user_id = :'ua'),
  0::bigint, 'tragovi A obrisani'
);
select is((select count(*) from public.profiles where id = :'ua'), 0::bigint, 'profil A obrisan');

select is(
  (select array[
     (select count(*) from public.recipes where household_id = :'hb'),
     (select count(*) from public.recipe_versions where household_id = :'hb'),
     (select count(*) from public.ratings where user_id = :'ub'),
     (select count(*) from public.taste_profiles where user_id = :'ub'),
     (select count(*) from public.deletions where household_id = :'hb'),
     (select count(*) from public.saved_recipe_searches where user_id = :'ub'),
     (select count(*) from public.profiles where id = :'ub'),
     (select count(*) from public.household_members where user_id = :'ub')
   ]),
  array[1, 1, 1, 1, 1, 1, 1, 1]::bigint[],
  'B je netaknut'
);

set local role service_role;
select lives_ok(format('select public.delete_account_data(%L)', :'ua'), 'drugi poziv ne radi ništa');
reset role;

select * from finish();
rollback;
