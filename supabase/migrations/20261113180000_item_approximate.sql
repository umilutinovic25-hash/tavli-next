-- Stavka nabavke nosi oznaku da količina sadrži približnu meru (rečnik v3).
-- Kolona nasleđuje postojeću RLS politiku i grantove tabele.
alter table public.shopping_items
  add column approximate boolean not null default false;
