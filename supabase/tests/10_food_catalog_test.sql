-- D1-005: tabele kataloga namirnica (specs/018-ingredient-catalog/data-model.md).
-- Deljeni redovi su samo za čitanje, kućni samo za članove; vlasništvo se ne
-- menja; alias pokazuje na deljenu ili sopstvenu namirnicu; povučena deljena
-- namirnica ne dobija nove kućne aliase; deljeni alias je jedinstven dok je
-- aktivan, kućni nije; brisanje ostavlja trag samo za kućne redove.
begin;
select * from no_plan();

-- The migration seed is covered by test 11; this suite owns an isolated
-- catalog fixture so its duplicate and permission cases stay deterministic.
delete from public.food_aliases where household_id is null;
delete from public.foods where household_id is null;

select tests.create_user('a@test.local') as ua \gset
select tests.create_user('b@test.local') as ub \gset
select tests.household_of(:'ua') as ha \gset
select tests.household_of(:'ub') as hb \gset

-- Deljeni katalog pravi migracija (ovde vlasnik tabela, bez RLS-a).
insert into public.foods (id, slug, name, category, base_unit, source, reviewed_at) values
  ('00000000-0000-4000-8000-000000000001', 'jaje', 'jaje', 'Mlečni proizvodi i jaja', 'piece', 'test', now()),
  ('00000000-0000-4000-8000-000000000002', 'mleko', 'mleko', 'Mlečni proizvodi i jaja', 'milliliter', 'test', now());
insert into public.food_aliases (id, food_id, alias, alias_normalized) values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-000000000001', 'jaja', 'jaja');

-- Id mora biti UUID string.
select throws_ok($$insert into public.foods (id, slug, name, category, base_unit) values ('jaje-2', 'jaje-2', 'jaje', 'Ostalo', 'piece')$$,
  '23514', null, 'id koji nije UUID se odbija');
select throws_ok($$insert into public.foods (id, slug, name, category, base_unit) values ('00000000-0000-4000-8000-000000000009', 'x', 'x', 'Ostalo', 'kilogram')$$,
  '23514', null, 'nepoznata osnovna jedinica se odbija');
select throws_ok($$insert into public.foods (id, slug, name, category, base_unit) values ('00000000-0000-4000-8000-000000000009', 'x', '', 'Ostalo', 'piece')$$,
  '23514', null, 'prazan naziv se odbija');

-- Jedinstvenost deljenih redova.
select throws_ok($$insert into public.foods (id, slug, name, category, base_unit) values ('00000000-0000-4000-8000-000000000003', 'jaje', 'jaje 2', 'Ostalo', 'piece')$$,
  '23505', null, 'isti deljeni slug se odbija');
select throws_ok($$insert into public.food_aliases (id, food_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-000000000002', 'jaja', 'jaja')$$,
  '23505', null, 'isti aktivan deljeni alias se odbija');

-- Deljeni alias ne sme pokazivati na kućnu namirnicu.
insert into public.foods (id, household_id, slug, name, category, base_unit) values
  ('00000000-0000-4000-8000-0000000000b1', :'hb', 'ajvar-b', 'ajvar', 'Ostalo', 'gram');
select throws_ok($$insert into public.food_aliases (id, food_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000a3', '00000000-0000-4000-8000-0000000000b1', 'ajvar', 'ajvar')$$,
  '23514', null, 'deljeni alias na kućnu namirnicu se odbija');

-- Povlačenje deljenog aliasa oslobađa ključ za zamenu.
update public.food_aliases set withdrawn_at = now() where id = '00000000-0000-4000-8000-0000000000a1';
select lives_ok($$insert into public.food_aliases (id, food_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000a4', '00000000-0000-4000-8000-000000000002', 'jaja', 'jaja')$$,
  'zamena pod istim ključem posle povlačenja prolazi');

-- Deljeni red nema vlasnika za deletions: brisanje (samo migracija) ne ostavlja trag.
insert into public.foods (id, slug, name, category, base_unit) values
  ('00000000-0000-4000-8000-000000000004', 'proba', 'proba', 'Ostalo', 'gram');
insert into public.food_aliases (id, food_id, alias, alias_normalized) values
  ('00000000-0000-4000-8000-0000000000a6', '00000000-0000-4000-8000-000000000004', 'probe', 'probe');
select lives_ok($$delete from public.foods where id = '00000000-0000-4000-8000-000000000004'$$,
  'brisanje deljene namirnice i njenog aliasa ne baca grešku');
select is((select count(*) from public.deletions where entity in ('food', 'food_alias')), 0::bigint,
  'deljeni redovi ne ostavljaju trag brisanja');

-- anon ne vidi ništa.
select tests.authenticate_anon();
select throws_ok($$select count(*) from public.foods$$, '42501', null, 'anon ne čita namirnice');
select throws_ok($$select count(*) from public.food_aliases$$, '42501', null, 'anon ne čita aliase');

-- A čita deljeno i svoje, ne i od B.
select tests.authenticate_as(:'ua');
select is((select count(*) from public.foods where household_id is null and id in (
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000002'
)), 2::bigint, 'A čita testne deljene namirnice');
select is((select count(*) from public.food_aliases where household_id is null), 2::bigint, 'A čita deljene aliase (i povučen)');
select is((select count(*) from public.foods where household_id = :'hb'), 0::bigint, 'A ne vidi namirnice od B');

-- A ne menja deljeni katalog.
select throws_ok($$insert into public.foods (id, slug, name, category, base_unit) values ('00000000-0000-4000-8000-000000000005', 'so', 'so', 'Ostalo', 'gram')$$,
  '42501', null, 'A ne dodaje deljenu namirnicu');
select is(tests.affected($$update public.foods set name = 'jaja' where id = '00000000-0000-4000-8000-000000000001'$$), 0::bigint, 'A ne menja deljenu namirnicu');
select is(tests.affected($$delete from public.foods where id = '00000000-0000-4000-8000-000000000001'$$), 0::bigint, 'A ne briše deljenu namirnicu');
select throws_ok($$insert into public.food_aliases (id, food_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000a5', '00000000-0000-4000-8000-000000000001', 'jaje', 'jaje')$$,
  '42501', null, 'A ne dodaje deljeni alias');

-- A dodaje svoju namirnicu, ne i u domaćinstvo od B.
select lives_ok(format($$insert into public.foods (id, household_id, slug, name, category, base_unit) values ('00000000-0000-4000-8000-0000000000c1', %L, 'domaci-ajvar', 'domaći ajvar', 'Ostalo', 'gram')$$, :'ha'),
  'A dodaje kućnu namirnicu');
select throws_ok(format($$insert into public.foods (id, household_id, slug, name, category, base_unit) values ('00000000-0000-4000-8000-0000000000c2', %L, 'x', 'x', 'Ostalo', 'gram')$$, :'hb'),
  '42501', null, 'A ne dodaje namirnicu u domaćinstvo od B');
select is(tests.affected($$update public.foods set name = 'tuđ' where id = '00000000-0000-4000-8000-0000000000b1'$$), 0::bigint, 'A ne menja namirnicu od B');
select lives_ok(format($$insert into public.foods (id, household_id, slug, name, category, base_unit) values ('00000000-0000-4000-8000-0000000000c3', %L, 'jaje', 'naše jaje', 'Ostalo', 'piece')$$, :'ha'),
  'isti slug u domaćinstvu i u deljenom katalogu može');
-- Dva uređaja offline naprave istu namirnicu: oba slanja prolaze (bez sudara slugova).
select lives_ok(format($$insert into public.foods (id, household_id, slug, name, category, base_unit) values ('00000000-0000-4000-8000-0000000000c4', %L, 'domaci-ajvar', 'domaći ajvar', 'Ostalo', 'gram')$$, :'ha'),
  'isti kućni slug sa drugog uređaja se prima');

-- Povučena može biti samo deljena namirnica.
select throws_ok($$update public.foods set withdrawn_at = now() where id = '00000000-0000-4000-8000-0000000000c1'$$,
  '23514', null, 'povlačenje kućne namirnice se odbija');

-- Nepromenljivo vlasništvo, sa dozvoljenom izmenom naziva kao kontrolom.
select is(tests.affected($$update public.foods set name = 'ajvar od paprike' where id = '00000000-0000-4000-8000-0000000000c1'$$), 1::bigint, 'A menja naziv svoje namirnice');
select throws_ok($$update public.foods set household_id = null where id = '00000000-0000-4000-8000-0000000000c1'$$,
  '23514', null, 'vlasnik namirnice se ne menja');
select throws_ok($$update public.foods set id = '00000000-0000-4000-8000-0000000000c9' where id = '00000000-0000-4000-8000-0000000000c1'$$,
  '23514', null, 'id namirnice se ne menja');

-- Kućni aliasi: na deljenu ili sopstvenu namirnicu, nikad na tuđu.
select lives_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-000000000002', %L, 'mlijeko', 'mlijeko')$$, :'ha'),
  'kućni alias na deljenu namirnicu');
select lives_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000d2', '00000000-0000-4000-8000-0000000000c1', %L, 'ajvar', 'ajvar')$$, :'ha'),
  'kućni alias na sopstvenu namirnicu');
select throws_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000d3', '00000000-0000-4000-8000-0000000000b1', %L, 'ajvar b', 'ajvar b')$$, :'ha'),
  '23514', null, 'kućni alias na namirnicu drugog domaćinstva se odbija');
select lives_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000d4', '00000000-0000-4000-8000-000000000001', %L, 'ajvar', 'ajvar')$$, :'ha'),
  'dva kućna aliasa za isti ključ su dozvoljena (zamena: upis pa brisanje)');
select lives_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000d6', '00000000-0000-4000-8000-000000000001', %L, 'jaja', 'jaja')$$, :'ha'),
  'isti alias u domaćinstvu i u deljenom katalogu može');
select throws_ok($$update public.food_aliases set food_id = '00000000-0000-4000-8000-000000000001' where id = '00000000-0000-4000-8000-0000000000d2'$$,
  '23514', null, 'namirnica aliasa se ne menja');
select throws_ok($$update public.food_aliases set withdrawn_at = now() where id = '00000000-0000-4000-8000-0000000000d2'$$,
  '23514', null, 'kućni alias se ne povlači, briše se');

-- Povučena deljena namirnica: novo vreme izmene i bez novih kućnih aliasa.
select tests.clear_auth();
select updated_at as before from public.foods where id = '00000000-0000-4000-8000-000000000002' \gset
update public.foods set withdrawn_at = now() where id = '00000000-0000-4000-8000-000000000002';
select ok((select updated_at > :'before'::timestamptz from public.foods where id = '00000000-0000-4000-8000-000000000002'),
  'povlačenje pomera updated_at (preuzimanje ga vidi)');
select tests.authenticate_as(:'ua');
select throws_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000d5', '00000000-0000-4000-8000-000000000002', %L, 'mleko kravlje', 'mleko kravlje')$$, :'ha'),
  '23514', null, 'novi kućni alias na povučenu namirnicu se odbija');
-- Slanje je upsert: postojeći alias na povučenu namirnicu ostaje i može ponovo da se pošalje.
select lives_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-000000000002', %L, 'mlijeko', 'mlijeko') on conflict (id) do update set alias = excluded.alias$$, :'ha'),
  'ponovno slanje postojećeg aliasa na povučenu namirnicu prolazi');

-- Brisanje kućne namirnice briše njene aliase i ostavlja trag za oba.
select is(tests.affected($$delete from public.foods where id = '00000000-0000-4000-8000-0000000000c1'$$), 1::bigint, 'A briše svoju namirnicu');
select tests.clear_auth();
select is((select count(*) from public.food_aliases where id = '00000000-0000-4000-8000-0000000000d2'), 0::bigint, 'alias obrisane namirnice je obrisan');
select is(
  array(select entity || ':' || record_id from public.deletions where household_id = :'ha' and entity in ('food', 'food_alias') order by entity || ':' || record_id collate "C"),
  array['food:00000000-0000-4000-8000-0000000000c1', 'food_alias:00000000-0000-4000-8000-0000000000d2'],
  'trag brisanja za namirnicu i alias, sa domaćinstvom');
select tests.authenticate_as(:'ua');
select lives_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000d2', '00000000-0000-4000-8000-000000000001', %L, 'ajvar', 'ajvar')$$, :'ha'),
  'ponovni upis obrisanog aliasa ne baca grešku');
select is((select count(*) from public.food_aliases where id = '00000000-0000-4000-8000-0000000000d2'), 0::bigint, 'obrisan alias se ne vraća');
-- Brisanje pobeđuje: zakasneli nov alias na obrisanu kućnu namirnicu se tiho preskače.
select lives_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000d7', '00000000-0000-4000-8000-0000000000c1', %L, 'pinđur', 'pinđur')$$, :'ha'),
  'alias na obrisanu namirnicu domaćinstva se preskače bez greške');
select is((select count(*) from public.food_aliases where id = '00000000-0000-4000-8000-0000000000d7'), 0::bigint, 'alias obrisane namirnice se ne upisuje');
-- Tuđa obrisana namirnica daje isti odgovor kao nepostojeća.
select tests.clear_auth();
insert into public.foods (id, household_id, slug, name, category, base_unit) values
  ('00000000-0000-4000-8000-0000000000b2', :'hb', 'kajmak-b', 'kajmak', 'Ostalo', 'gram');
delete from public.foods where id = '00000000-0000-4000-8000-0000000000b2';
select tests.authenticate_as(:'ua');
select throws_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000d8', '00000000-0000-4000-8000-0000000000b2', %L, 'kajmak', 'kajmak')$$, :'ha'),
  '23514', null, 'alias na obrisanu namirnicu drugog domaćinstva se odbija kao nepostojeća');

-- Ovlašćenje prvo, tragovi posle: nečlan dobija 42501 i za obrisan alias i za
-- obrisanu namirnicu tuđeg domaćinstva, pa odgovor ne zavisi od tuđih brisanja.
select tests.authenticate_as(:'ub');
select throws_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000d2', '00000000-0000-4000-8000-000000000001', %L, 'ajvar', 'ajvar')$$, :'ha'),
  '42501', null, 'nečlan ne dobija tihi preskok za obrisan alias tuđeg domaćinstva');
select throws_ok(format($$insert into public.foods (id, household_id, slug, name, category, base_unit) values ('00000000-0000-4000-8000-0000000000c1', %L, 'ajvar', 'ajvar', 'Ostalo', 'gram')$$, :'ha'),
  '42501', null, 'nečlan ne dobija tihi preskok za obrisanu namirnicu tuđeg domaćinstva');
-- Trag važi samo za domaćinstvo koje je brisalo: isti id u drugom domaćinstvu se upisuje.
select lives_ok(format($$insert into public.foods (id, household_id, slug, name, category, base_unit) values ('00000000-0000-4000-8000-0000000000c1', %L, 'ajvar-b', 'ajvar', 'Ostalo', 'gram')$$, :'hb'),
  'tuđ trag ne preskače upis u sopstveno domaćinstvo');
select is((select count(*) from public.foods where id = '00000000-0000-4000-8000-0000000000c1'), 1::bigint, 'red je upisan');

-- Zakasnela izmena aliasa koji je drugi uređaj obrisao, a namirnica je povučena:
-- trag samog aliasa se gleda pre provere povlačenja, pa je to tih no-op, ne 23514.
select tests.authenticate_as(:'ua');
select is(tests.affected($$delete from public.food_aliases where id = '00000000-0000-4000-8000-0000000000d1'$$), 1::bigint, 'A briše alias na povučenu namirnicu');
select lives_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias, alias_normalized) values ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-000000000002', %L, 'mlijeko 2', 'mlijeko 2') on conflict (id) do update set alias = excluded.alias$$, :'ha'),
  'zakasnela izmena obrisanog aliasa na povučenu namirnicu je no-op, ne trajna greška');
select is((select count(*) from public.food_aliases where id = '00000000-0000-4000-8000-0000000000d1'), 0::bigint, 'obrisan alias se ne vraća');

-- Brisanje naloga uklanja kućne namirnice i aliase, deljeni ostaju.
select tests.clear_auth();
select public.delete_account_data(:'ua');
select is((select count(*) from public.foods where household_id = :'ha'), 0::bigint, 'brisanje naloga briše kućne namirnice');
select is((select count(*) from public.food_aliases where household_id = :'ha'), 0::bigint, 'brisanje naloga briše kućne aliase');
select is((select count(*) from public.foods where household_id is null and id in (
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000002'
)), 2::bigint, 'testne deljene namirnice ostaju');

select * from finish();
rollback;
