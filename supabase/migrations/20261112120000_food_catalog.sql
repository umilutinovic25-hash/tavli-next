-- 036: katalog namirnica. Namirnica ima stalni id; household_id null je
-- zajednički katalog (referentni podaci, ustav 2.1.0: čitaju ga svi
-- prijavljeni, menja se samo migracijama), inače je to sopstvena namirnica
-- domaćinstva. Namirnice se ne brišu (id se nikad ne koristi ponovo), osim
-- kaskadno sa domaćinstvom. Uploader šalje upsert, pa deca imaju i update
-- pravo, a nepromenljive kolone čuvaju okidači.

-- Normalizovan tekst: kao `ingredientKey` u aplikaciji (trim, mala slova,
-- jedan razmak).
create or replace function private.normalized(t text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(btrim(regexp_replace(t, '\s+', ' ', 'g')));
$$;

revoke execute on function private.normalized(text) from public, anon;
grant execute on function private.normalized(text) to authenticated;

-- Alergeni: 14 iz EU Uredbe 1169/2011, Prilog II. Isti kodovi su u
-- `euAllergens` (lib/domain/food.dart).
create table public.allergens (
  code text primary key,
  name_sr text not null
);

insert into public.allergens (code, name_sr) values
  ('gluten', 'gluten'),
  ('crustaceans', 'rakovi'),
  ('eggs', 'jaja'),
  ('fish', 'riba'),
  ('peanuts', 'kikiriki'),
  ('soy', 'soja'),
  ('milk', 'mleko'),
  ('nuts', 'orašasti plodovi'),
  ('celery', 'celer'),
  ('mustard', 'slačica'),
  ('sesame', 'susam'),
  ('sulphites', 'sulfiti'),
  ('lupin', 'lupina'),
  ('molluscs', 'mekušci');

create table public.foods (
  id text primary key check (char_length(id) between 1 and 64),
  household_id uuid references public.households (id) on delete cascade,
  name text not null
    check (char_length(name) between 1 and 60 and name = private.normalized(name)),
  category text not null check (category in (
    'voće i povrće', 'meso i riba', 'mlečni proizvodi i jaja', 'pekara',
    'suvi proizvodi', 'začini i sosovi', 'konzerve i tegle', 'zamrznuto',
    'pića', 'ostalo')),
  base_unit text not null check (base_unit in ('kom', 'g', 'ml')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

create table public.food_aliases (
  id text primary key check (char_length(id) between 1 and 128),
  food_id text not null references public.foods (id) on delete cascade,
  household_id uuid references public.households (id) on delete cascade,
  alias text not null
    check (char_length(alias) between 1 and 60 and alias = private.normalized(alias)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

create unique index food_aliases_shared_alias on public.food_aliases (alias)
  where household_id is null;
create unique index food_aliases_household_alias on public.food_aliases (household_id, alias)
  where household_id is not null;

create table public.food_conversions (
  id text primary key check (char_length(id) between 1 and 128),
  food_id text not null references public.foods (id) on delete cascade,
  household_id uuid references public.households (id) on delete cascade,
  unit text not null
    check (char_length(unit) between 1 and 20 and unit = private.normalized(unit)),
  factor_micros bigint not null check (factor_micros > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  unique (food_id, unit)
);

create table public.food_allergens (
  id text primary key check (char_length(id) between 1 and 128),
  food_id text not null references public.foods (id) on delete cascade,
  household_id uuid references public.households (id) on delete cascade,
  allergen_code text not null references public.allergens (code),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  unique (food_id, allergen_code)
);

create index foods_sync_idx on public.foods (household_id, updated_at, id);
create index food_aliases_sync_idx on public.food_aliases (household_id, updated_at, id);
create index food_conversions_sync_idx on public.food_conversions (household_id, updated_at, id);
create index food_allergens_sync_idx on public.food_allergens (household_id, updated_at, id);

-- Osnovna jedinica i vlasnik namirnice su stalni.
create or replace function private.food_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.base_unit is distinct from old.base_unit
     or new.household_id is distinct from old.household_id then
    raise exception 'food_base_unit_immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- Dete namirnice: ista namirnica i isto domaćinstvo kao namirnica. Funkcija
-- vidi i tuđe namirnice (security definer) da bi odbila vezu sa njima.
create or replace function private.food_child_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid;
begin
  if tg_op = 'UPDATE' and (new.food_id is distinct from old.food_id
      or new.household_id is distinct from old.household_id) then
    raise exception 'food_child_immutable' using errcode = '42501';
  end if;
  select f.household_id into owner from public.foods f where f.id = new.food_id;
  if not found then
    raise exception 'food_not_found' using errcode = '23503';
  end if;
  if owner is distinct from new.household_id then
    raise exception 'food_household_mismatch' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- Sopstveni alias ne sme da zakloni zajednički.
create or replace function private.food_alias_not_shared()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.household_id is not null and exists (
    select 1 from public.food_aliases a
    where a.household_id is null and a.alias = new.alias
  ) then
    raise exception 'food_alias_taken' using errcode = '23505';
  end if;
  return new;
end;
$$;

revoke execute on function private.food_immutable() from public, anon, authenticated;
revoke execute on function private.food_child_check() from public, anon, authenticated;
revoke execute on function private.food_alias_not_shared() from public, anon, authenticated;

create trigger touch_updated_at before insert or update on public.foods
  for each row execute function private.touch_updated_at('updated_by');
create trigger food_immutable before update on public.foods
  for each row execute function private.food_immutable();
create trigger record_deletion after delete on public.foods
  for each row execute function private.record_deletion('food', 'id');
create trigger skip_if_deleted before insert on public.foods
  for each row execute function private.skip_if_deleted('food', 'id');

create trigger touch_updated_at before insert or update on public.food_aliases
  for each row execute function private.touch_updated_at('updated_by');
create trigger food_child_check before insert or update on public.food_aliases
  for each row execute function private.food_child_check();
create trigger food_alias_not_shared before insert or update on public.food_aliases
  for each row execute function private.food_alias_not_shared();
create trigger record_deletion after delete on public.food_aliases
  for each row execute function private.record_deletion('food_alias', 'id');
create trigger skip_if_deleted before insert on public.food_aliases
  for each row execute function private.skip_if_deleted('food_alias', 'id', 'food', 'food_id');

create trigger touch_updated_at before insert or update on public.food_conversions
  for each row execute function private.touch_updated_at('updated_by');
create trigger food_child_check before insert or update on public.food_conversions
  for each row execute function private.food_child_check();
create trigger record_deletion after delete on public.food_conversions
  for each row execute function private.record_deletion('food_conversion', 'id');
create trigger skip_if_deleted before insert on public.food_conversions
  for each row execute function private.skip_if_deleted('food_conversion', 'id', 'food', 'food_id');

create trigger touch_updated_at before insert or update on public.food_allergens
  for each row execute function private.touch_updated_at('updated_by');
create trigger food_child_check before insert or update on public.food_allergens
  for each row execute function private.food_child_check();
create trigger record_deletion after delete on public.food_allergens
  for each row execute function private.record_deletion('food_allergen', 'id');
create trigger skip_if_deleted before insert on public.food_allergens
  for each row execute function private.skip_if_deleted('food_allergen', 'id', 'food', 'food_id');

-- RLS i prava. Zajednički redovi: samo select. Sopstveni: članovi.
alter table public.allergens enable row level security;
alter table public.foods enable row level security;
alter table public.food_aliases enable row level security;
alter table public.food_conversions enable row level security;
alter table public.food_allergens enable row level security;

grant select on public.allergens to authenticated;
grant select, insert, update on public.foods to authenticated;
grant select, insert, update on public.food_aliases to authenticated;
grant select, insert, update on public.food_conversions to authenticated;
grant select, insert, update, delete on public.food_allergens to authenticated;

create policy "allergens: authenticated select" on public.allergens
  for select to authenticated using (true);

create policy "foods: shared or members select" on public.foods
  for select to authenticated
  using (household_id is null or private.is_member(household_id));
create policy "foods: members insert" on public.foods
  for insert to authenticated
  with check (household_id is not null and private.is_member(household_id));
create policy "foods: members update" on public.foods
  for update to authenticated
  using (household_id is not null and private.is_member(household_id))
  with check (household_id is not null and private.is_member(household_id));

create policy "food_aliases: shared or members select" on public.food_aliases
  for select to authenticated
  using (household_id is null or private.is_member(household_id));
create policy "food_aliases: members insert" on public.food_aliases
  for insert to authenticated
  with check (household_id is not null and private.is_member(household_id));
create policy "food_aliases: members update" on public.food_aliases
  for update to authenticated
  using (household_id is not null and private.is_member(household_id))
  with check (household_id is not null and private.is_member(household_id));

create policy "food_conversions: shared or members select" on public.food_conversions
  for select to authenticated
  using (household_id is null or private.is_member(household_id));
create policy "food_conversions: members insert" on public.food_conversions
  for insert to authenticated
  with check (household_id is not null and private.is_member(household_id));
create policy "food_conversions: members update" on public.food_conversions
  for update to authenticated
  using (household_id is not null and private.is_member(household_id))
  with check (household_id is not null and private.is_member(household_id));

create policy "food_allergens: shared or members select" on public.food_allergens
  for select to authenticated
  using (household_id is null or private.is_member(household_id));
create policy "food_allergens: members insert" on public.food_allergens
  for insert to authenticated
  with check (household_id is not null and private.is_member(household_id));
create policy "food_allergens: members update" on public.food_allergens
  for update to authenticated
  using (household_id is not null and private.is_member(household_id))
  with check (household_id is not null and private.is_member(household_id));
create policy "food_allergens: members delete" on public.food_allergens
  for delete to authenticated
  using (household_id is not null and private.is_member(household_id));
