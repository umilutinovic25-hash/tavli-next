-- Preferencije ishrane: B ne vidi i ne menja preferencije od A; jedan red po
-- domaćinstvu; ishrana samo iz zatvorenog skupa; liste i broj osoba u
-- granicama; brisanje naloga briše preferencije.
begin;
select * from no_plan();

select tests.create_user('a@test.local') as ua \gset
select tests.create_user('b@test.local') as ub \gset
select tests.household_of(:'ua') as ha \gset
select tests.household_of(:'ub') as hb \gset

insert into public.household_preferences (id, household_id, diet, dislikes, allergies, servings)
  values (:'ha', :'ha', '["vegan"]', '["cilantro"]', '["orasasti plodovi"]', 4),
         (:'hb', :'hb', '[]', '[]', '[]', 2);

select tests.authenticate_as(:'ub');
select is((select count(*) from public.household_preferences where household_id = :'ha'), 0::bigint, 'B ne vidi preferencije od A');
select is(tests.affected(format($$update public.household_preferences set servings = 9 where household_id = %L$$, :'ha')), 0::bigint, 'B ne menja preferencije od A');
select is(tests.affected(format($$delete from public.household_preferences where household_id = %L$$, :'ha')), 0::bigint, 'B ne briše preferencije od A');
select throws_ok(format($$insert into public.household_preferences (id, household_id) values (%L, %L)$$, :'ha', :'ha'), '42501', null, 'B ne dodaje preferencije u A-ovo domaćinstvo');
select tests.clear_auth();

select tests.authenticate_as(:'ua');
select is((select count(*) from public.household_preferences), 1::bigint, 'A vidi samo svoje preferencije');
select throws_ok(format($$insert into public.household_preferences (id, household_id) values (%L, %L)$$, :'ha', :'ha'), '23505', null, 'jedan red po domaćinstvu');
select throws_ok(format($$update public.household_preferences set diet = '["keto"]' where household_id = %L$$, :'ha'), '23514', null, 'ishrana iz zatvorenog skupa');
select throws_ok(format($$update public.household_preferences set diet = '"vegan"' where household_id = %L$$, :'ha'), '23514', null, 'ishrana je niz');
select throws_ok(format($$update public.household_preferences set dislikes = '[1]' where household_id = %L$$, :'ha'), '23514', null, 'stavke su stringovi');
select throws_ok(format($$update public.household_preferences set allergies = '[""]' where household_id = %L$$, :'ha'), '23514', null, 'stavka nije prazna');
select throws_ok(format($$update public.household_preferences set servings = 0 where household_id = %L$$, :'ha'), '23514', null, 'broj osoba 1–20');
select is(tests.affected(format($$update public.household_preferences set allergies = '["mleko","jaja"]', servings = 3 where household_id = %L$$, :'ha')), 1::bigint, 'A menja alergije i broj osoba');
select tests.clear_auth();

set local role service_role;
select public.delete_account_data(:'ua');
reset role;
select is((select count(*) from public.household_preferences where household_id = :'ha'), 0::bigint, 'brisanje naloga briše preferencije');
select is((select count(*) from public.deletions where entity = 'household_preference' and record_id = :'ha'), 0::bigint, 'brisanje naloga ne ostavlja trag (tragovi se brišu poslednji)');
select is((select count(*) from public.household_preferences where household_id = :'hb'), 1::bigint, 'preferencije B ostaju');

select * from finish();
rollback;
