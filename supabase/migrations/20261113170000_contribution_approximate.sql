-- Doprinos nosi oznaku da količina sadrži približnu kuhinjsku meru (rečnik v3).
-- Kolona nasleđuje postojeću RLS politiku i grantove tabele.
alter table public.shopping_contributions
  add column approximate boolean not null default false;
