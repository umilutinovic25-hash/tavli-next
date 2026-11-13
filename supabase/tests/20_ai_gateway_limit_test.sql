begin;
select * from no_plan();
select tests.create_user('ai-limit-a@test.local') as ua \gset
select tests.create_user('ai-limit-b@test.local') as ub \gset

select is(
  (select count(*) filter (where public.consume_ai_request(:'ua', '2026-11-13 10:00:05+00'))
     from generate_series(1, 20)),
  20::bigint,
  'A ima 20 AI zahteva u minuti'
);
select is(public.consume_ai_request(:'ua', '2026-11-13 10:00:50+00'), false, '21. zahtev u istoj minuti je odbijen');
select is(public.consume_ai_request(:'ub', '2026-11-13 10:00:50+00'), true, 'B ima sopstveno ograničenje');
select is(public.consume_ai_request(:'ua', '2026-11-13 10:01:00+00'), true, 'nova minuta vraća pristup');

-- Dnevni zbir broji i odbijene: 20 + 1 + 1 = 22 do sada; do 300 ostaje 278.
select is(
  (select count(*) filter (where public.consume_ai_request(:'ua', '2026-11-13 10:00:00+00'::timestamptz + make_interval(mins => 2 + i / 20)))
     from generate_series(0, 277) i),
  278::bigint,
  'A troši dnevno ograničenje kroz više minuta'
);
select is(public.consume_ai_request(:'ua', '2026-11-13 20:00:00+00'), false, 'posle 300 zahteva u danu sledeći je odbijen');
select is(public.consume_ai_request(:'ua', '2026-11-14 00:00:01+00'), true, 'novi dan vraća pristup');

select is(has_function_privilege('authenticated', 'public.consume_ai_request(uuid, timestamptz)', 'execute'), false, 'authenticated ne izvršava brojač');
select is(has_function_privilege('anon', 'public.consume_ai_request(uuid, timestamptz)', 'execute'), false, 'anon ne izvršava brojač');
select is(has_function_privilege('service_role', 'public.consume_ai_request(uuid, timestamptz)', 'execute'), true, 'service_role izvršava brojač');
select is(has_table_privilege('authenticated', 'private.ai_gateway_usage', 'select'), false, 'authenticated ne čita brojač');

delete from auth.users where id = :'ub';
select is((select count(*) from private.ai_gateway_usage where user_id = :'ub'), 0::bigint, 'brisanje naloga briše brojač');

select * from finish();
rollback;
