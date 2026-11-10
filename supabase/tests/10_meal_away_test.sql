-- 026: obrok van kuće. Postojeći obroci su `cook`; `away` traži razlog,
-- `cook` nema razlog ni napomenu; B ne menja A-ov obrok u obrok van kuće.
begin;
select * from no_plan();

select tests.create_user('a@test.local') as ua \gset
select tests.create_user('b@test.local') as ub \gset
select tests.household_of(:'ua') as ha \gset
select tests.household_of(:'ub') as hb \gset

insert into public.meal_plans (id, household_id, start_date, end_date, meal_types)
  values ('pa', :'ha', '2026-11-02', '2026-11-08', '["lunch"]');
insert into public.meal_plan_entries (id, household_id, plan_id, date, meal_type)
  values ('ea', :'ha', 'pa', '2026-11-03', 'lunch');

select is((select kind from public.meal_plan_entries where id = 'ea'), 'cook', 'postojeći obrok se kuva');

select tests.authenticate_as(:'ub');
select is(tests.affected($$update public.meal_plan_entries set kind = 'away', away_reason = 'restaurant' where id = 'ea'$$), 0::bigint, 'B ne menja A-ov obrok u obrok van kuće');
select tests.clear_auth();

select tests.authenticate_as(:'ua');
select is(tests.affected($$update public.meal_plan_entries set kind = 'away', away_reason = 'restaurant', away_note = 'sa kolegama' where id = 'ea'$$), 1::bigint, 'A označava obrok van kuće');
select lives_ok(format($$insert into public.meal_plan_entries (id, household_id, plan_id, date, meal_type, kind, away_reason) values ('eb', %L, 'pa', '2026-11-04', 'lunch', 'away', 'skip')$$, :'ha'), 'A dodaje obrok van kuće na prazno mesto');
select throws_ok($$update public.meal_plan_entries set away_reason = null where id = 'eb'$$, '23514', null, 'obrok van kuće ima razlog');
select throws_ok($$update public.meal_plan_entries set kind = 'cook' where id = 'eb'$$, '23514', null, 'obrok koji se kuva nema razlog');
select throws_ok($$update public.meal_plan_entries set kind = 'ostatak' where id = 'eb'$$, '23514', null, 'nepoznata vrsta se odbija');
select throws_ok($$update public.meal_plan_entries set away_reason = 'bioskop' where id = 'eb'$$, '23514', null, 'nepoznat razlog se odbija');
select throws_ok(format($$update public.meal_plan_entries set away_note = %L where id = 'eb'$$, repeat('x', 81)), '23514', null, 'napomena najviše 80 znakova');
select is(tests.affected($$update public.meal_plan_entries set kind = 'cook', away_reason = null, away_note = null where id = 'ea'$$), 1::bigint, 'A vraća obrok u kuvanje');
select tests.clear_auth();

select * from finish();
rollback;
