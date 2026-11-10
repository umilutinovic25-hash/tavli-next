-- Nezavisni snimci nedelje, dostupni članovima domaćinstva.
create table public.week_templates (
  id text primary key check (char_length(id) between 1 and 64),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 100),
  meals jsonb not null check (jsonb_typeof(meals) = 'array' and jsonb_array_length(meals) between 1 and 21),
  use_pantry boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);
create trigger touch_updated_at before insert or update on public.week_templates
  for each row execute function private.touch_updated_at('updated_by');
create trigger record_deletion after delete on public.week_templates
  for each row execute function private.record_deletion('week_template', 'id');
create trigger skip_if_deleted before insert on public.week_templates
  for each row execute function private.skip_if_deleted('week_template', 'id');
alter table public.week_templates enable row level security;
grant select, insert, update, delete on public.week_templates to authenticated;
create policy "week_templates: members select" on public.week_templates for select to authenticated using (private.is_member(household_id));
create policy "week_templates: members insert" on public.week_templates for insert to authenticated with check (private.is_member(household_id));
create policy "week_templates: members update" on public.week_templates for update to authenticated using (private.is_member(household_id)) with check (private.is_member(household_id));
create policy "week_templates: members delete" on public.week_templates for delete to authenticated using (private.is_member(household_id));
