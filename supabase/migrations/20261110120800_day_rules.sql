-- 029: pravila po danima ("ponedeljak bez mesa", "petak riba"). Pravilo se
-- dodaje ili briše; stavka plana pamti id-jeve obaveznih pravila
-- dozvoljenih baš za taj obrok (izuzetak ne važi za drugi dan).
create table public.day_rules (
  id text primary key check (char_length(id) between 1 and 64),
  household_id uuid not null references public.households (id) on delete cascade,
  weekday integer not null check (weekday between 1 and 7),
  meal_type text check (meal_type in ('breakfast', 'lunch', 'dinner')),
  kind text not null check (kind in ('noMeat', 'fish', 'without', 'withIngredient')),
  value text check (char_length(value) between 1 and 40),
  mode text not null default 'required' check (mode in ('required', 'preferred')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  check ((kind in ('without', 'withIngredient')) = (value is not null))
);

create index day_rules_sync_idx on public.day_rules (household_id, updated_at, id);

create trigger touch_updated_at before insert or update on public.day_rules
  for each row execute function private.touch_updated_at('updated_by');
create trigger record_deletion after delete on public.day_rules
  for each row execute function private.record_deletion('day_rule', 'id');
create trigger skip_if_deleted before insert on public.day_rules
  for each row execute function private.skip_if_deleted('day_rule', 'id');

alter table public.day_rules enable row level security;
grant select, insert, update, delete on public.day_rules to authenticated;

create policy "day_rules: members select" on public.day_rules
  for select to authenticated using (private.is_member(household_id));
create policy "day_rules: members insert" on public.day_rules
  for insert to authenticated with check (private.is_member(household_id));
create policy "day_rules: members update" on public.day_rules
  for update to authenticated
  using (private.is_member(household_id)) with check (private.is_member(household_id));
create policy "day_rules: members delete" on public.day_rules
  for delete to authenticated using (private.is_member(household_id));

alter table public.meal_plan_entries
  add column rule_overrides jsonb check (rule_overrides is null or jsonb_typeof(rule_overrides) = 'array');
