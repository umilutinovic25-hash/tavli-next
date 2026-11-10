-- 028: vreme po danu. Dva naloga: B ne vidi i ne menja A-ovo vreme; jedan
-- red po danu; provere prozora i limita; vreme recepta 1–1440, aktivno
-- najviše koliko ukupno; brisanje ostavlja trag.
begin;
select * from no_plan();

select tests.create_user('a@test.local') as ua \gset
select tests.create_user('b@test.local') as ub \gset
select tests.household_of(:'ua') as ha \gset
select tests.household_of(:'ub') as hb \gset

insert into public.day_time_budgets (id, household_id, weekday, max_active_minutes)
  values ('a-2', :'ha', 2, 20), ('b-2', :'hb', 2, 45);
insert into public.recipes (id, household_id, title, servings, source, ingredients, steps, prep_minutes)
  values ('ra', :'ha', 'Pasulj', 4, 'manual', '[]', '[]', 15);

select is((select active_minutes from public.recipes where id = 'ra'), null, 'staro vreme pripreme ne postaje aktivno');

select tests.authenticate_as(:'ub');
select is((select count(*) from public.day_time_budgets where household_id = :'ha'), 0::bigint, 'B ne vidi day_time_budgets od A');
select is(tests.affected($$update public.day_time_budgets set max_active_minutes = 90 where id = 'a-2'$$), 0::bigint, 'B ne menja day_time_budgets od A');
select is(tests.affected($$delete from public.day_time_budgets where id = 'a-2'$$), 0::bigint, 'B ne briše day_time_budgets od A');
select throws_ok(format($$insert into public.day_time_budgets (id, household_id, weekday, max_active_minutes) values ('x', %L, 3, 20)$$, :'ha'), '42501', null, 'B ne dodaje day_time_budgets u A-ovo domaćinstvo');
select tests.clear_auth();

select tests.authenticate_as(:'ua');
select is((select count(*) from public.day_time_budgets), 1::bigint, 'A vidi samo svoje vreme');
select throws_ok(format($$insert into public.day_time_budgets (id, household_id, weekday, max_active_minutes) values ('a-2b', %L, 2, 30)$$, :'ha'), '23505', null, 'jedan red po danu');
select lives_ok(format($$insert into public.day_time_budgets (id, household_id, weekday, window_start, window_end) values ('a-7', %L, 7, 1080, 1125)$$, :'ha'), 'A dodaje prozor za nedelju');
select throws_ok($$update public.day_time_budgets set window_end = 1000 where id = 'a-7'$$, '23514', null, 'kraj prozora posle početka');
select throws_ok($$update public.day_time_budgets set window_end = null where id = 'a-7'$$, '23514', null, 'prozor ima početak i kraj');
select throws_ok($$update public.day_time_budgets set weekday = 8 where id = 'a-7'$$, '23514', null, 'dan 1–7');
select throws_ok($$update public.day_time_budgets set max_active_minutes = 0 where id = 'a-2'$$, '23514', null, 'limit je pozitivan');
select is(tests.affected($$update public.recipes set active_minutes = 15, total_minutes = 60 where id = 'ra'$$), 1::bigint, 'A potvrđuje vreme recepta');
select throws_ok($$update public.recipes set active_minutes = 90 where id = 'ra'$$, '23514', null, 'aktivno najviše koliko ukupno');
select is(tests.affected($$delete from public.day_time_budgets where id = 'a-7'$$), 1::bigint, 'A briše dan');
select is((select count(*) from public.deletions where entity = 'day_time_budget' and record_id = 'a-7'), 1::bigint, 'brisanje ostavlja trag');
select tests.clear_auth();

set local role service_role;
select public.delete_account_data(:'ua');
reset role;
select is((select count(*) from public.day_time_budgets where household_id = :'ha'), 0::bigint, 'brisanje naloga briše vreme');
select is((select count(*) from public.day_time_budgets where household_id = :'hb'), 1::bigint, 'vreme B ostaje');

select * from finish();
rollback;
