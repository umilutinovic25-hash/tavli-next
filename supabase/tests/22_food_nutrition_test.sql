begin;
select * from no_plan();

select has_column('public', 'foods', 'kcal_100', 'namirnica ima kcal na 100 g');
select has_column('public', 'foods', 'protein_100', 'namirnica ima proteine');
select has_column('public', 'foods', 'fat_100', 'namirnica ima masti');
select has_column('public', 'foods', 'carbs_100', 'namirnica ima ugljene hidrate');
select has_column('public', 'foods', 'nutrition_source', 'namirnica ima izvor');
select has_column('public', 'foods', 'nutrition_ref', 'namirnica ima oznaku zapisa u izvoru');

-- Cilj kartice: bar 90% zajedničkog kataloga ima vrednosti i izvor.
select ok(
  (select count(*) filter (where kcal_100 is not null and nutrition_source is not null)::numeric
          / count(*) from public.foods where household_id is null) >= 0.9,
  'bar 90% zajedničkih namirnica ima nutritivne vrednosti i izvor'
);

select results_eq(
  $$select kcal_100::text, protein_100::text, fat_100::text, carbs_100::text,
           nutrition_source, nutrition_ref
      from public.foods where id = 'f_jaje'$$,
  $$values ('143.00', '12.56', '9.51', '0.72', 'usda-sr-legacy-2018-04', '171287')$$,
  'jaje: vrednosti i izvor iz USDA zapisa 171287'
);

-- Nepoznato nije nula: bez odgovarajućeg zapisa ostaje prazno.
select is(
  (select kcal_100 from public.foods where id = 'f_kajmak'),
  null,
  'kajmak nema USDA zapis, vrednost ostaje nepoznata'
);

-- Sve ili ništa: nikad delimičan unos.
select throws_ok(
  $$update public.foods set kcal_100 = null where id = 'f_jaje'$$,
  '23514', null, 'delimičan unos (bez kcal) je odbijen'
);
select throws_ok(
  $$update public.foods set nutrition_source = null where id = 'f_jaje'$$,
  '23514', null, 'vrednosti bez izvora su odbijene'
);
select throws_ok(
  $$update public.foods set kcal_100 = 950 where id = 'f_jaje'$$,
  '23514', null, 'kcal van opsega je odbijen'
);
select throws_ok(
  $$update public.foods set fat_100 = 101 where id = 'f_jaje'$$,
  '23514', null, 'masti preko 100 g su odbijene'
);

select * from finish();
rollback;
