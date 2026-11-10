begin;
select * from no_plan();
select tests.create_user('url-a@test.local') as ua \gset
select tests.create_user('url-b@test.local') as ub \gset
select tests.household_of(:'ua') as ha \gset
select tests.authenticate_as(:'ua');
select lives_ok(format($$insert into public.recipes (id, household_id, title, servings, source, ingredients, steps, source_url) values ('url_a', %L, 'Pita', 2, 'url', '[]', '[]', 'https://example.com/pita')$$, :'ha'), 'A čuva izvor recepta');
select is((select source_url from public.recipes where id = 'url_a'), 'https://example.com/pita', 'A čita izvor');
select tests.authenticate_as(:'ub');
select is((select count(*) from public.recipes where id = 'url_a'), 0::bigint, 'B ne vidi izvor A');
select is(tests.affected($$update public.recipes set source_url = 'https://example.com/other' where id = 'url_a'$$), 0::bigint, 'B ne menja izvor A');
select * from finish();
rollback;
