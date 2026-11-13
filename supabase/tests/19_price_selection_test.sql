begin;
select * from no_plan();
select tests.create_user('price-a@test.local') as ua \gset
select tests.create_user('price-b@test.local') as ub \gset
select tests.household_of(:'ua') as ha \gset
insert into public.shopping_lists (id, household_id, name) values ('price-list-a', :'ha', 'Lista');
insert into public.shopping_items (id, household_id, list_id, name, category) values ('price-item-a', :'ha', 'price-list-a', 'Mleko', 'ostalo');
select tests.authenticate_as(:'ua');
select lives_ok($$update public.shopping_items set price_selection = '{"barcode":"123","package":"1000"}' where id = 'price-item-a'$$, 'član čuva izbor');
select is((select price_selection->>'barcode' from public.shopping_items where id = 'price-item-a'), '123', 'izbor se čita');
select throws_ok($$update public.shopping_items set price_selection = '[]' where id = 'price-item-a'$$, '23514', null, 'nevažeći oblik odbijen');
select tests.clear_auth();
select tests.authenticate_as(:'ub');
select is((select count(*) from public.shopping_items where id = 'price-item-a'), 0::bigint, 'drugo domaćinstvo ne vidi izbor');
select is(tests.affected($$update public.shopping_items set price_selection = '{"barcode":"456"}' where id = 'price-item-a'$$), 0::bigint, 'drugo domaćinstvo ne menja izbor');
select tests.clear_auth();
select * from finish();
rollback;
