-- Preferencije za ishranu domaćinstva: jedan red po domaćinstvu (id je id
-- domaćinstva). Dele ih svi članovi i idu u AI upite za recepte i plan.
-- Liste su jsonb nizovi stringova; vrednosti ishrane su zatvoren skup.
create or replace function private.is_text_list(v jsonb, max_items integer, max_length integer)
returns boolean language sql immutable as $$
  select case
    when jsonb_typeof(v) <> 'array' then false
    when jsonb_array_length(v) > max_items then false
    else not exists (
      select 1 from jsonb_array_elements(v) e
      where jsonb_typeof(e) <> 'string'
        or char_length(e #>> '{}') not between 1 and max_length
    )
  end;
$$;

grant execute on function private.is_text_list(jsonb, integer, integer) to authenticated;

create table public.household_preferences (
  id text primary key check (id = household_id::text),
  household_id uuid not null unique references public.households (id) on delete cascade,
  diet jsonb not null default '[]'::jsonb check (
    jsonb_typeof(diet) = 'array'
    and diet <@ '["vegetarian","vegan","glutenFree","lactoseFree"]'::jsonb
  ),
  dislikes jsonb not null default '[]'::jsonb check (private.is_text_list(dislikes, 30, 40)),
  allergies jsonb not null default '[]'::jsonb check (private.is_text_list(allergies, 30, 40)),
  servings integer not null default 2 check (servings between 1 and 20),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

create index household_preferences_sync_idx on public.household_preferences (household_id, updated_at, id);

create trigger touch_updated_at before insert or update on public.household_preferences
  for each row execute function private.touch_updated_at('updated_by');
create trigger record_deletion after delete on public.household_preferences
  for each row execute function private.record_deletion('household_preference', 'id');
create trigger skip_if_deleted before insert on public.household_preferences
  for each row execute function private.skip_if_deleted('household_preference', 'id');

alter table public.household_preferences enable row level security;
grant select, insert, update, delete on public.household_preferences to authenticated;

create policy "household_preferences: members select" on public.household_preferences
  for select to authenticated using (private.is_member(household_id));
create policy "household_preferences: members insert" on public.household_preferences
  for insert to authenticated with check (private.is_member(household_id));
create policy "household_preferences: members update" on public.household_preferences
  for update to authenticated
  using (private.is_member(household_id)) with check (private.is_member(household_id));
create policy "household_preferences: members delete" on public.household_preferences
  for delete to authenticated using (private.is_member(household_id));
