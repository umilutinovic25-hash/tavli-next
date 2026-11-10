-- 025: red "Uskoro kuvam". Dva naloga (A i B): B ne vidi i ne menja A-ov
-- red; recept iz tuđeg domaćinstva se ne vezuje; porcije 1–20; brisanje
-- recepta čuva stavku sa snimkom; brisanje stavke ostavlja trag.
begin;
select * from no_plan();

select tests.create_user('a@test.local') as ua \gset
select tests.create_user('b@test.local') as ub \gset
select tests.household_of(:'ua') as ha \gset
select tests.household_of(:'ub') as hb \gset

insert into public.recipes (id, household_id, title, servings, source, ingredients, steps)
  values ('ra', :'ha', 'Sarma', 4, 'manual', '[]', '[]'),
         ('rb', :'hb', 'Pasulj', 2, 'manual', '[]', '[]');
insert into public.cook_soon_items (id, household_id, recipe_id, recipe_snapshot, servings, position)
  values ('qa', :'ha', 'ra', '{"title":"Sarma","servings":4,"ingredients":[]}', 4, 0),
         ('qb', :'hb', 'rb', '{"title":"Pasulj","servings":2,"ingredients":[]}', 2, 0);

-- B pokušava da dođe do A-ovog reda.
select tests.authenticate_as(:'ub');
select is((select count(*) from public.cook_soon_items where household_id = :'ha'), 0::bigint, 'B ne vidi cook_soon_items od A');
select is(tests.affected($$update public.cook_soon_items set position = 5 where id = 'qa'$$), 0::bigint, 'B ne menja cook_soon_items od A');
select is(tests.affected($$delete from public.cook_soon_items where id = 'qa'$$), 0::bigint, 'B ne briše cook_soon_items od A');
select throws_ok(format($$insert into public.cook_soon_items (id, household_id, recipe_snapshot, servings) values ('qx', %L, '{"title":"X","servings":2}', 2)$$, :'ha'), '42501', null, 'B ne dodaje cook_soon_items u A-ovo domaćinstvo');
select throws_ok(format($$insert into public.cook_soon_items (id, household_id, recipe_id, recipe_snapshot, servings) values ('qy', %L, 'ra', '{"title":"X","servings":2}', 2)$$, :'hb'), '23503', null, 'B ne vezuje recept iz A-ovog domaćinstva');
select tests.clear_auth();

-- A radi sa svojim redom.
select tests.authenticate_as(:'ua');
select is((select count(*) from public.cook_soon_items), 1::bigint, 'A vidi samo svoj red');
select lives_ok(format($$insert into public.cook_soon_items (id, household_id, recipe_id, recipe_snapshot, servings, position) values ('qa2', %L, 'ra', '{"title":"Sarma","servings":4}', 2, 1)$$, :'ha'), 'A dodaje isti recept još jednom (odvojena namera)');
select is(tests.affected($$update public.cook_soon_items set position = 0 where id = 'qa2'$$), 1::bigint, 'A menja redosled');
select throws_ok($$update public.cook_soon_items set servings = 0 where id = 'qa2'$$, '23514', null, 'porcije 1–20');
select throws_ok($$update public.cook_soon_items set recipe_snapshot = '[]' where id = 'qa2'$$, '23514', null, 'snimak je JSON objekat');
select throws_ok(format($$update public.cook_soon_items set household_id = %L where id = 'qa2'$$, :'hb'), '42501', null, 'A ne premešta stavku u B-ovo domaćinstvo');
select is(tests.affected($$delete from public.cook_soon_items where id = 'qa2'$$), 1::bigint, 'A briše stavku');
select is((select count(*) from public.deletions where entity = 'cook_soon_item' and record_id = 'qa2'), 1::bigint, 'brisanje stavke ostavlja trag');
select tests.clear_auth();

-- Brisanje recepta zadržava stavku i snimak.
delete from public.recipes where id = 'ra';
select is((select recipe_id from public.cook_soon_items where id = 'qa'), null, 'stavka gubi vezu sa obrisanim receptom');
select is((select recipe_snapshot ->> 'title' from public.cook_soon_items where id = 'qa'), 'Sarma', 'snimak ostaje');

-- Brisanje naloga A briše njegov red, B ostaje.
set local role service_role;
select public.delete_account_data(:'ua');
reset role;
select is((select count(*) from public.cook_soon_items where household_id = :'ha'), 0::bigint, 'brisanje naloga briše red');
select is((select count(*) from public.cook_soon_items where household_id = :'hb'), 1::bigint, 'red B ostaje');

select * from finish();
rollback;
