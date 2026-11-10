-- 029: pravila po danima. Dva naloga: B ne vidi i ne menja A-ova pravila;
-- provere vrste, dana, obroka i naziva sastojka; izuzetak na obroku je
-- lista; brisanje ostavlja trag.
begin;
select * from no_plan();

select tests.create_user('a@test.local') as ua \gset
select tests.create_user('b@test.local') as ub \gset
select tests.household_of(:'ua') as ha \gset
select tests.household_of(:'ub') as hb \gset

insert into public.day_rules (id, household_id, weekday, kind)
  values ('ra', :'ha', 1, 'noMeat'), ('rb', :'hb', 5, 'fish');
insert into public.meal_plans (id, household_id, start_date, end_date, meal_types)
  values ('pa', :'ha', '2026-11-02', '2026-11-08', '["lunch"]');
insert into public.meal_plan_entries (id, household_id, plan_id, date, meal_type)
  values ('ea', :'ha', 'pa', '2026-11-02', 'lunch');

select tests.authenticate_as(:'ub');
select is((select count(*) from public.day_rules where household_id = :'ha'), 0::bigint, 'B ne vidi day_rules od A');
select is(tests.affected($$update public.day_rules set weekday = 2 where id = 'ra'$$), 0::bigint, 'B ne menja day_rules od A');
select is(tests.affected($$delete from public.day_rules where id = 'ra'$$), 0::bigint, 'B ne briše day_rules od A');
select throws_ok(format($$insert into public.day_rules (id, household_id, weekday, kind) values ('x', %L, 2, 'noMeat')$$, :'ha'), '42501', null, 'B ne dodaje day_rules u A-ovo domaćinstvo');
select tests.clear_auth();

select tests.authenticate_as(:'ua');
select is((select count(*) from public.day_rules), 1::bigint, 'A vidi samo svoja pravila');
select lives_ok(format($$insert into public.day_rules (id, household_id, weekday, meal_type, kind, value, mode) values ('ra2', %L, 3, 'dinner', 'without', 'luk', 'preferred')$$, :'ha'), 'A dodaje pravilo sa sastojkom');
select throws_ok(format($$insert into public.day_rules (id, household_id, weekday, kind) values ('ra3', %L, 3, 'without')$$, :'ha'), '23514', null, 'bez sastojka traži naziv');
select throws_ok(format($$insert into public.day_rules (id, household_id, weekday, kind, value) values ('ra4', %L, 3, 'noMeat', 'x')$$, :'ha'), '23514', null, 'bez mesa nema naziv');
select throws_ok($$update public.day_rules set weekday = 0 where id = 'ra'$$, '23514', null, 'dan 1–7');
select throws_ok($$update public.day_rules set kind = 'vegan' where id = 'ra'$$, '23514', null, 'nepoznata vrsta se odbija');
select throws_ok($$update public.day_rules set meal_type = 'uzina' where id = 'ra'$$, '23514', null, 'nepoznat obrok se odbija');
select is(tests.affected($$update public.meal_plan_entries set rule_overrides = '["ra"]' where id = 'ea'$$), 1::bigint, 'A dozvoljava izuzetak za obrok');
select throws_ok($$update public.meal_plan_entries set rule_overrides = '{"ra":true}' where id = 'ea'$$, '23514', null, 'izuzeci su lista');
select is(tests.affected($$delete from public.day_rules where id = 'ra2'$$), 1::bigint, 'A briše pravilo');
select is((select count(*) from public.deletions where entity = 'day_rule' and record_id = 'ra2'), 1::bigint, 'brisanje ostavlja trag');
select tests.clear_auth();

set local role service_role;
select public.delete_account_data(:'ua');
reset role;
select is((select count(*) from public.day_rules where household_id = :'ha'), 0::bigint, 'brisanje naloga briše pravila');
select is((select count(*) from public.day_rules where household_id = :'hb'), 1::bigint, 'pravila B ostaju');

select * from finish();
rollback;
