-- Pozivnice za domaćinstvo. Vlasnik traži pozivnicu preko create_household_invite:
-- kod (8 znakova) pravi server iz kriptografski bezbednog izvora, važi 7 dana i
-- može da se iskoristi najviše 5 puta. Drugi nalog ga unosi preko
-- redeem_household_invite i postaje član. Tabela je samo za server: nije u drift
-- šemi i ne ide kroz sinhronizaciju.

-- gen_random_bytes za kodove pozivnica.
create extension if not exists pgcrypto with schema extensions;

-- Članstvo sada može da ima i ulogu 'member' (pored 'owner').
alter table public.household_members drop constraint household_members_role_check;
alter table public.household_members
  add constraint household_members_role_check check (role in ('owner', 'member'));

create table public.household_invites (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  -- Alfabet bez 0, O, 1, I, L: 2–9 i A–Z bez I, L, O (31 znak). Kod ima 8 znakova.
  code text not null unique check (code ~ '^[2-9A-HJ-KM-NP-Z]{8}$'),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  revoked_at timestamptz,
  max_uses integer not null default 5 check (max_uses > 0),
  uses integer not null default 0 check (uses >= 0),
  constraint household_invites_expiry_after_creation check (expires_at > created_at),
  constraint household_invites_uses_within_max check (uses <= max_uses)
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

-- Neuspešni pokušaji unosa koda po korisniku (ograničenje brzine).
-- Čita i piše samo funkcija redeem_household_invite.
create table private.household_invite_failures (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  failed_at timestamptz not null default now()
);
create index household_invite_failures_user_idx on private.household_invite_failures (user_id, failed_at);
alter table private.household_invite_failures enable row level security;
revoke all on private.household_invite_failures from public, anon, authenticated;

-- Neuspešni pokušaji po kodu, za sve naloge zajedno. Čita i piše samo
-- redeem_household_invite.
create table private.household_invite_code_failures (
  id bigint generated always as identity primary key,
  code text not null,
  failed_at timestamptz not null default now()
);
create index household_invite_code_failures_code_idx on private.household_invite_code_failures (code, failed_at);
alter table private.household_invite_code_failures enable row level security;
revoke all on private.household_invite_code_failures from public, anon, authenticated;

alter table public.household_invites enable row level security;

-- Nema INSERT-a: pozivnice prave samo create_household_invite (SECURITY DEFINER),
-- da klijent ne bira kod. Poništavanje je jedina izmena; kod, uses, max_uses i
-- domaćinstvo se ne menjaju.
revoke all on public.household_invites from anon, authenticated;
grant select on public.household_invites to authenticated;
grant update (revoked_at) on public.household_invites to authenticated;

-- Vlasnik vidi i poništava pozivnice svog domaćinstva. Poništena pozivnica se
-- ne vraća (revoked_at ostaje postavljen).
create policy "household_invites: owner select" on public.household_invites
  for select to authenticated using (private.is_household_owner(household_id));
create policy "household_invites: owner revoke" on public.household_invites
  for update to authenticated
  using (private.is_household_owner(household_id))
  with check (private.is_household_owner(household_id) and revoked_at is not null);

-- Pravi pozivnicu i vraća kod. Kod pravi server: 8 znakova iz alfabeta od 31
-- znaka, iz gen_random_bytes. Bajt se prihvata samo ako je manji od 248 (248 =
-- 31 * 8, najveći višekratnik 31 koji staje u bajt), pa je svaki znak jednako
-- verovatan (nema pristrasnosti pri modulo). Sudar sa postojećim kodom (unique)
-- se ponavlja s novim kodom.
create or replace function public.create_household_invite(p_household_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  uid uuid := auth.uid();
  v_code text;
  v_bytes bytea;
  v_byte integer;
  v_attempt integer;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not private.is_household_owner(p_household_id) then
    raise exception 'not_owner' using errcode = '42501';
  end if;

  for v_attempt in 1..5 loop
    v_code := '';
    while length(v_code) < 8 loop
      v_bytes := extensions.gen_random_bytes(16);
      for i in 0..15 loop
        v_byte := get_byte(v_bytes, i);
        if v_byte < 248 then
          v_code := v_code || substr(alphabet, (v_byte % 31) + 1, 1);
          exit when length(v_code) = 8;
        end if;
      end loop;
    end loop;

    begin
      insert into public.household_invites (household_id, code, created_by)
      values (p_household_id, v_code, uid);
      return v_code;
    exception when unique_violation then
      null;
    end;
  end loop;

  raise exception 'code_generation_failed';
end;
$$;

-- Uzastopni neuspešni pokušaji: najviše 5 u 10 minuta po korisniku. Po kodu:
-- 5 neuspeha za isti kod u 10 minuta poništava pozivnicu sa tim kodom (ako
-- postoji). Neuspeh se upisuje i vraća null (ne baca se greška), jer bi
-- rollback obrisao upisani neuspeh.
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
  v_code_recent integer;
  inv public.household_invites%rowtype;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  delete from private.household_invite_failures f
  where f.user_id = uid and f.failed_at < now() - interval '10 minutes';
  delete from private.household_invite_code_failures f
  where f.failed_at < now() - interval '10 minutes';

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
    and i.uses < i.max_uses
  for update;

  if not found then
    insert into private.household_invite_failures (user_id) values (uid);
    if v_code ~ '^[2-9A-HJ-KM-NP-Z]{8}$' then
      insert into private.household_invite_code_failures (code) values (v_code);
      select count(*) into v_code_recent
      from private.household_invite_code_failures f
      where f.code = v_code and f.failed_at >= now() - interval '10 minutes';
      if v_code_recent >= 5 then
        update public.household_invites set revoked_at = now()
        where code = v_code and revoked_at is null;
      end if;
    end if;
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

revoke execute on function public.create_household_invite(uuid) from public, anon;
grant execute on function public.create_household_invite(uuid) to authenticated;

revoke execute on function public.redeem_household_invite(text) from public, anon;
grant execute on function public.redeem_household_invite(text) to authenticated;
