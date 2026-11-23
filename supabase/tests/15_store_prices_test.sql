begin;
select * from no_plan();

select has_table('public', 'store_price_imports', 'price imports table exists');
select has_table('public', 'store_price_observations', 'price observations table exists');
select has_table('public', 'store_price_mappings', 'reviewed mappings table exists');
select has_function('public', 'store_price_offers_for_food_ids', array['text[]'],
  'authenticated comparison RPC exists');

select gen_random_uuid() as food_id \gset
select gen_random_uuid() as import_id \gset
insert into public.foods (id, slug, name, category, base_unit, reviewed_at)
values (:'food_id', 'test-flour', 'Brašno', 'Ostalo', 'gram', now());
insert into public.store_price_imports
  (id, source_id, source_url, source_sha256, status, row_count)
values (:'import_id', 'delhaize', 'https://data.gov.rs/sr/datasets/r/example',
  repeat('a', 64), 'complete', 1);
insert into public.store_price_observations
  (import_id, source_id, source_url, source_sha256, retailer, retailer_format,
   barcode, product_name, measure, price_list_type, price_date,
   regular_price_paras, row_sha256)
values (:'import_id', 'delhaize', 'https://data.gov.rs/sr/datasets/r/example',
  repeat('a', 64), 'Delhaize Serbia', 'Maxi', '123', 'Brašno 1 kg', 'kg',
  'VAZECI_CENOVNIK', '2026-11-21', 9500, repeat('b', 64));
insert into public.store_price_mappings
  (source_id, retailer_format, barcode, food_id, package_quantity_micros,
   package_unit, evidence_url, reviewed_at, reviewed_by)
values ('delhaize', 'Maxi', '123', :'food_id', 1000000000, 'gram',
  'https://example.com/product/123', now(), 'reviewer');

select tests.create_user('store-prices@test.local') as user_id \gset
select tests.authenticate_as(:'user_id');
select is((select count(*) from public.store_price_offers_for_food_ids(
  array[:'food_id']::text[])), 1::bigint, 'authenticated lookup sees a reviewed matching price');
select is((select price_in_paras from public.store_price_offers_for_food_ids(
  array[:'food_id']::text[])), 9500, 'lookup returns exact cents');
select throws_ok($$insert into public.store_price_mappings
  (source_id, retailer_format, barcode, food_id, package_quantity_micros,
   package_unit, evidence_url, reviewed_at, reviewed_by)
  values ('delhaize', 'Maxi', '456', '00000000-0000-0000-0000-000000000000',
   1000000000, 'gram', 'https://example.com/product/456', now(), 'user')$$,
  '42501', null, 'authenticated clients cannot write shared mappings');

select tests.clear_auth();
select throws_ok(format($$insert into public.store_price_mappings
  (source_id, retailer_format, barcode, food_id, package_quantity_micros,
   package_unit, evidence_url, reviewed_at, reviewed_by)
  values ('delhaize', 'Maxi', '456', %L, 1000000000, 'piece',
   'https://example.com/product/456', now(), 'reviewer')$$, :'food_id'),
  '23514', null, 'mapping rejects a package unit that differs from reviewed food unit');

select tests.authenticate_anon();
select throws_ok($$select * from public.store_price_offers_for_food_ids('{}'::text[])$$,
  '42501', null, 'anonymous role cannot call the comparison RPC');
select tests.clear_auth();
select * from finish();
rollback;
