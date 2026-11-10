-- 027: veze sastojaka i koraka u receptu. Postojeći recepti nemaju veze;
-- veze su lista; upis bez step_links (stariji klijent) ih ne briše; B ne
-- menja A-ove veze.
begin;
select * from no_plan();

select tests.create_user('a@test.local') as ua \gset
select tests.create_user('b@test.local') as ub \gset
select tests.household_of(:'ua') as ha \gset

insert into public.recipes (id, household_id, title, servings, source, ingredients, steps)
  values ('ra', :'ha', 'Testo', 4, 'manual', '[{"name":"brašno","quantity":500,"unit":"g"}]', '["Prosejati."]');

select is((select step_links from public.recipes where id = 'ra'), null, 'postojeći recept nema veze');

select tests.authenticate_as(:'ua');
select is(tests.affected($$update public.recipes set ingredients = '[{"name":"brašno","quantity":500,"unit":"g","id":"i-b"}]', step_links = '[{"text":"Prosejati.","uses":[{"ingredientId":"i-b","quantity":300}]}]' where id = 'ra'$$), 1::bigint, 'A čuva veze');
select throws_ok($$update public.recipes set step_links = '{"text":"x"}' where id = 'ra'$$, '23514', null, 'veze su lista');
-- Stariji klijent šalje samo stare kolone (upsert kao iz aplikacije).
select lives_ok(format($$insert into public.recipes (id, household_id, title, servings, source, ingredients, steps) values ('ra', %L, 'Testo', 4, 'manual', '[{"name":"brašno","quantity":500,"unit":"g"}]', '["Prosejati.", "Mesiti."]') on conflict (id) do update set title = excluded.title, ingredients = excluded.ingredients, steps = excluded.steps$$, :'ha'), 'stariji klijent upisuje recept bez step_links');
select is((select step_links -> 0 ->> 'text' from public.recipes where id = 'ra'), 'Prosejati.', 'veze ostaju posle upisa starijeg klijenta');
select tests.clear_auth();

select tests.authenticate_as(:'ub');
select is(tests.affected($$update public.recipes set step_links = null where id = 'ra'$$), 0::bigint, 'B ne menja A-ove veze');
select tests.clear_auth();
select isnt((select step_links from public.recipes where id = 'ra'), null, 'A-ove veze su netaknute');

select * from finish();
rollback;
