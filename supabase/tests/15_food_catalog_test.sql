-- 036: katalog namirnica. Zajednički deo (household_id null) čitaju svi
-- prijavljeni, a ne menja ga niko osim migracija; sopstvene namirnice vide i
-- menjaju samo članovi; alias je jedinstven u vidljivom skupu.
begin;
select * from no_plan();

select tests.create_user('a@test.local') as ua \gset
select tests.create_user('b@test.local') as ub \gset
select tests.household_of(:'ua') as ha \gset
select tests.household_of(:'ub') as hb \gset

-- Zajednička namirnica kao iz seed migracije (postgres, bez RLS-a).
insert into public.foods (id, name, category, base_unit)
  values ('f_t_jaje', 'jaje', 'mlečni proizvodi i jaja', 'kom');
insert into public.food_aliases (id, food_id, alias)
  values ('f_t_jaje:jaje', 'f_t_jaje', 'jaje'), ('f_t_jaje:jaja', 'f_t_jaje', 'jaja');
insert into public.food_allergens (id, food_id, allergen_code)
  values ('f_t_jaje:eggs', 'f_t_jaje', 'eggs');

select is((select count(*) from public.allergens), 14::bigint, '14 EU alergena');
select is(
  array(select code from public.allergens order by code),
  array['celery', 'crustaceans', 'eggs', 'fish', 'gluten', 'lupin', 'milk',
        'molluscs', 'mustard', 'nuts', 'peanuts', 'sesame', 'soy', 'sulphites'],
  'kodovi alergena'
);

-- A: čita zajedničko, ne može da ga menja.
select tests.authenticate_as(:'ua');
select is((select count(*) from public.foods where id = 'f_t_jaje'), 1::bigint, 'A čita zajedničku namirnicu');
select is((select count(*) from public.food_aliases where food_id = 'f_t_jaje'), 2::bigint, 'A čita zajedničke aliase');
select is((select count(*) from public.food_allergens where food_id = 'f_t_jaje'), 1::bigint, 'A čita zajedničke alergene');
select is((select count(*) from public.allergens), 14::bigint, 'A čita alergene');
select throws_ok($$insert into public.foods (id, name, category, base_unit) values ('f_x', 'x', 'ostalo', 'g')$$,
  '42501', null, 'A ne dodaje zajedničku namirnicu');
select is(tests.affected($$update public.foods set name = 'jaja' where id = 'f_t_jaje'$$), 0::bigint, 'A ne menja zajedničku namirnicu');
select throws_ok($$delete from public.foods where id = 'f_t_jaje'$$, '42501', null, 'niko ne briše namirnice');
select throws_ok($$insert into public.food_aliases (id, food_id, alias) values ('x', 'f_t_jaje', 'jajca')$$,
  '42501', null, 'A ne dodaje zajednički alias');
select is(tests.affected($$delete from public.food_allergens where food_id = 'f_t_jaje'$$), 0::bigint, 'A ne briše zajednički alergen');

-- A: sopstvena namirnica.
select lives_ok(format($$insert into public.foods (id, household_id, name, category, base_unit) values ('own-a', %L, 'zmajevo voće', 'voće i povrće', 'g')$$, :'ha'),
  'A dodaje sopstvenu namirnicu');
select lives_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias) values ('al-a', 'own-a', %L, 'zmajevo voće'), ('al-a2', 'own-a', %L, 'pitaja')$$, :'ha', :'ha'),
  'A dodaje aliase sopstvene namirnice');
select lives_ok(format($$insert into public.food_conversions (id, food_id, household_id, unit, factor_micros) values ('cv-a', 'own-a', %L, 'komad', 350000000)$$, :'ha'),
  'A dodaje konverziju');
select lives_ok(format($$insert into public.food_allergens (id, food_id, household_id, allergen_code) values ('ag-a', 'own-a', %L, 'sulphites')$$, :'ha'),
  'A dodaje oznaku alergena');
select throws_ok(format($$insert into public.food_allergens (id, food_id, household_id, allergen_code) values ('ag-a2', 'own-a', %L, 'orasi')$$, :'ha'),
  '23503', null, 'alergen mora biti iz liste');
select throws_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias) values ('al-a3', 'own-a', %L, 'jaja')$$, :'ha'),
  '23505', null, 'sopstveni alias ne zaklanja zajednički');
select throws_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias) values ('al-a4', 'own-a', %L, 'pitaja')$$, :'ha'),
  '23505', null, 'sopstveni alias je jedinstven u domaćinstvu');
select throws_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias) values ('al-a5', 'own-a', %L, 'Pitaja')$$, :'ha'),
  '23514', null, 'alias mora biti normalizovan');
select throws_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias) values ('al-a6', 'f_t_jaje', %L, 'moje jaje')$$, :'ha'),
  '42501', null, 'sopstveni alias ne pokazuje na zajedničku namirnicu');
select throws_ok(format($$insert into public.foods (id, household_id, name, category, base_unit) values ('own-a2', %L, 'mango', 'egzotika', 'g')$$, :'ha'),
  '23514', null, 'kategorija iz liste');
select throws_ok(format($$insert into public.foods (id, household_id, name, category, base_unit) values ('own-a3', %L, 'mango', 'ostalo', 'kg')$$, :'ha'),
  '23514', null, 'osnovna jedinica kom/g/ml');
select is(tests.affected($$update public.foods set name = 'pitaja', category = 'ostalo' where id = 'own-a'$$), 1::bigint, 'A menja naziv i kategoriju');
select throws_ok($$update public.foods set base_unit = 'kom' where id = 'own-a'$$, '42501', null, 'osnovna jedinica je stalna');
select throws_ok($$update public.food_aliases set food_id = 'f_t_jaje' where id = 'al-a'$$, '42501', null, 'alias ne menja namirnicu');
select lives_ok($$insert into public.food_aliases (id, food_id, household_id, alias)
    select id, food_id, household_id, alias from public.food_aliases where id = 'al-a'
    on conflict (id) do update set alias = excluded.alias, food_id = excluded.food_id, household_id = excluded.household_id$$,
  'ponovljen upsert istog aliasa prolazi (outbox)');
select is(tests.affected($$delete from public.food_allergens where id = 'ag-a'$$), 1::bigint, 'A briše svoju oznaku alergena');
select is((select count(*) from public.deletions where entity = 'food_allergen' and record_id = 'ag-a'), 1::bigint, 'brisanje oznake ostavlja trag');
select tests.clear_auth();

-- B ne vidi i ne menja A-ovo.
select tests.authenticate_as(:'ub');
select is((select count(*) from public.foods where id = 'own-a'), 0::bigint, 'B ne vidi A-ovu namirnicu');
select is((select count(*) from public.food_aliases where id = 'al-a'), 0::bigint, 'B ne vidi A-ove aliase');
select is((select count(*) from public.food_conversions where id = 'cv-a'), 0::bigint, 'B ne vidi A-ove konverzije');
select is(tests.affected($$update public.foods set name = 'x' where id = 'own-a'$$), 0::bigint, 'B ne menja A-ovu namirnicu');
select throws_ok(format($$insert into public.foods (id, household_id, name, category, base_unit) values ('own-b', %L, 'x', 'ostalo', 'g')$$, :'ha'),
  '42501', null, 'B ne dodaje u A-ovo domaćinstvo');
select lives_ok(format($$insert into public.foods (id, household_id, name, category, base_unit) values ('own-b', %L, 'zmajevo voće', 'ostalo', 'g')$$, :'hb'),
  'B ima svoju namirnicu istog naziva');
select lives_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias) values ('al-b', 'own-b', %L, 'pitaja')$$, :'hb'),
  'isti sopstveni alias u drugom domaćinstvu je dozvoljen');
select throws_ok(format($$insert into public.food_aliases (id, food_id, household_id, alias) values ('al-b2', 'own-a', %L, 'tuđe')$$, :'hb'),
  '42501', null, 'B ne vezuje alias za A-ovu namirnicu');
select is((select count(*) from public.foods where household_id is null and id = 'f_t_jaje'), 1::bigint, 'B čita zajedničku namirnicu');
select tests.clear_auth();

-- anon ne vidi ništa.
select tests.authenticate_anon();
select throws_ok($$select count(*) from public.foods$$, '42501', null, 'anon nema pristup namirnicama');
select throws_ok($$select count(*) from public.allergens$$, '42501', null, 'anon nema pristup alergenima');
select tests.clear_auth();

-- Brisanje naloga briše sopstvene namirnice, zajedničke ostaju.
set local role service_role;
select public.delete_account_data(:'ua');
reset role;
select is((select count(*) from public.foods where id = 'own-a'), 0::bigint, 'brisanje naloga briše sopstvene namirnice');
select is((select count(*) from public.foods where id = 'f_t_jaje'), 1::bigint, 'zajednička namirnica ostaje');

select * from finish();
rollback;
