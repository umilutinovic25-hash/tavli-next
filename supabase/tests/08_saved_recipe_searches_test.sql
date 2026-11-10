begin;
select * from no_plan();
select tests.create_user('saved-a@test.local') as ua \gset
select tests.create_user('saved-b@test.local') as ub \gset
select tests.authenticate_as(:'ua');
select lives_ok($$insert into public.saved_recipe_searches (id, name, max_minutes, include_ingredient) values ('s1', 'Brzo', 30, 'piletina')$$, 'A čuva pretragu');
select tests.authenticate_as(:'ub');
select is((select count(*) from public.saved_recipe_searches), 0::bigint, 'B ne vidi A');
select is(tests.affected($$update public.saved_recipe_searches set name = 'B' where id = 's1'$$), 0::bigint, 'B ne menja A');
select is(tests.affected($$delete from public.saved_recipe_searches where id = 's1'$$), 0::bigint, 'B ne briše A');
select throws_ok(format($$insert into public.saved_recipe_searches (id, user_id, name) values ('s2', %L, 'B')$$, :'ua'), '42501', null, 'B ne upisuje za A');
select tests.authenticate_as(:'ua');
select throws_ok(format($$update public.saved_recipe_searches set user_id = %L where id = 's1'$$, :'ub'), '42501', null, 'A ne prenosi B');
select is(tests.affected($$delete from public.saved_recipe_searches where id = 's1'$$), 1::bigint, 'A briše');
select is((select count(*) from public.deletions where entity = 'saved_recipe_search' and record_id = 's1'), 1::bigint, 'brisanje se sinhronizuje');
select tests.authenticate_anon();
select throws_ok($$select * from public.saved_recipe_searches$$, '42501', null, 'anon nema pristup');
select tests.clear_auth();
select * from finish();
rollback;
