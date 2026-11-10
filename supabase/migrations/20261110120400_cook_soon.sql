-- 025: red "Uskoro kuvam". Recepti čekaju bez datuma; potražnju za nabavku
-- pravi tek raspoređivanje u plan (obična stavka plana). Snimak recepta
-- ostaje i kad se recept obriše.
create table public.cook_soon_items (
  id text primary key check (char_length(id) between 1 and 64),
  household_id uuid not null references public.households (id) on delete cascade,
  recipe_id text,
  recipe_snapshot jsonb not null check (jsonb_typeof(recipe_snapshot) = 'object'),
  servings integer not null check (servings between 1 and 20),
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  foreign key (recipe_id, household_id)
    references public.recipes (id, household_id) on delete set null (recipe_id)
);

create index cook_soon_items_sync_idx on public.cook_soon_items (household_id, updated_at, id);
create index cook_soon_items_recipe_idx on public.cook_soon_items (recipe_id, household_id);

create trigger touch_updated_at before insert or update on public.cook_soon_items
  for each row execute function private.touch_updated_at('updated_by');
create trigger record_deletion after delete on public.cook_soon_items
  for each row execute function private.record_deletion('cook_soon_item', 'id');
create trigger skip_if_deleted before insert on public.cook_soon_items
  for each row execute function private.skip_if_deleted('cook_soon_item', 'id');

alter table public.cook_soon_items enable row level security;
grant select, insert, update, delete on public.cook_soon_items to authenticated;

create policy "cook_soon_items: members select" on public.cook_soon_items
  for select to authenticated using (private.is_member(household_id));
create policy "cook_soon_items: members insert" on public.cook_soon_items
  for insert to authenticated with check (private.is_member(household_id));
create policy "cook_soon_items: members update" on public.cook_soon_items
  for update to authenticated
  using (private.is_member(household_id)) with check (private.is_member(household_id));
create policy "cook_soon_items: members delete" on public.cook_soon_items
  for delete to authenticated using (private.is_member(household_id));
