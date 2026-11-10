-- Članstvo domaćinstva: uklanjanje člana, napuštanje i prenos vlasništva.
-- Vlasnik O i članovi M1, M2, M3 u domaćinstvu H; X ima svoje domaćinstvo.
-- Svaki korisnik ima i lično domaćinstvo (okidač pri pravljenju naloga), pa
-- funkcije moraju da rade nad domaćinstvom H, a ne nad prvim članstvom.
begin;
select plan(29);

select tests.create_user('o@test.local') as uo \gset
select tests.create_user('m1@test.local') as um1 \gset
select tests.create_user('m2@test.local') as um2 \gset
select tests.create_user('m3@test.local') as um3 \gset
select tests.create_user('x@test.local') as ux \gset
select tests.household_of(:'uo') as ho \gset

insert into public.household_members (household_id, user_id, role)
  values (:'ho', :'um1', 'member'), (:'ho', :'um2', 'member'), (:'ho', :'um3', 'member');

-- Anon ne može da pozove nijednu funkciju.
select tests.authenticate_anon();
select throws_ok(format('select public.remove_household_member(%L, %L)', :'ho', :'um1'), '42501', null, 'anon ne uklanja člana');
select throws_ok(format('select public.leave_household(%L)', :'ho'), '42501', null, 'anon ne napušta domaćinstvo');
select tests.clear_auth();

-- Član ne sme da uklanja, ni da prenosi vlasništvo.
select tests.authenticate_as(:'um1');
select throws_ok(format('select public.remove_household_member(%L, %L)', :'ho', :'uo'), '42501', null, 'član ne uklanja vlasnika');
select throws_ok(format('select public.remove_household_member(%L, %L)', :'ho', :'um2'), '42501', null, 'član ne uklanja drugog člana');
select throws_ok(format('select public.transfer_household_ownership(%L, %L)', :'ho', :'um2'), '42501', null, 'član ne prenosi vlasništvo');
select tests.clear_auth();

-- Vlasnik samo svog ličnog domaćinstva nema prava nad tuđim domaćinstvom.
select tests.authenticate_as(:'ux');
select throws_ok(format('select public.remove_household_member(%L, %L)', :'ho', :'um2'), '42501', 'not_owner', 'vlasnik ličnog domaćinstva ne uklanja člana tuđeg');
select throws_ok(format('select public.transfer_household_ownership(%L, %L)', :'ho', :'um2'), '42501', 'not_owner', 'vlasnik ličnog domaćinstva ne prenosi tuđe vlasništvo');
select tests.clear_auth();

-- Vlasnik: ne sebe, ne tuđe, ne sebi, ne van domaćinstva; ne napušta pre prenosa.
select tests.authenticate_as(:'uo');
select throws_ok(format('select public.remove_household_member(%L, %L)', :'ho', :'uo'), 'P0001', 'cannot_remove_self', 'vlasnik ne uklanja sebe');
select throws_ok(format('select public.remove_household_member(%L, %L)', :'ho', :'ux'), 'P0001', 'not_household_member', 'ne uklanja osobu iz tuđeg domaćinstva');
select throws_ok(format('select public.transfer_household_ownership(%L, %L)', :'ho', :'uo'), 'P0001', 'cannot_transfer_to_self', 'vlasnik ne prenosi sebi');
select throws_ok(format('select public.transfer_household_ownership(%L, %L)', :'ho', :'ux'), 'P0001', 'not_household_member', 'novi vlasnik mora biti u domaćinstvu');
select throws_ok(format('select public.leave_household(%L)', :'ho'), 'P0001', 'owner_must_transfer', 'vlasnik ne napušta pre prenosa');
select tests.clear_auth();

-- Vlasnik uklanja M1; M1 zadržava svoje lično domaćinstvo.
select tests.authenticate_as(:'uo');
select lives_ok(format('select public.remove_household_member(%L, %L)', :'ho', :'um1'), 'vlasnik uklanja člana');
select tests.clear_auth();
select is((select count(*) from public.household_members where household_id = :'ho' and user_id = :'um1'), 0::bigint, 'uklonjeni član više nije u domaćinstvu');
select is((select role from public.household_members where user_id = :'um1'), 'owner', 'uklonjeni član ima svoje (lično) domaćinstvo');
select is((select count(*) from public.household_members where user_id = :'um1'), 1::bigint, 'uklonjeni član ima tačno jedno članstvo');

-- M2 napušta domaćinstvo H i zadržava svoje lično.
select tests.authenticate_as(:'um2');
select lives_ok(format('select public.leave_household(%L)', :'ho'), 'član napušta domaćinstvo');
select tests.clear_auth();
select is((select count(*) from public.household_members where household_id = :'ho' and user_id = :'um2'), 0::bigint, 'napustio član više nije u domaćinstvu');
select is((select role from public.household_members where user_id = :'um2'), 'owner', 'napustio član ima svoje (lično) domaćinstvo');

-- Prenos vlasništva na M3: O postaje član, M3 vlasnik.
select tests.authenticate_as(:'uo');
select lives_ok(format('select public.transfer_household_ownership(%L, %L)', :'ho', :'um3'), 'vlasnik prenosi vlasništvo članu');
select tests.clear_auth();
select is((select role from public.household_members where household_id = :'ho' and user_id = :'uo'), 'member', 'stari vlasnik postaje član');
select is((select role from public.household_members where household_id = :'ho' and user_id = :'um3'), 'owner', 'novi vlasnik je u domaćinstvu kao vlasnik');

-- Bivši vlasnik više ne uklanja; sada sme da napusti.
select tests.authenticate_as(:'uo');
select throws_ok(format('select public.remove_household_member(%L, %L)', :'ho', :'um3'), '42501', null, 'bivši vlasnik više ne uklanja');
select lives_ok(format('select public.leave_household(%L)', :'ho'), 'bivši vlasnik sada može da napusti');
select tests.clear_auth();
select is((select role from public.household_members where user_id = :'uo'), 'owner', 'napustio bivši vlasnik ima svoje (lično) domaćinstvo');

-- Novi vlasnik ne sme da napusti pre prenosa, niti da ukloni sebe.
select tests.authenticate_as(:'um3');
select throws_ok(format('select public.leave_household(%L)', :'ho'), 'P0001', 'owner_must_transfer', 'novi vlasnik ne napušta pre prenosa');
select throws_ok(format('select public.remove_household_member(%L, %L)', :'ho', :'um3'), 'P0001', 'cannot_remove_self', 'novi vlasnik ne uklanja sebe');
select tests.clear_auth();

-- Šema: uloga mora biti owner ili member; jedan vlasnik po domaćinstvu.
select throws_ok(
  format('insert into public.household_members (household_id, user_id, role) values (%L, %L, %L)', :'ho', :'ux', 'admin'),
  '23514', null, 'nepoznata uloga se odbija'
);
select throws_ok(
  format('insert into public.household_members (household_id, user_id, role) values (%L, %L, %L)', :'ho', :'ux', 'owner'),
  '23505', null, 'drugi vlasnik u domaćinstvu se odbija'
);

select * from finish();
