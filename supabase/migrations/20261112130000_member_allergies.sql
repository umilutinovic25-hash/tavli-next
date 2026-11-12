-- 039: alergije po osobi. Jedan red po osobi u domaćinstvu (id je
-- 'domaćinstvo:osoba', pa dva uređaja iste osobe pišu isti red). Svi članovi
-- čitaju redove svog domaćinstva (provera AI recepata važi za sve), a svaku
-- osobu menja samo ona sama. Član koji napusti domaćinstvo ili bude uklonjen
-- više ne nosi alergije u njega.
create table public.member_allergies (
  id text primary key check (id = household_id::text || ':' || user_id::text),
  household_id uuid not null references public.households (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  codes jsonb not null default '[]'::jsonb check (
    jsonb_typeof(codes) = 'array'
    and codes <@ '["gluten","crustaceans","eggs","fish","peanuts","soy","milk","nuts","celery","mustard","sesame","sulphites","lupin","molluscs"]'::jsonb
  ),
  custom jsonb not null default '[]'::jsonb check (private.is_text_list(custom, 30, 40)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  unique (household_id, user_id)
);

create index member_allergies_sync_idx on public.member_allergies (household_id, updated_at, id);

-- Ponovni ulazak u domaćinstvo daje isti id kao pre izlaska, pa se umesto
-- skip_if_deleted stari trag brisanja uklanja pri novom upisu. Zastareo
-- upis bivšeg člana ne prolazi RLS (više nije član).
create or replace function private.clear_member_allergy_trace()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.deletions d
  where d.entity = 'member_allergy' and d.record_id = new.id;
  return new;
end;
$$;

revoke execute on function private.clear_member_allergy_trace() from public, anon, authenticated;

create trigger touch_updated_at before insert or update on public.member_allergies
  for each row execute function private.touch_updated_at('updated_by');
create trigger clear_trace before insert on public.member_allergies
  for each row execute function private.clear_member_allergy_trace();
create trigger record_deletion after delete on public.member_allergies
  for each row execute function private.record_deletion('member_allergy', 'id');

alter table public.member_allergies enable row level security;
grant select, insert, update, delete on public.member_allergies to authenticated;

create policy "member_allergies: members select" on public.member_allergies
  for select to authenticated using (private.is_member(household_id));
create policy "member_allergies: own insert" on public.member_allergies
  for insert to authenticated
  with check (private.is_member(household_id) and user_id = (select auth.uid()));
create policy "member_allergies: own update" on public.member_allergies
  for update to authenticated
  using (private.is_member(household_id) and user_id = (select auth.uid()))
  with check (private.is_member(household_id) and user_id = (select auth.uid()));
create policy "member_allergies: own delete" on public.member_allergies
  for delete to authenticated
  using (private.is_member(household_id) and user_id = (select auth.uid()));

-- Izlazak iz domaćinstva (napuštanje, uklanjanje, brisanje naloga) briše
-- alergije te osobe u tom domaćinstvu; trag brisanja javlja ostalim
-- uređajima da ih uklone iz keša.
create or replace function private.drop_member_allergies()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.member_allergies a
  where a.household_id = old.household_id and a.user_id = old.user_id;
  return old;
end;
$$;

revoke execute on function private.drop_member_allergies() from public, anon, authenticated;

create trigger drop_member_allergies after delete on public.household_members
  for each row execute function private.drop_member_allergies();

-- Prenos postojećih alergija domaćinstva osobi koja ih je upisala
-- (updated_by, ako je i dalje član), inače vlasniku. Srpski nazivi EU
-- alergena postaju kodovi, ostalo ide u slobodan unos. Kolona `allergies`
-- ostaje zbog starijih klijenata, ali se prazni.
create or replace function private.migrate_household_allergies()
returns void
language sql
security definer
set search_path = ''
as $$
with legacy as (
  select
    p.household_id,
    coalesce(
      (select m.user_id from public.household_members m
        where m.household_id = p.household_id and m.user_id = p.updated_by),
      (select m.user_id from public.household_members m
        where m.household_id = p.household_id and m.role = 'owner'
        order by m.joined_at limit 1)
    ) as user_id,
    p.allergies
  from public.household_preferences p
  where jsonb_array_length(p.allergies) > 0
),
names(name, code) as (
  values
    ('gluten', 'gluten'), ('rakovi', 'crustaceans'), ('jaja', 'eggs'),
    ('jaje', 'eggs'), ('riba', 'fish'), ('kikiriki', 'peanuts'),
    ('soja', 'soy'), ('mleko', 'milk'), ('orašasti plodovi', 'nuts'),
    ('orasasti plodovi', 'nuts'), ('celer', 'celery'), ('slačica', 'mustard'),
    ('slacica', 'mustard'), ('senf', 'mustard'), ('susam', 'sesame'),
    ('sulfiti', 'sulphites'), ('lupina', 'lupin'), ('mekušci', 'molluscs'),
    ('mekusci', 'molluscs')
),
items as (
  select l.household_id, l.user_id, lower(btrim(e #>> '{}')) as item
  from legacy l, jsonb_array_elements(l.allergies) e
  where l.user_id is not null
)
insert into public.member_allergies (id, household_id, user_id, codes, custom, updated_by)
select
  i.household_id::text || ':' || i.user_id::text,
  i.household_id,
  i.user_id,
  coalesce(jsonb_agg(distinct n.code) filter (where n.code is not null), '[]'::jsonb),
  coalesce(jsonb_agg(distinct i.item) filter (where n.code is null), '[]'::jsonb),
  i.user_id
from items i
left join names n on n.name = i.item
group by i.household_id, i.user_id
on conflict (id) do nothing;

update public.household_preferences
set allergies = '[]'::jsonb
where jsonb_array_length(allergies) > 0;
$$;

revoke execute on function private.migrate_household_allergies() from public, anon, authenticated;

select private.migrate_household_allergies();
