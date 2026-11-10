-- Pozivnice za domaćinstvo. Vlasnik pravi pozivnicu sa 6-znakovnim kodom
-- (važi 7 dana), a drugi nalog je unosi i postaje član. Tabela je samo za
-- server: nije u drift šemi i ne ide kroz sinhronizaciju.

-- Članstvo sada može da ima i ulogu 'member' (pored 'owner').
alter table public.household_members drop constraint household_members_role_check;
alter table public.household_members
  add constraint household_members_role_check check (role in ('owner', 'member'));

create table public.household_invites (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  -- Alfabet bez 0, O, 1, I, L: 2–9 i A–Z bez I, L, O (31 znak).
  code text not null unique check (code ~ '^[2-9A-HJ-KM-NP-Z]{6}$'),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  revoked_at timestamptz,
  uses integer not null default 0 check (uses >= 0),
  constraint household_invites_expiry_after_creation check (expires_at > created_at)
);

create index household_invites_household_idx on public.household_invites (household_id);

-- Da li je prijavljena osoba vlasnik domaćinstva. Kao private.is_member, ali
-- samo za ulogu 'owner'.
create or replace function private.is_household_owner(hid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.household_members m
    where m.household_id = hid
      and m.user_id = (select auth.uid())
      and m.role = 'owner'
  );
$$;

revoke execute on function private.is_household_owner(uuid) from public, anon;
grant execute on function private.is_household_owner(uuid) to authenticated;

-- Neuspešni pokušaji unosa koda po korisniku (za ograničenje brzine).
-- Čita i piše samo funkcija redeem_household_invite.
create table private.household_invite_failures (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  failed_at timestamptz not null default now()
);
create index household_invite_failures_user_idx on private.household_invite_failures (user_id, failed_at);
alter table private.household_invite_failures enable row level security;
revoke all on private.household_invite_failures from public, anon, authenticated;

alter table public.household_invites enable row level security;

revoke all on public.household_invites from anon, authenticated;
grant select, insert on public.household_invites to authenticated;
-- Poništavanje je jedina izmena; kod, uses i domaćinstvo se ne menjaju.
grant update (revoked_at) on public.household_invites to authenticated;

-- Vlasnik vidi, pravi i poništava pozivnice svog domaćinstva. Poništena
-- pozivnica se ne vraća (revoked_at ostaje postavljen).
create policy "household_invites: owner select" on public.household_invites
  for select to authenticated using (private.is_household_owner(household_id));
create policy "household_invites: owner insert" on public.household_invites
  for insert to authenticated
  with check (
    private.is_household_owner(household_id)
    and created_by = (select auth.uid())
  );
create policy "household_invites: owner revoke" on public.household_invites
  for update to authenticated
  using (private.is_household_owner(household_id))
  with check (private.is_household_owner(household_id) and revoked_at is not null);

-- Uzastopni neuspešni pokušaji: najviše 5 u 10 minuta po korisniku.
-- Neuspeh se upisuje i vraća null (ne baca se greška), jer bi rollback
-- obrisao upisani neuspeh.
create or replace function public.redeem_household_invite(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_code text := upper(btrim(coalesce(p_code, '')));
  v_recent integer;
  inv public.household_invites%rowtype;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  delete from private.household_invite_failures f
  where f.user_id = uid and f.failed_at < now() - interval '10 minutes';

  select count(*) into v_recent
  from private.household_invite_failures f
  where f.user_id = uid and f.failed_at >= now() - interval '10 minutes';
  if v_recent >= 5 then
    raise exception 'too_many_attempts' using errcode = 'P0429';
  end if;

  select i.* into inv
  from public.household_invites i
  where i.code = v_code
    and i.revoked_at is null
    and i.expires_at > now()
  for update;

  if not found then
    insert into private.household_invite_failures (user_id) values (uid);
    return null;
  end if;

  if not exists (
    select 1 from public.household_members m
    where m.household_id = inv.household_id and m.user_id = uid
  ) then
    insert into public.household_members (household_id, user_id, role)
    values (inv.household_id, uid, 'member');
    update public.household_invites set uses = uses + 1 where id = inv.id;
  end if;

  return inv.household_id;
end;
$$;

revoke execute on function public.redeem_household_invite(text) from public, anon;
grant execute on function public.redeem_household_invite(text) to authenticated;
