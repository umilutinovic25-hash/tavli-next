begin;
select * from no_plan();
select tests.create_user('limit-a@test.local') as ua \gset
select tests.create_user('limit-b@test.local') as ub \gset

select is(
  (select count(*) filter (where public.consume_recipe_import(:'ua', '2026-11-10 10:00:05+00'))
     from generate_series(1, 10)),
  10::bigint,
  'A ima 10 uvoza u minuti'
);
select is(public.consume_recipe_import(:'ua', '2026-11-10 10:00:50+00'), false, '11. uvoz u istoj minuti je odbijen');
select is(public.consume_recipe_import(:'ub', '2026-11-10 10:00:50+00'), true, 'B ima sopstveno ograničenje');
select is(public.consume_recipe_import(:'ua', '2026-11-10 10:01:00+00'), true, 'nova minuta vraća uvoz');

select is(
  (select count(*) filter (where public.consume_recipe_import(:'ua', '2026-11-10 10:00:00+00'::timestamptz + make_interval(mins => 2 + i / 10)))
     from generate_series(0, 47) i),
  48::bigint,
  'A troši dnevno ograničenje kroz više minuta'
);
-- Dnevni zbir broji i odbijene: 11 + 1 + 48 = 60, pa je sledeći 61. i odbijen.
select is(public.consume_recipe_import(:'ua', '2026-11-10 20:00:00+00'), false, 'posle 60 uvoza u danu sledeći je odbijen');
select is(public.consume_recipe_import(:'ua', '2026-11-11 00:00:01+00'), true, 'novi dan vraća uvoz');

select is(has_function_privilege('authenticated', 'public.consume_recipe_import(uuid, timestamptz)', 'execute'), false, 'authenticated ne izvršava brojač');
select is(has_function_privilege('anon', 'public.consume_recipe_import(uuid, timestamptz)', 'execute'), false, 'anon ne izvršava brojač');
select is(has_function_privilege('service_role', 'public.consume_recipe_import(uuid, timestamptz)', 'execute'), true, 'service_role izvršava brojač');
select is(has_table_privilege('authenticated', 'private.recipe_import_usage', 'select'), false, 'authenticated ne čita brojač');

delete from auth.users where id = :'ub';
select is((select count(*) from private.recipe_import_usage where user_id = :'ub'), 0::bigint, 'brisanje naloga briše brojač');

select * from finish();
rollback;
