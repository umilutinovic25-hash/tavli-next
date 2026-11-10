-- Lista članova domaćinstva sa imenima: vide je samo članovi, bez imejla.
-- Vlasnik A i član B u domaćinstvu H; C je stranac sa svojim domaćinstvom.
begin;
select plan(9);

select tests.create_user('a@test.local') as ua \gset
select tests.create_user('b@test.local') as ub \gset
select tests.create_user('c@test.local') as uc \gset
select tests.household_of(:'ua') as ha \gset

update public.profiles set display_name = 'Ana' where id = :'ua';
insert into public.household_members (household_id, user_id, role)
  values (:'ha', :'ub', 'member');

select is(
  pg_get_function_result('public.household_member_list(uuid)'::regprocedure),
  'TABLE(user_id uuid, display_name text, role text, joined_at timestamp with time zone)',
  'vraća samo id, ime, ulogu i vreme pridruživanja'
);

select tests.authenticate_anon();
select throws_ok(format('select * from public.household_member_list(%L)', :'ha'), '42501', null, 'anon ne čita članove');
select tests.clear_auth();

select tests.authenticate_as(:'ua');
select is((select count(*) from public.household_member_list(:'ha')), 2::bigint, 'vlasnik vidi oba člana');
select is((select user_id from public.household_member_list(:'ha') limit 1), :'ua'::uuid, 'vlasnik je prvi');
select is((select display_name from public.household_member_list(:'ha') where user_id = :'ua'), 'Ana', 'ime vlasnika');
select is((select display_name from public.household_member_list(:'ha') where user_id = :'ub'), null, 'član bez imena ima null');
select tests.clear_auth();

select tests.authenticate_as(:'ub');
select is(
  array(select role from public.household_member_list(:'ha')),
  array['owner', 'member'],
  'član vidi uloge, vlasnik prvi'
);
select tests.clear_auth();

select tests.authenticate_as(:'uc');
select throws_ok(format('select * from public.household_member_list(%L)', :'ha'), '42501', 'not_household_member', 'stranac ne vidi tuđe članove');
select is((select count(*) from public.household_member_list(tests.household_of(:'uc'))), 1::bigint, 'stranac vidi svoje domaćinstvo');
select tests.clear_auth();

select * from finish();
rollback;
