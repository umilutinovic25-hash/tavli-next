begin;
select * from no_plan();
select tests.create_user('a@test.local') as ua \gset
select tests.create_user('b@test.local') as ub \gset
select tests.household_of(:'ua') as ha \gset
insert into public.shopping_lists (id, household_id, name) values ('list-a', :'ha', 'Lista');
insert into public.shopping_items (id, household_id, list_id, name, category, quantity, unit, brand, note, photo_path)
values ('item-a', :'ha', 'list-a', 'Mleko', 'ostalo', 2, 'l', 'Brend', 'Bez laktoze', 'abc.jpg');
set local storage.allow_delete_query = 'true';
select tests.authenticate_as(:'ua');
select is((select brand from public.shopping_items where id = 'item-a'), 'Brend', 'A vidi svoje detalje');
select lives_ok(format($$insert into storage.objects (bucket_id, name) values ('recipe-photos', %L)$$, :'ha' || '/abc.jpg'), 'A dodaje fotografiju');
select throws_ok($$update public.shopping_items set photo_path = '../x.jpg' where id = 'item-a'$$, '23514', null, 'putanja ne može napustiti direktorijum');
select tests.clear_auth();
select tests.authenticate_as(:'ub');
select is((select count(*) from public.shopping_items where id = 'item-a'), 0::bigint, 'B ne vidi detalje');
select is(tests.affected($$update public.shopping_items set brand = 'tuđe' where id = 'item-a'$$), 0::bigint, 'B ne menja detalje');
select is((select count(*) from storage.objects where name = :'ha' || '/abc.jpg'), 0::bigint, 'B ne vidi fotografiju');
select is(tests.affected(format($$delete from storage.objects where name = %L$$, :'ha' || '/abc.jpg')), 0::bigint, 'B ne briše fotografiju');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('recipe-photos', %L)$$, :'ha' || '/other.jpg'), '42501', null, 'B ne dodaje fotografiju u A');
select tests.clear_auth();
select tests.authenticate_as(:'ua');
select is((select quantity from public.shopping_items where id = 'item-a'), 2::double precision, 'količina je očuvana');
select * from finish();
rollback;
