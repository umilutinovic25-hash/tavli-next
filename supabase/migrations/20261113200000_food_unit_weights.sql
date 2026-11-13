-- Težina jedne osnovne jedinice namirnice u gramima: za kom težina komada, za
-- ml gustina (g po ml); g namirnice je nemaju (1 g je 1 g). Prazno = nepoznato.
-- Sve ili ništa: vrednost uvek dolazi sa izvorom. Kolone nasleđuju postojeći
-- RLS i grantove tabele foods.
alter table public.foods
  add column unit_grams numeric(9, 4),
  add column unit_grams_source text;

alter table public.foods add constraint foods_unit_grams_all_or_none check (
  (unit_grams is null) = (unit_grams_source is null)
);
alter table public.foods add constraint foods_unit_grams_range check (
  unit_grams is null or (
    base_unit <> 'g'
    and unit_grams > 0
    and (base_unit <> 'ml' or unit_grams between 0.1 and 3)
    and (base_unit <> 'kom' or unit_grams <= 5000)
    and char_length(unit_grams_source) between 1 and 120
  )
);
