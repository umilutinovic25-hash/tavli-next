-- Lične sačuvane pretrage koriste isti protokol sinhronizacije i brisanja.
create table public.saved_recipe_searches (
  id text primary key check (char_length(id) between 1 and 64),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  query text not null default '',
  max_minutes integer check (max_minutes > 0),
  include_ingredient text not null default '',
  exclude_ingredient text not null default '',
  updated_at timestamptz not null default now()
);
create index saved_recipe_searches_sync_idx on public.saved_recipe_searches(user_id, updated_at, id);
alter table public.saved_recipe_searches enable row level security;
revoke all on public.saved_recipe_searches from anon, authenticated;
grant select, insert, update, delete on public.saved_recipe_searches to authenticated;
create policy "saved searches: own select" on public.saved_recipe_searches for select to authenticated using (user_id = (select auth.uid()));
create policy "saved searches: own insert" on public.saved_recipe_searches for insert to authenticated with check (user_id = (select auth.uid()));
create policy "saved searches: own update" on public.saved_recipe_searches for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "saved searches: own delete" on public.saved_recipe_searches for delete to authenticated using (user_id = (select auth.uid()));
create trigger touch_updated_at before insert or update on public.saved_recipe_searches for each row execute function private.touch_updated_at();
create trigger record_deletion after delete on public.saved_recipe_searches for each row execute function private.record_deletion('saved_recipe_search', 'id');
create trigger skip_if_deleted before insert on public.saved_recipe_searches for each row execute function private.skip_if_deleted('saved_recipe_search', 'id');

-- Lične pretrage brišu se pre čišćenja tragova i auth naloga.
create or replace function public.delete_account_data(uid uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  solo uuid[];
begin
  select coalesce(array_agg(h), '{}') into solo from public.solo_households(uid) h;

  delete from public.saved_recipe_searches where user_id = uid;
  delete from public.ratings where user_id = uid;
  delete from public.taste_profiles where user_id = uid;
  delete from public.households where id = any (solo);
  delete from public.household_members where user_id = uid;
  -- Tragovi nastaju i iz brisanja iznad, pa se brišu poslednji.
  delete from public.deletions where household_id = any (solo) or user_id = uid;
  delete from public.profiles where id = uid;
end;
$$;

revoke execute on function public.delete_account_data(uuid) from public, anon, authenticated;
grant execute on function public.delete_account_data(uuid) to service_role;
