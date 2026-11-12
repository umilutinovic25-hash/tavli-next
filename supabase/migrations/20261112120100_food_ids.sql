-- 036: zaliha u Ostavi i stavka nabavke čuvaju id namirnice. Tekst (name,
-- unit, category) ostaje za prikaz i za starije klijente.
alter table public.pantry_items
  add column food_id text references public.foods (id) on delete set null;
alter table public.shopping_items
  add column food_id text references public.foods (id) on delete set null;

-- Namirnica mora biti zajednička ili iz istog domaćinstva kao red. Vidi i
-- tuđe namirnice (security definer) da bi odbila vezu sa njima.
create or replace function private.food_ref_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid;
begin
  if new.food_id is null then
    return new;
  end if;
  select f.household_id into owner from public.foods f where f.id = new.food_id;
  if not found then
    raise exception 'food_not_found' using errcode = '23503';
  end if;
  if owner is not null and owner is distinct from new.household_id then
    raise exception 'food_household_mismatch' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function private.food_ref_check() from public, anon, authenticated;

create trigger food_ref_check before insert or update of food_id, household_id
  on public.pantry_items
  for each row execute function private.food_ref_check();
create trigger food_ref_check before insert or update of food_id, household_id
  on public.shopping_items
  for each row execute function private.food_ref_check();
