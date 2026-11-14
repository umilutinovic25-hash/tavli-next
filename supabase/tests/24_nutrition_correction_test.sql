begin;
select * from no_plan();

select is(
  (select count(*) from public.foods
    where id in ('f_kafa', 'f_caj', 'f_kokos', 'f_prezle', 'f_lisnato_testo')
      and household_id is null
      and kcal_100 is null and protein_100 is null and fat_100 is null
      and carbs_100 is null and nutrition_source is null and nutrition_ref is null),
  5::bigint,
  'neodgovarajuće stanje namirnice je nepoznato, ne pogrešna vrednost'
);
select is((select kcal_100 from public.foods where id = 'f_jaje'),
  143.00::numeric, 'ispravna nutritivna vrednost jajeta ostaje ista');
select ok(
  (select count(*) filter (where kcal_100 is not null)::numeric / count(*)
     from public.foods where household_id is null) >= 0.9,
  'katalog i posle ispravke ostaje preko 90% pokriven'
);

select * from finish();
rollback;
