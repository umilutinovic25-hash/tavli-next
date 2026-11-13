-- Alergije po osobi: vlasnik O i član M dele domaćinstvo H; X je van njega.
-- Članovi čitaju alergije svih u H, menja ih samo osoba sama; X ne vidi
-- ništa; izlazak iz domaćinstva briše red; prenos starih alergija ide osobi
-- koja ih je upisala, inače vlasniku, sa kodovima za EU nazive.
begin;
select * from no_plan();

select tests.create_user('o@test.local') as uo \gset
select tests.create_user('m@test.local') as um \gset
select tests.create_user('x@test.local') as ux \gset
select tests.household_of(:'uo') as ho \gset
select tests.household_of(:'ux') as hx \gset

insert into public.household_members (household_id, user_id, role) values (:'ho', :'um', 'member');

select tests.authenticate_as(:'uo');
select lives_ok(format($$insert into public.member_allergies (id, household_id, codes, custom) values (%L, %L, '["peanuts"]', '["jagode"]')$$, :'ho' || ':' || :'uo', :'ho'), 'O upisuje svoje alergije');
select throws_ok(format($$insert into public.member_allergies (id, household_id, user_id) values (%L, %L, %L)$$, :'ho' || ':' || :'um', :'ho', :'um'), '42501', null, 'O ne upisuje alergije za M');
select throws_ok(format($$insert into public.member_allergies (id, household_id) values (%L, %L)$$, :'ho' || ':pogresno', :'ho'), '23514', null, 'id mora biti domaćinstvo:osoba');
select throws_ok(format($$update public.member_allergies set codes = '["kikiriki"]' where household_id = %L$$, :'ho'), '23514', null, 'kodovi samo iz EU liste');
select throws_ok(format($$update public.member_allergies set custom = '[""]' where household_id = %L$$, :'ho'), '23514', null, 'slobodan unos nije prazan');
select tests.clear_auth();

select tests.authenticate_as(:'um');
select lives_ok(format($$insert into public.member_allergies (id, household_id, codes) values (%L, %L, '["gluten"]')$$, :'ho' || ':' || :'um', :'ho'), 'M upisuje svoje alergije');
select is((select count(*) from public.member_allergies where household_id = :'ho'), 2::bigint, 'M vidi alergije svih članova H');
select is(tests.affected(format($$update public.member_allergies set codes = '[]' where id = %L$$, :'ho' || ':' || :'uo')), 0::bigint, 'M ne menja alergije od O');
select is(tests.affected(format($$delete from public.member_allergies where id = %L$$, :'ho' || ':' || :'uo')), 0::bigint, 'M ne briše alergije od O');
select tests.clear_auth();

select tests.authenticate_as(:'ux');
select is((select count(*) from public.member_allergies), 0::bigint, 'X ne vidi alergije domaćinstva H');
select throws_ok(format($$insert into public.member_allergies (id, household_id) values (%L, %L)$$, :'ho' || ':' || :'ux', :'ho'), '42501', null, 'X ne upisuje u H');
select tests.clear_auth();

select tests.authenticate_anon();
select throws_ok('select count(*) from public.member_allergies', '42501', null, 'anon nema pristup');
select tests.clear_auth();

-- Napuštanje briše red i ostavlja trag; ponovni ulazak uklanja trag.
select tests.authenticate_as(:'um');
select public.leave_household(:'ho');
select tests.clear_auth();
select is((select count(*) from public.member_allergies where id = :'ho' || ':' || :'um'), 0::bigint, 'napuštanje briše alergije člana');
select is((select count(*) from public.deletions where entity = 'member_allergy' and record_id = :'ho' || ':' || :'um'), 1::bigint, 'trag brisanja za ostale uređaje');
select is((select count(*) from public.member_allergies where id = :'ho' || ':' || :'uo'), 1::bigint, 'alergije vlasnika ostaju');

insert into public.household_members (household_id, user_id, role) values (:'ho', :'um', 'member');
select tests.authenticate_as(:'um');
select lives_ok(format($$insert into public.member_allergies (id, household_id, codes) values (%L, %L, '["milk"]')$$, :'ho' || ':' || :'um', :'ho'), 'posle ponovnog ulaska M opet upisuje alergije');
select tests.clear_auth();
select is((select count(*) from public.member_allergies where id = :'ho' || ':' || :'um'), 1::bigint, 'novi red nije preskočen zbog starog traga');
select is((select count(*) from public.deletions where entity = 'member_allergy' and record_id = :'ho' || ':' || :'um'), 0::bigint, 'stari trag je uklonjen');

-- Uklanjanje člana (vlasnik) briše i njegov red.
select tests.authenticate_as(:'uo');
select public.remove_household_member(:'ho', :'um');
select tests.clear_auth();
select is((select count(*) from public.member_allergies where id = :'ho' || ':' || :'um'), 0::bigint, 'uklanjanje člana briše njegove alergije');

-- Prenos starih alergija domaćinstva.
delete from public.member_allergies;
insert into public.household_members (household_id, user_id, role) values (:'ho', :'um', 'member');
insert into public.household_preferences (id, household_id, allergies, updated_by)
  values (:'ho', :'ho', '["Kikiriki", "orasasti plodovi", "jagode"]', :'um'),
         (:'hx', :'hx', '["mleko"]', null);
-- touch_updated_at upisuje auth.uid() (null) u updated_by; vraćamo autora.
update public.household_preferences set updated_by = :'um' where id = :'ho';
select private.migrate_household_allergies();

select is((select codes from public.member_allergies where id = :'ho' || ':' || :'um'), '["nuts", "peanuts"]'::jsonb, 'autor (updated_by) dobija EU kodove');
select is((select custom from public.member_allergies where id = :'ho' || ':' || :'um'), '["jagode"]'::jsonb, 'ostalo ide u slobodan unos');
select is((select codes from public.member_allergies where id = :'hx' || ':' || :'ux'), '["milk"]'::jsonb, 'bez autora alergije dobija vlasnik');
select is((select count(*) from public.household_preferences where jsonb_array_length(allergies) > 0), 0::bigint, 'zajednički spisak je prazan');

select * from finish();
rollback;
