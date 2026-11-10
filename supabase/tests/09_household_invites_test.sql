-- Pozivnice za domaćinstvo: vlasnik vidi i upravlja svojim pozivnicama, drugi
-- nalog ne vidi tuđe; istekla, poništena i pogrešna pozivnica ne prolaze;
-- ograničenje pokušaja radi; anon nema pristup.
begin;
select * from no_plan();

select tests.create_user('a@test.local') as ua \gset
select tests.create_user('b@test.local') as ub \gset
select tests.create_user('c@test.local') as uc \gset
select tests.create_user('d@test.local') as ud \gset
select tests.create_user('e@test.local') as ue \gset
select tests.household_of(:'ua') as ha \gset
select tests.household_of(:'ub') as hb \gset

-- Pozivnice (kao postgres, bez RLS-a).
insert into public.household_invites (household_id, code, created_by)
  values (:'ha', 'K7P2MD', :'ua'),
         (:'ha', 'Q5T7XB', :'ua'),
         (:'ha', 'W3N9XC', :'ua');
insert into public.household_invites (household_id, code, created_by, created_at, expires_at)
  values (:'ha', 'H4R8TQ', :'ua', now() - interval '8 days', now() - interval '1 day');
update public.household_invites set revoked_at = now() where code = 'W3N9XC';
insert into public.household_invites (household_id, code, created_by)
  values (:'hb', 'T4N6GD', :'ub');

-- Kod mora da ima tačno 6 znakova iz dozvoljenog alfabeta.
select throws_ok(format($$insert into public.household_invites (household_id, code) values (%L, 'O0I1L2')$$, :'ha'), '23514', null, 'kod sa 0, O, 1, I, L se odbija');
select throws_ok(format($$insert into public.household_invites (household_id, code) values (%L, 'K7P2M')$$, :'ha'), '23514', null, 'kod kraći od 6 znakova se odbija');

-- Vlasnik A.
select tests.authenticate_as(:'ua');
select is((select count(*) from public.household_invites), 4::bigint, 'vlasnik vidi sve pozivnice svog domaćinstva');
select lives_ok(format($$insert into public.household_invites (household_id, code, created_by) values (%L, 'M8F4PD', %L)$$, :'ha', :'ua'), 'vlasnik pravi pozivnicu');
select throws_ok(format($$insert into public.household_invites (household_id, code, created_by) values (%L, 'R6V3TN', %L)$$, :'hb', :'ua'), '42501', null, 'vlasnik ne pravi pozivnicu u tuđem domaćinstvu');
select throws_ok(format($$insert into public.household_invites (household_id, code, created_by) values (%L, 'R6V3TN', %L)$$, :'ha', :'ub'), '42501', null, 'created_by mora da bude pozivalac');
select is(tests.affected($$update public.household_invites set revoked_at = now() where code = 'M8F4PD'$$), 1::bigint, 'vlasnik poništava svoju pozivnicu');
select throws_ok($$update public.household_invites set revoked_at = null where code = 'M8F4PD'$$, '42501', null, 'poništena pozivnica se ne vraća');
select throws_ok($$update public.household_invites set uses = 0 where code = 'K7P2MD'$$, '42501', null, 'uses se ne menja kroz API');
select throws_ok($$update public.household_invites set code = 'X2X2X2' where code = 'K7P2MD'$$, '42501', null, 'kod se ne menja kroz API');
select throws_ok($$delete from public.household_invites where code = 'K7P2MD'$$, '42501', null, 'pozivnica se ne briše kroz API');
select tests.clear_auth();

-- Drugi nalog B ne vidi i ne menja tuđe pozivnice.
select tests.authenticate_as(:'ub');
select is((select count(*) from public.household_invites where household_id = :'ha'), 0::bigint, 'drugi nalog ne vidi tuđe pozivnice');
select is(tests.affected($$update public.household_invites set revoked_at = now() where code = 'K7P2MD'$$), 0::bigint, 'drugi nalog ne poništava tuđu pozivnicu');
select throws_ok(format($$insert into public.household_invites (household_id, code, created_by) values (%L, 'R6V3TN', %L)$$, :'ha', :'ub'), '42501', null, 'drugi nalog ne pravi pozivnicu u tuđem domaćinstvu');
select tests.clear_auth();

-- B unosi važeći kod: postaje član A-ovog domaćinstva kao 'member'.
select tests.authenticate_as(:'ub');
select is(public.redeem_household_invite('K7P2MD'), :'ha'::uuid, 'važeći kod vraća domaćinstvo');
select is(public.redeem_household_invite('K7P2MD'), :'ha'::uuid, 'ponovljeni unos istog koda je bezopasan');
select is(public.redeem_household_invite('H4R8TQ'), null::uuid, 'istekla pozivnica ne prolazi');
select is(public.redeem_household_invite('W3N9XC'), null::uuid, 'poništena pozivnica ne prolazi');
select is(public.redeem_household_invite('ZZZZZZ'), null::uuid, 'pogrešan kod ne prolazi');
select is((select count(*) from public.household_invites where household_id = :'ha'), 0::bigint, 'član (ne vlasnik) ne vidi pozivnice');
select tests.clear_auth();

select is((select role from public.household_members where household_id = :'ha' and user_id = :'ub'), 'member', 'B je član sa ulogom member');
select is((select count(*) from public.household_members where user_id = :'ub'), 2::bigint, 'B zadržava svoje domaćinstvo i pridružuje se A-ovom');
select is((select uses from public.household_invites where code = 'K7P2MD'), 1, 'uses se povećava jednom, ne pri ponovnom unosu');

-- Poništavanje posle upotrebe: kod više ne prolazi, ni za članove.
update public.household_invites set revoked_at = now() where code = 'Q5T7XB';
select tests.authenticate_as(:'ub');
select is(public.redeem_household_invite('Q5T7XB'), null::uuid, 'pozivnica poništena posle izdavanja ne prolazi');
select tests.clear_auth();

-- Kod se prihvata bez obzira na velika slova i razmake.
select tests.authenticate_as(:'uc');
select is(public.redeem_household_invite(' k7p2md '), :'ha'::uuid, 'kod se normalizuje (mala slova, razmaci)');
select tests.clear_auth();

-- Ograničenje: 5 neuspešnih pokušaja u 10 minuta, pa ni tačan kod ne prolazi.
select tests.authenticate_as(:'ud');
select is(public.redeem_household_invite('ZZZZZZ'), null::uuid, 'neuspeh 1');
select is(public.redeem_household_invite('ZZZZZZ'), null::uuid, 'neuspeh 2');
select is(public.redeem_household_invite('ZZZZZZ'), null::uuid, 'neuspeh 3');
select is(public.redeem_household_invite('ZZZZZZ'), null::uuid, 'neuspeh 4');
select is(public.redeem_household_invite('ZZZZZZ'), null::uuid, 'neuspeh 5');
select throws_ok($$select public.redeem_household_invite('K7P2MD')$$, 'P0429', null, 'posle 5 neuspešnih pokušaja ni tačan kod ne prolazi');
select tests.clear_auth();

-- Stari neuspesi (preko 10 minuta) se ne broje.
insert into private.household_invite_failures (user_id, failed_at)
  select :'ue'::uuid, now() - interval '11 minutes' from generate_series(1, 5);
select tests.authenticate_as(:'ue');
select is(public.redeem_household_invite('K7P2MD'), :'ha'::uuid, 'stari neuspesi ne blokiraju korisnika');
select tests.clear_auth();

-- Anonimni korisnik nema pristup ni funkciji ni tabeli.
select tests.authenticate_anon();
select throws_ok($$select public.redeem_household_invite('K7P2MD')$$, '42501', null, 'anon ne izvršava redeem');
select throws_ok($$select count(*) from public.household_invites$$, '42501', null, 'anon ne čita pozivnice');
select tests.clear_auth();

-- Grantovi.
select ok(has_function_privilege('authenticated', 'public.redeem_household_invite(text)', 'EXECUTE'), 'authenticated izvršava redeem');
select ok(not has_function_privilege('anon', 'public.redeem_household_invite(text)', 'EXECUTE'), 'anon ne izvršava redeem');
select ok(not has_table_privilege('authenticated', 'public.household_invites', 'DELETE'), 'authenticated nema DELETE nad pozivnicama');
select ok(not has_table_privilege('anon', 'public.household_invites', 'SELECT'), 'anon nema SELECT nad pozivnicama');
select ok(not has_table_privilege('authenticated', 'private.household_invite_failures', 'SELECT'), 'authenticated ne čita brojač pokušaja');

select * from finish();
rollback;
