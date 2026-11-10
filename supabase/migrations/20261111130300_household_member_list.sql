-- Lista članova domaćinstva sa imenima (spec 034).
-- Profil čita samo njegov vlasnik (RLS), pa članovi vide jedni druge samo
-- kroz ovu funkciju: ime i uloga, nikad imejl ni ostale kolone profila.

create or replace function public.household_member_list(p_household_id uuid)
returns table (user_id uuid, display_name text, role text, joined_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not private.is_member(p_household_id) then
    raise exception 'not_household_member' using errcode = '42501';
  end if;
  return query
    select m.user_id, p.display_name, m.role, m.joined_at
    from public.household_members m
    left join public.profiles p on p.id = m.user_id
    where m.household_id = p_household_id
    order by (m.role = 'owner') desc, m.joined_at asc, m.user_id asc;
end;
$$;

revoke execute on function public.household_member_list(uuid) from public, anon;
grant execute on function public.household_member_list(uuid) to authenticated;
