begin;
select * from no_plan();
select tests.create_user('template-a@test.local') as ua \gset
select tests.create_user('template-b@test.local') as ub \gset
select tests.household_of(:'ua') as ha \gset
select tests.household_of(:'ub') as hb \gset
insert into public.week_templates (id, household_id, name, meals) values ('ta', :'ha', 'Nedelja', '[{"weekday":1}]');
select tests.authenticate_as(:'ub');
select is((select count(*) from public.week_templates), 0::bigint, 'B ne vidi A-ov šablon');
select is(tests.affected($$update public.week_templates set name = 'x' where id = 'ta'$$), 0::bigint, 'B ne menja A-ov šablon');
select is(tests.affected($$delete from public.week_templates where id = 'ta'$$), 0::bigint, 'B ne briše A-ov šablon');
select throws_ok(format($$insert into public.week_templates (id, household_id, name, meals) values ('tx', %L, 'x', '[1]')$$, :'ha'), '42501', null, 'B ne dodaje u A-ovo domaćinstvo');
select tests.clear_auth();
select tests.authenticate_as(:'ua');
select is((select count(*) from public.week_templates), 1::bigint, 'A vidi svoj šablon');
select lives_ok(format($$insert into public.week_templates (id, household_id, name, meals) values ('t2', %L, 'Novi', '[1]')$$, :'ha'), 'A može da sačuva šablon');
select throws_ok(format($$update public.week_templates set household_id = %L where id = 'ta'$$, :'hb'), '42501', null, 'A ne premešta šablon');
select tests.clear_auth();
select throws_ok(format($$insert into public.week_templates (id, household_id, name, meals) values ('bad', %L, 'x', '[]')$$, :'ha'), '23514', null, 'prazan šablon se odbija');
select * from finish();
rollback;
