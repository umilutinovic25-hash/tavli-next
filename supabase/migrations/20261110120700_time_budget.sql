-- 028: vreme po danu. Recept dobija potvrđeno aktivno i ukupno vreme
-- (staro prep_minutes ostaje nespecificirano i ne migrira se). Domaćinstvo
-- ima najviše jedno ograničenje po danu u nedelji: limit aktivnog rada po
-- obroku i/ili prozor za kuvanje.
alter table public.recipes
  add column active_minutes integer check (active_minutes between 1 and 1440),
  add column total_minutes integer check (total_minutes between 1 and 1440),
  add constraint recipes_timing_check check (
    active_minutes is null or total_minutes is null or active_minutes <= total_minutes
  );

create table public.day_time_budgets (
  id text primary key check (char_length(id) between 1 and 64),
  household_id uuid not null references public.households (id) on delete cascade,
  weekday integer not null check (weekday between 1 and 7),
  max_active_minutes integer check (max_active_minutes between 1 and 1440),
  window_start integer check (window_start between 0 and 1440),
  window_end integer check (window_end between 0 and 1440),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  unique (household_id, weekday),
  check ((window_start is null) = (window_end is null)),
  check (window_end is null or window_end > window_start),
  check (max_active_minutes is not null or window_start is not null)
);

create index day_time_budgets_sync_idx on public.day_time_budgets (household_id, updated_at, id);

create trigger touch_updated_at before insert or update on public.day_time_budgets
  for each row execute function private.touch_updated_at('updated_by');
create trigger record_deletion after delete on public.day_time_budgets
  for each row execute function private.record_deletion('day_time_budget', 'id');
create trigger skip_if_deleted before insert on public.day_time_budgets
  for each row execute function private.skip_if_deleted('day_time_budget', 'id');

alter table public.day_time_budgets enable row level security;
grant select, insert, update, delete on public.day_time_budgets to authenticated;

create policy "day_time_budgets: members select" on public.day_time_budgets
  for select to authenticated using (private.is_member(household_id));
create policy "day_time_budgets: members insert" on public.day_time_budgets
  for insert to authenticated with check (private.is_member(household_id));
create policy "day_time_budgets: members update" on public.day_time_budgets
  for update to authenticated
  using (private.is_member(household_id)) with check (private.is_member(household_id));
create policy "day_time_budgets: members delete" on public.day_time_budgets
  for delete to authenticated using (private.is_member(household_id));
