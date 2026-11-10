-- 006a/članstvo: uklanjanje člana, napuštanje i prenos vlasništva.
-- Klijent nema UPDATE/DELETE nad household_members, pa sve ide kroz security
-- definer funkcije sa proverom auth.uid(). Greške nose mašinski kod u poruci
-- (owner_must_transfer, not_owner, not_household_member, cannot_remove_self,
-- cannot_transfer_to_self, not_authenticated), a klijent ih prevodi u tekst.
-- Sve funkcije primaju household_id: korisnik ima i svoje lično domaćinstvo
-- (vlasnik) i može biti član tuđeg, pa se članstvo uvek bira po domaćinstvu.

-- Uloga 'member' (do sada je jedina dozvoljena vrednost bila 'owner').
alter table public.household_members
  drop constraint if exists household_members_role_check;
alter table public.household_members
  add constraint household_members_role_check check (role in ('owner', 'member'));

-- Najviše jedan vlasnik po domaćinstvu. Prenos ide u dva koraka (stari vlasnik
-- postaje član, pa novi postaje vlasnik), da indeks nikad ne vidi dva vlasnika.
create unique index household_members_one_owner_idx
  on public.household_members (household_id) where role = 'owner';

-- Osoba bez članstva dobija novo, prazno domaćinstvo u kome je vlasnik (isto
-- kao pri pravljenju naloga), da aplikacija uvek ima svoje domaćinstvo.
create or replace function private.ensure_household(uid uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  hid uuid;
begin
  if not exists (select 1 from public.household_members m where m.user_id = uid) then
    insert into public.households (created_by) values (uid) returning id into hid;
    insert into public.household_members (household_id, user_id, role)
    values (hid, uid, 'owner');
  end if;
end;
$$;

revoke execute on function private.ensure_household(uuid) from public, anon, authenticated;

-- Stari potpisi (bez household_id) se brišu pre novih, da ne ostanu preopterećenja.
drop function if exists public.remove_household_member(uuid);
drop function if exists public.leave_household();
drop function if exists public.transfer_household_ownership(uuid);

-- Vlasnik uklanja člana svog domaćinstva; uklonjena osoba dobija novo domaćinstvo
-- ako nema nijedno drugo.
create or replace function public.remove_household_member(p_household_id uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.household_members m
     where m.household_id = p_household_id and m.user_id = uid and m.role = 'owner'
  ) then
    raise exception 'not_owner' using errcode = '42501';
  end if;

  if p_user = uid then
    raise exception 'cannot_remove_self' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.household_members m
     where m.household_id = p_household_id and m.user_id = p_user
  ) then
    raise exception 'not_household_member' using errcode = 'P0001';
  end if;

  delete from public.household_members
   where household_id = p_household_id and user_id = p_user;
  perform private.ensure_household(p_user);
end;
$$;

revoke execute on function public.remove_household_member(uuid, uuid) from public, anon;
grant execute on function public.remove_household_member(uuid, uuid) to authenticated;

-- Član napušta domaćinstvo p_household_id; vlasnik mora prvo da prenese vlasništvo.
create or replace function public.leave_household(p_household_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  role_now text;
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select m.role into role_now
    from public.household_members m
   where m.household_id = p_household_id and m.user_id = uid;
  if role_now is null then
    raise exception 'not_household_member' using errcode = 'P0001';
  end if;

  if role_now = 'owner' then
    raise exception 'owner_must_transfer' using errcode = 'P0001';
  end if;

  delete from public.household_members
   where household_id = p_household_id and user_id = uid;
  perform private.ensure_household(uid);
end;
$$;

revoke execute on function public.leave_household(uuid) from public, anon;
grant execute on function public.leave_household(uuid) to authenticated;

-- Vlasnik prenosi vlasništvo članu istog domaćinstva p_household_id; stari vlasnik postaje član.
create or replace function public.transfer_household_ownership(p_household_id uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
begin
  if uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.household_members m
     where m.household_id = p_household_id and m.user_id = uid and m.role = 'owner'
  ) then
    raise exception 'not_owner' using errcode = '42501';
  end if;

  if p_user = uid then
    raise exception 'cannot_transfer_to_self' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.household_members m
     where m.household_id = p_household_id and m.user_id = p_user
  ) then
    raise exception 'not_household_member' using errcode = 'P0001';
  end if;

  -- Prvo stari vlasnik (indeks dozvoljava najviše jednog), pa novi.
  update public.household_members set role = 'member'
   where household_id = p_household_id and user_id = uid;
  update public.household_members set role = 'owner'
   where household_id = p_household_id and user_id = p_user;
end;
$$;

revoke execute on function public.transfer_household_ownership(uuid, uuid) from public, anon;
grant execute on function public.transfer_household_ownership(uuid, uuid) to authenticated;
