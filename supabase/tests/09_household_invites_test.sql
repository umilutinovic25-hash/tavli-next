-- Pozivnice za domaćinstvo: pravi se samo kroz create_household_invite (kod pravi
-- server), vlasnik vidi i poništava svoje, drugi nalog ne vidi tuđe, istekla,
-- poništena, iskorišćena i pogrešna pozivnica ne prolaze; ograničenja pokušaja
-- rade; anon nema pristup.
begin;
select * from no_plan();

select tests.create_user('a@test.local') as ua \gset
select tests.create_user('b@test.local') as ub \gset
select tests.create_user('c@test.local') as uc \gset
select tests.create_user('d@test.local') as ud \gset
select tests.create_user('e@test.local') as ue \gset
select tests.create_user('f@test.local') as uf \gset
select tests.create_user('g@test.local') as ug \gset
select tests.create_user('h@test.local') as uh \gset
select tests.household_of(:'ua') as ha \gset
select tests.household_of(:'ub') as hb \gset

-- Pozivnice (kao postgres, bez RLS-a).
insert into public.household_invites (household_id, code, created_by)
  values (:'ha', 'K7P2MDXN', :'ua'),
         (:'ha', 'Q5T7XBNR', :'ua'),
         (:'ha', 'W3N9XCTR', :'ua'),
         (:'hb', 'T4N6GDWP', :'ub');
insert into public.household_invites (household_id, code, created_by, created_at, expires_at)
  values (:'ha', 'H4R8TQZM', :'ua', now() - interval '8 days', now() - interval '1 day');
insert into public.household_invites (household_id, code, created_by, max_uses)
  values (:'ha', 'P9Z2KWRM', :'ua', 1);
update public.household_invites set revoked_at = now() where code = 'W3N9XCTR';

-- Kod mora da ima tačno 8 znakova iz dozvoljenog alfabeta.
select throws_ok(format($$insert into public.household_invites (household_id, code) values (%L, 'O0I1L2AB')$$, :'ha'), '23514', null, 'kod sa 0, O, 1, I, L se odbija');
select throws_ok(format($$insert into public.household_invites (household_id, code) values (%L, 'K7P2MDX')$$, :'ha'), '23514', null, 'kod kraći od 8 znakova se odbija');

-- Vlasnik A.
select tests.authenticate_as(:'ua');
select is((select count(*) from public.household_invites), 5::bigint, 'vlasnik vidi sve pozivnice svog domaćinstva');
select throws_ok(format($$insert into public.household_invites (household_id, code, created_by) values (%L, 'M8F4PDKV', %L)$$, :'ha', :'ua'), '42501', null, 'vlasnik ne unosi pozivnicu direktno (samo kroz create_household_invite)');
select throws_ok($$update public.household_invites set revoked_at = null where code = 'W3N9XCTR'$$, '42501', null, 'poništena pozivnica se ne vraća');
select throws_ok($$update public.household_invites set uses = 0 where code = 'K7P2MDXN'$$, '42501', null, 'uses se ne menja kroz API');
select throws_ok($$update public.household_invites set code = 'X2X2X2X2' where code = 'K7P2MDXN'$$, '42501', null, 'kod se ne menja kroz API');
select throws_ok($$delete from public.household_invites where code = 'K7P2MDXN'$$, '42501', null, 'pozivnica se ne briše kroz API');

select public.create_household_invite(:'ha') as code_new \gset
select is(length(:'code_new'), 8, 'create_household_invite vraća 8-znakovni kod');
select ok(:'code_new' ~ '^[2-9A-HJ-KM-NP-Z]{8}$', 'kod koristi dozvoljeni alfabet');
select is((select household_id from public.household_invites where code = :'code_new'), :'ha'::uuid, 'pozivnica pripada domaćinstvu');
select is((select created_by from public.household_invites where code = :'code_new'), :'ua'::uuid, 'created_by je pozivalac');
select is((select expires_at - created_at from public.household_invites where code = :'code_new'), interval '7 days', 'pozivnica važi 7 dana');
select is((select max_uses from public.household_invites where code = :'code_new'), 5, 'pozivnica ima najviše 5 iskorišćenja');
select is(
  (select count(distinct c) from (select public.create_household_invite(:'ha') c from generate_series(1, 30)) s),
  30::bigint,
  'uzastopni kodovi su različiti'
);
select is(tests.affected(format($$update public.household_invites set revoked_at = now() where code = %L$$, :'code_new')), 1::bigint, 'vlasnik poništava svoju pozivnicu');
select tests.clear_auth();

-- Nevlasnik ne pravi pozivnicu ni kroz funkciju ni direktno.
select tests.authenticate_as(:'ub');
select throws_ok(format($$select public.create_household_invite(%L)$$, :'ha'), '42501', 'not_owner', 'drugi nalog ne pravi pozivnicu u tuđem domaćinstvu');
select throws_ok(format($$insert into public.household_invites (household_id, code, created_by) values (%L, 'R6V3TNYU', %L)$$, :'ha', :'ub'), '42501', null, 'drugi nalog ne unosi pozivnicu direktno');

-- Drugi nalog B ne vidi i ne menja tuđe pozivnice.
select is((select count(*) from public.household_invites where household_id = :'ha'), 0::bigint, 'drugi nalog ne vidi tuđe pozivnice');
select is(tests.affected($$update public.household_invites set revoked_at = now() where code = 'K7P2MDXN'$$), 0::bigint, 'drugi nalog ne poništava tuđu pozivnicu');

-- B unosi važeći kod: postaje član A-ovog domaćinstva kao 'member'.
select is(public.redeem_household_invite('K7P2MDXN'), :'ha'::uuid, 'važeći kod vraća domaćinstvo');
select is(public.redeem_household_invite('K7P2MDXN'), :'ha'::uuid, 'ponovljeni unos istog koda je bezopasan');
select is(public.redeem_household_invite('H4R8TQZM'), null::uuid, 'istekla pozivnica ne prolazi');
select is(public.redeem_household_invite('W3N9XCTR'), null::uuid, 'poništena pozivnica ne prolazi');
select is(public.redeem_household_invite('ZZZZZZZZ'), null::uuid, 'pogrešan kod ne prolazi');
select is((select count(*) from public.household_invites where household_id = :'ha'), 0::bigint, 'član (ne vlasnik) ne vidi pozivnice');
select tests.clear_auth();

select is((select role from public.household_members where household_id = :'ha' and user_id = :'ub'), 'member', 'B je član sa ulogom member');
select is((select count(*) from public.household_members where user_id = :'ub'), 2::bigint, 'B zadržava svoje domaćinstvo i pridružuje se A-ovom');
select is((select uses from public.household_invites where code = 'K7P2MDXN'), 1, 'uses se povećava jednom, ne pri ponovnom unosu');

-- Poništavanje posle izdavanja: kod više ne prolazi.
update public.household_invites set revoked_at = now() where code = 'Q5T7XBNR';
select tests.authenticate_as(:'ub');
select is(public.redeem_household_invite('Q5T7XBNR'), null::uuid, 'pozivnica poništena posle izdavanja ne prolazi');
select tests.clear_auth();

-- Kod se prihvata bez obzira na velika slova i razmake.
select tests.authenticate_as(:'uc');
select is(public.redeem_household_invite(' k7p2mdxn '), :'ha'::uuid, 'kod se normalizuje (mala slova, razmaci)');
select tests.clear_auth();

-- Iskorišćenje: max_uses = 1, pa drugi nalog ne prolazi.
select tests.authenticate_as(:'uf');
select is(public.redeem_household_invite('P9Z2KWRM'), :'ha'::uuid, 'prvi unos iskorišćuje pozivnicu do kraja');
select tests.clear_auth();
select tests.authenticate_as(:'ug');
select is(public.redeem_household_invite('P9Z2KWRM'), null::uuid, 'pozivnica iskorišćena do max_uses ne prolazi');
select tests.clear_auth();

-- Po kodu: 5 neuspeha za isti kod poništava pozivnicu sa tim kodom (istekla
-- pozivnica, da se ne bi mešalo sa aktivnom).
select tests.authenticate_as(:'uh');
select is(public.redeem_household_invite('H4R8TQZM'), null::uuid, 'neuspeh po kodu 1');
select is(public.redeem_household_invite('H4R8TQZM'), null::uuid, 'neuspeh po kodu 2');
select is(public.redeem_household_invite('H4R8TQZM'), null::uuid, 'neuspeh po kodu 3');
select is(public.redeem_household_invite('H4R8TQZM'), null::uuid, 'neuspeh po kodu 4');
select is(public.redeem_household_invite('H4R8TQZM'), null::uuid, 'neuspeh po kodu 5');
select tests.clear_auth();
select ok((select revoked_at is not null from public.household_invites where code = 'H4R8TQZM'), 'pozivnica se poništava posle 5 neuspešnih pokušaja nad istim kodom');

-- Ograničenje po nalogu: 5 neuspešnih pokušaja u 10 minuta, pa ni tačan kod ne prolazi.
select tests.authenticate_as(:'ud');
select is(public.redeem_household_invite('ZZZZZZZZ'), null::uuid, 'neuspeh 1');
select is(public.redeem_household_invite('ZZZZZZZZ'), null::uuid, 'neuspeh 2');
select is(public.redeem_household_invite('ZZZZZZZZ'), null::uuid, 'neuspeh 3');
select is(public.redeem_household_invite('ZZZZZZZZ'), null::uuid, 'neuspeh 4');
select is(public.redeem_household_invite('ZZZZZZZZ'), null::uuid, 'neuspeh 5');
select throws_ok($$select public.redeem_household_invite('K7P2MDXN')$$, 'P0429', null, 'posle 5 neuspešnih pokušaja ni tačan kod ne prolazi');
select tests.clear_auth();

-- Stari neuspesi (preko 10 minuta) se ne broje.
insert into private.household_invite_failures (user_id, failed_at)
  select :'ue'::uuid, now() - interval '11 minutes' from generate_series(1, 5);
select tests.authenticate_as(:'ue');
select is(public.redeem_household_invite('K7P2MDXN'), :'ha'::uuid, 'stari neuspesi ne blokiraju korisnika');
select tests.clear_auth();

-- Anonimni korisnik nema pristup ni funkcijama ni tabeli.
select tests.authenticate_anon();
select throws_ok($$select public.redeem_household_invite('K7P2MDXN')$$, '42501', null, 'anon ne izvršava redeem');
select throws_ok(format($$select public.create_household_invite(%L)$$, :'ha'), '42501', null, 'anon ne izvršava create');
select throws_ok($$select count(*) from public.household_invites$$, '42501', null, 'anon ne čita pozivnice');
select tests.clear_auth();

-- Grantovi.
select ok(has_function_privilege('authenticated', 'public.create_household_invite(uuid)', 'EXECUTE'), 'authenticated izvršava create');
select ok(not has_function_privilege('anon', 'public.create_household_invite(uuid)', 'EXECUTE'), 'anon ne izvršava create');
select ok(has_function_privilege('authenticated', 'public.redeem_household_invite(text)', 'EXECUTE'), 'authenticated izvršava redeem');
select ok(not has_function_privilege('anon', 'public.redeem_household_invite(text)', 'EXECUTE'), 'anon ne izvršava redeem');
select ok(not has_table_privilege('authenticated', 'public.household_invites', 'INSERT'), 'authenticated nema INSERT nad pozivnicama');
select ok(not has_table_privilege('authenticated', 'public.household_invites', 'DELETE'), 'authenticated nema DELETE nad pozivnicama');
select ok(not has_table_privilege('anon', 'public.household_invites', 'SELECT'), 'anon nema SELECT nad pozivnicama');
select ok(not has_table_privilege('authenticated', 'private.household_invite_failures', 'SELECT'), 'authenticated ne čita brojač pokušaja');
select ok(not has_table_privilege('authenticated', 'private.household_invite_code_failures', 'SELECT'), 'authenticated ne čita brojač po kodu');

select * from finish();
rollback;
