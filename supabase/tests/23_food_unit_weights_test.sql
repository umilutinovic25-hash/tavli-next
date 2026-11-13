begin;
select * from no_plan();

select has_column('public', 'foods', 'unit_grams', 'namirnica ima težinu jedinice');
select has_column('public', 'foods', 'unit_grams_source', 'namirnica ima izvor težine');

-- Težina komada za sve zajedničke kom namirnice, gustina za ml sa podatkom.
select is(
  (select count(*) from public.foods
    where household_id is null and base_unit = 'kom' and unit_grams is null),
  0::bigint, 'sve zajedničke kom namirnice imaju težinu komada'
);
select ok(
  (select count(*) from public.foods
    where household_id is null and base_unit = 'ml' and unit_grams is not null) >= 15,
  'većina zajedničkih ml namirnica ima gustinu'
);
select is(
  (select unit_grams from public.foods where id = 'f_jaje'),
  50.0000::numeric, 'jaje: 50 g po komadu (USDA large)'
);
select is(
  (select unit_grams from public.foods where id = 'f_mleko'),
  1.0313::numeric, 'mleko: gustina 1,0313 g/ml'
);
-- Nepoznato nije nula: jogurt nema volumenski red u izvoru.
select is(
  (select unit_grams from public.foods where id = 'f_jogurt'),
  null, 'jogurt nema gustinu (nepoznato)'
);
select is(
  (select count(*) from public.foods where base_unit = 'g' and unit_grams is not null),
  0::bigint, 'g namirnice nemaju težinu po jedinici'
);

select throws_ok(
  $$update public.foods set unit_grams = 5, unit_grams_source = 'x' where id = 'f_krompir'$$,
  '23514', null, 'g namirnica ne sme da dobije težinu po jedinici'
);
select throws_ok(
  $$update public.foods set unit_grams = null where id = 'f_jaje'$$,
  '23514', null, 'težina bez izvora (ili izvor bez težine) je odbijena'
);
select throws_ok(
  $$update public.foods set unit_grams = 0 where id = 'f_jaje'$$,
  '23514', null, 'nulta težina je odbijena'
);
select throws_ok(
  $$update public.foods set unit_grams = 5 where id = 'f_mleko'$$,
  '23514', null, 'gustina van opsega je odbijena'
);

select * from finish();
rollback;
