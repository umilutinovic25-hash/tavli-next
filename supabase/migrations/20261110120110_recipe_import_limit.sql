-- Ograničenje uvoza recepta sa URL-a po nalogu: 10 u minuti i 60 dnevno.
-- Brojač je u private šemi; menja ga samo Edge funkcija preko service_role.
create table private.recipe_import_usage (
  user_id uuid primary key references auth.users (id) on delete cascade,
  minute_start timestamptz not null,
  minute_count integer not null,
  day_start timestamptz not null,
  day_count integer not null
);
alter table private.recipe_import_usage enable row level security;
revoke all on private.recipe_import_usage from public, anon, authenticated;

-- Atomski upisuje poziv i vraća da li je u okviru ograničenja. Odbijeni
-- pozivi se takođe broje, pa uporno slanje ostaje blokirano do novog prozora.
create or replace function public.consume_recipe_import(
  uid uuid,
  at timestamptz default now()
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  m timestamptz := date_trunc('minute', at);
  d timestamptz := date_trunc('day', at);
  mc integer;
  dc integer;
begin
  insert into private.recipe_import_usage as u
    (user_id, minute_start, minute_count, day_start, day_count)
  values (uid, m, 1, d, 1)
  on conflict (user_id) do update set
    minute_count = case when u.minute_start = m then u.minute_count + 1 else 1 end,
    minute_start = m,
    day_count = case when u.day_start = d then u.day_count + 1 else 1 end,
    day_start = d
  returning minute_count, day_count into mc, dc;
  return mc <= 10 and dc <= 60;
end;
$$;
revoke execute on function public.consume_recipe_import(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.consume_recipe_import(uuid, timestamptz) to service_role;
