-- 024 / D1-017, D1-018: public retailer price references and reviewed mappings.
-- Household shopping data is never stored in these tables.

create table public.store_price_imports (
  id uuid primary key default gen_random_uuid(),
  source_id text not null check (source_id in ('delhaize', 'europrom')),
  source_url text not null check (char_length(source_url) <= 500),
  source_sha256 text not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  retrieved_at timestamptz not null default now(),
  status text not null check (status in ('processing', 'complete', 'failed')),
  row_count integer not null default 0 check (row_count >= 0),
  unique (source_id, source_sha256)
);

create table public.store_price_observations (
  id bigint generated always as identity primary key,
  import_id uuid not null references public.store_price_imports (id) on delete cascade,
  source_id text not null check (source_id in ('delhaize', 'europrom')),
  source_url text not null check (char_length(source_url) <= 500),
  source_sha256 text not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  retailer text not null check (char_length(retailer) between 1 and 120),
  retailer_format text not null check (char_length(retailer_format) between 1 and 120),
  barcode text not null check (char_length(barcode) between 1 and 64),
  product_name text not null check (char_length(product_name) between 1 and 500),
  measure text not null check (char_length(measure) between 1 and 64),
  price_list_type text not null check (price_list_type = 'VAZECI_CENOVNIK'),
  price_date date not null,
  regular_price_paras integer not null check (regular_price_paras >= 0),
  row_sha256 text not null check (row_sha256 ~ '^[0-9a-f]{64}$'),
  unique (import_id, retailer_format, barcode, price_date, row_sha256)
);

create index store_price_observations_current_idx
  on public.store_price_observations (retailer_format, barcode, price_date desc);
create index store_price_observations_import_idx
  on public.store_price_observations (import_id);

-- Each barcode-to-food mapping and package size must be reviewed with direct
-- product evidence; the importer never infers either value from display text.
create table public.store_price_mappings (
  id bigint generated always as identity primary key,
  source_id text not null check (source_id in ('delhaize', 'europrom')),
  retailer_format text not null check (char_length(retailer_format) between 1 and 120),
  barcode text not null check (char_length(barcode) between 1 and 64),
  food_id text not null references public.foods (id) on delete cascade,
  package_quantity_micros bigint not null check (package_quantity_micros > 0),
  package_unit text not null check (package_unit in ('gram', 'milliliter', 'piece')),
  evidence_url text not null check (
    char_length(evidence_url) between 8 and 500 and evidence_url like 'https://%'
  ),
  reviewed_at timestamptz not null,
  reviewed_by text not null check (char_length(reviewed_by) between 1 and 120),
  unique (source_id, retailer_format, barcode)
);

create or replace function private.check_store_price_mapping()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  food record;
begin
  select f.base_unit, f.household_id, f.withdrawn_at, f.reviewed_at
    into food from public.foods f where f.id = new.food_id;
  if not found or food.household_id is not null or food.withdrawn_at is not null
     or food.reviewed_at is null or food.base_unit is distinct from new.package_unit then
    raise exception 'mapping requires a reviewed shared food with a compatible unit'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke execute on function private.check_store_price_mapping() from public, anon, authenticated;
create trigger check_store_price_mapping
  before insert or update on public.store_price_mappings
  for each row execute function private.check_store_price_mapping();

alter table public.store_price_imports enable row level security;
alter table public.store_price_observations enable row level security;
alter table public.store_price_mappings enable row level security;
grant select on public.store_price_imports,
  public.store_price_observations, public.store_price_mappings to authenticated;
grant insert, update on public.store_price_imports,
  public.store_price_observations to service_role;
grant select on public.store_price_imports,
  public.store_price_observations, public.store_price_mappings to service_role;
grant delete on public.store_price_observations to service_role;
grant insert, update, delete on public.store_price_mappings to service_role;
grant usage, select on sequence public.store_price_observations_id_seq,
  public.store_price_mappings_id_seq to service_role;

create policy "store prices: authenticated reads completed imports"
  on public.store_price_imports for select to authenticated
  using (status = 'complete');
create policy "store prices: authenticated reads completed observations"
  on public.store_price_observations for select to authenticated
  using (exists (
    select 1 from public.store_price_imports i
    where i.id = import_id and i.status = 'complete'
  ));
create policy "store prices: authenticated reads mappings"
  on public.store_price_mappings for select to authenticated using (true);

create or replace function public.store_price_offers_for_food_ids(p_food_ids text[])
returns table (
  source_id text,
  retailer text,
  retailer_format text,
  barcode text,
  food_id text,
  package_quantity_micros bigint,
  package_unit text,
  price_in_paras integer,
  price_date date,
  source_url text,
  retrieved_at timestamptz,
  source_sha256 text
)
language sql
stable
security invoker
set search_path = ''
as $$
  with latest_imports as (
    select distinct on (source_id) id, source_id, retrieved_at
    from public.store_price_imports
    where status = 'complete'
    order by source_id, retrieved_at desc, id desc
  ), latest as (
    select o.*,
      max(o.price_date) over (
        partition by o.source_id, o.retailer_format, o.barcode
      ) as latest_price_date
    from public.store_price_observations o
    join latest_imports i on i.id = o.import_id
    where o.price_list_type = 'VAZECI_CENOVNIK'
  )
  select l.source_id, l.retailer, l.retailer_format, l.barcode,
    m.food_id, m.package_quantity_micros, m.package_unit,
    l.regular_price_paras, l.price_date, l.source_url,
    i.retrieved_at, l.source_sha256
  from latest l
  join latest_imports i on i.id = l.import_id
  join public.store_price_mappings m
    on m.source_id = l.source_id
    and m.retailer_format = l.retailer_format
    and m.barcode = l.barcode
  where l.price_date = l.latest_price_date
    and m.food_id = any(p_food_ids);
$$;

revoke all on function public.store_price_offers_for_food_ids(text[]) from public, anon;
grant execute on function public.store_price_offers_for_food_ids(text[]) to authenticated;
