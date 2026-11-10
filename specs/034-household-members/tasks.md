# Tasks: Domaćinstvo — pozivanje, pridruživanje i članovi

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/household-api.md](contracts/household-api.md), [quickstart.md](quickstart.md)

**Tests**: obavezni (konstitucija V, TDD). Svaki zadatak: napiši test → pokreni i vidi da pada iz pravog razloga → minimalni kod → test prolazi → `dart format lib test` → commit (hook pokreće `scripts/check.sh` i pogođene testove; nikad `--no-verify`, bez `Co-Authored-By`).

**Okruženje**: `PATH=/Users/urosmilutinovic/.cache/tavli-flutter-sdk/bin:$PATH`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; commit kroz wrapper iz CLAUDE napomena sesije (hook nasleđuje `GIT_DIR`). Supabase samo lokalno.

**Format**: `- [ ] Tnnn [P?] [USn?] Opis sa putanjom`. Ispod zadatka su testovi (ime → očekivanje) i potpisi koje zadatak uvodi. Telo funkcija piše izvršilac.

---

## Phase 1: Setup

- [ ] T001 Potvrdi polaznu tačku u `~/tavli-agents/G-household-members`: grana `034-household-members` je na `origin/main` posle PR #31 (`git log --oneline -3` pokazuje `fac87ad` ispod docs commitova); `flutter pub get`; `flutter analyze` čist; `supabase start` i `supabase db reset` lokalno prolaze. Bez commita.

---

## Phase 2: Foundational (blokira sve priče)

### Server

- [ ] T002 [P] Funkcija `public.household_member_list` u `supabase/migrations/20261111130300_household_member_list.sql` i pgTAP `supabase/tests/14_household_member_list_test.sql` (ugovor §1).
  - Testovi (pišu se prvi, `supabase test db` pada jer funkcija ne postoji): vlasnik A i član B (pridružen kroz `redeem_household_invite`) dobijaju po 2 reda, vlasnik prvi, `display_name` tačan; stranac C → `throws_ok(..., '42501', 'not_household_member')`; `anon` nema `execute` (`function_privs_are` ili `has_function_privilege`); `pg_get_function_result(...)` = `TABLE(user_id uuid, display_name text, role text, joined_at timestamp with time zone)`.
  - Dopuni katalog test `supabase/tests/01_catalog_test.sql` novom funkcijom u istom commitu (pada dok se ne dopuni).
  - Provera: `supabase db reset && supabase test db` → svi fajlovi prolaze.

### Domen (test-first)

- [ ] T003 [P] Nove vrste i funkcije u `lib/domain/household.dart`, testovi u `test/domain/household_test.dart`.
  - Potpisi: `class Membership { householdId, householdName, HouseholdRole role, DateTime joinedAt }`, `class HouseholdMember { userId, String? displayName, HouseholdRole role, DateTime joinedAt }` (oba immutable, `==`/`hashCode`), `Membership pickActiveHousehold(List<Membership> all, {String? preferredId})` (baca `StateError` za praznu listu), `String formatInviteCode(String code)`, `String usesLeftText(int n)`, `String inviteDate(DateTime t)`.
  - Testovi: `pickActiveHousehold` bez izbora → najnoviji `joinedAt`; sa izborom koji postoji → izabrani; sa izborom koji ne postoji → najnoviji (Review Focus 5); prazna lista → `StateError`. `formatInviteCode('ABCDEFGH')` → `'ABCD EFGH'`. `usesLeftText`: 1 → `'Još 1 upotreba'`, 2/3/4 → `'Još 2 upotrebe'`…, 5 → `'Još 5 upotreba'`, 12 → `'Još 12 upotreba'`, 22 → `'Još 22 upotrebe'`. `inviteDate(DateTime(2026, 11, 17))` → `'17.11.2026.'`.

- [ ] T004 [P] Izmene `lib/domain/household_invite.dart`, testovi u `test/domain/household_invite_test.dart`.
  - `normalizeInviteCode(' abcd-efgh\n')` → `'ABCDEFGH'`; `'AB CD EF GH'` → `'ABCDEFGH'`; postojeći testovi ostaju zeleni (Review Focus 3).
  - `HouseholdInvite` dobija `final int maxUses` (konstruktor: podrazumevano 5) i `int get usesLeft => maxUses - uses`; `isInviteUsable` vraća false kad je `usesLeft <= 0` (novi test) i zadržava postojeća pravila.

### Podaci

- [ ] T005 [P] `max_uses` u `SupabaseHouseholdInviteRemote._fromRow` (`lib/data/household_invite_repository.dart`), test u `test/data/household_invite_repository_test.dart`: red sa `'max_uses': 3, 'uses': 1` → `usesLeft == 2`; red bez `max_uses` → `maxUses == 5`.

- [ ] T006 Interfejs članstva u `lib/data/household_membership_repository.dart` (ugovor §2), testovi u `test/data/household_membership_repository_test.dart`.
  - Uvedi `HouseholdMembershipRemote` i `SupabaseHouseholdMembershipRemote(SupabaseClient)` sa sadašnjim `_call`/`_classify`; `HouseholdMembershipRepository(HouseholdMembershipRemote)`. Postojeći testovi prave repozitorijum preko `SupabaseHouseholdMembershipRemote(client)` i proveravaju isto što i sada.
  - Novo `Future<List<HouseholdMember>> listMembers(String householdId)` → `rpc('household_member_list', params: {'p_household_id': id})`.
  - Novi testovi: odgovor sa dva reda → dva `HouseholdMember` sa ulogama i `displayName` (null ostaje null); telo zahteva sadrži `p_household_id`; `{'message': 'not_household_member', 'code': '42501'}` → `NotHouseholdMember`; nepoznata uloga → `MembershipServerError` (FormatException iz `HouseholdRole.parse` se mapira, ne curi).

- [ ] T007 Drift v16 u `lib/data/database.dart` (data-model), regenerisan `lib/data/database.g.dart`, test u `test/data/migration_test.dart`.
  - `accounts.preferredHouseholdId` (text nullable); tabele `HouseholdMemberships` (PK accountId+householdId) i `HouseholdMemberCache` (PK accountId+householdId+userId) sa kolonama iz data-model.md; `schemaVersion => 16`; `from < 16` korak: `addColumn` + dva `createTable`.
  - Test: v15 baza sa redom u `accounts` → otvaranje kao v16 → nalog postoji, `preferredHouseholdId == null`, obe tabele postoje i prazne su; sveža v16 baza se pravi bez greške.
  - `dart run build_runner build --delete-conflicting-outputs`; `.g.dart` u istom commitu.

### Nalog

- [ ] T008 `RemoteAccount.memberships` u `lib/account/account_api.dart` (ugovor §3), test u `test/account/account_service_test.dart` (grupa `SupabaseAccountApi.fetch`).
  - Upit: `select('household_id, role, joined_at, households(name)')`, `.order('joined_at', ascending: false)`, bez `limit`. Postojeća polja = prvo članstvo.
  - Testovi: dva reda → `memberships.length == 2`, redosled kao sa servera, `householdName` iz `households.name`, uloga parsirana; zahtev ima `order=joined_at.desc…` i nema `limit`; postojeći testovi (`sa dva članstva bira poslednje pridruženo…`, ponavljanje, 401, offline) ostaju zeleni. `FakeAccountApi` u `test/helpers/fake_backend.dart` vraća `memberships` sa jednim (ličnim) članstvom.

- [ ] T009 `AccountService.refresh` i pomoćne metode u `lib/account/account_service.dart` (ugovor §4, prelazi u data-model.md), testovi u `test/account/account_service_test.dart` (grupa `AccountService`).
  - Potpisi: `Future<Account> refresh(AuthSession session)`, `Future<void> setPreferredHousehold(String userId, String? householdId)`, `Future<void> cacheMembers(String userId, String householdId, List<HouseholdMember> members, DateTime fetchedAt)`, `Stream<List<Membership>> watchMemberships(String userId)`, `Stream<List<HouseholdMember>> watchMembers(String userId, String householdId)`; privatni `_purgeHousehold(String householdId)` izdvojen iz `wipeLocal` (ponašanje `wipeLocal` nepromenjeno — postojeći testovi to dokazuju).
  - Sve izmene jednog `refresh` su jedna drift transakcija.
  - `FakeAccountApi` dobija mogućnost da vrati zadat skup članstava (polje u `FakeServer`, vidi T010) — ako je T010 još nije uradio, ovaj zadatak dodaje samo minimalno polje `memberships` u `FakeServer`.
  - Testovi:
    1. `refresh` uvek pita server i kad nalog postoji u kešu (keš ima `home-1`, server vraća `home-2` kao poslednje) → `householdId == 'home-2'`, red u `accounts` ažuriran.
    2. Promenjen skup članstava → `sync_cursors` naloga prazan, `initialDownloadDone == false` (Review Focus 1). Isti skup → kursori netaknuti.
    3. Nestalo članstvo `home-2` → lokalni recepti/nabavka/ostava sa `householdId == 'home-2'` obrisani, oni sa `home-1` ostaju; outbox stavke čiji red pripada `home-2` obrisane; fotografije tih recepata obrisane iz `RecipePhotoStore` (Review Focus 2).
    4. `preferred_household_id` koji više nije među članstvima → posle `refresh` null, aktivno = poslednje pridruženo (Review Focus 5).
    5. `setPreferredHousehold('u', 'home-1')` pa `refresh` → aktivno `home-1`.
    6. Bez mreže → baca `Offline`, keš i kursori nepromenjeni.
    7. `cacheMembers` zamenjuje ceo skup za (nalog, domaćinstvo); `watchMembers` emituje novu listu; članovi drugog domaćinstva netaknuti.

- [ ] T010 `AuthController.refreshAccount` u `lib/account/auth_controller.dart` (ugovor §5) i `FakeHouseholdServer` u `test/helpers/fake_backend.dart`; testovi u `test/account/auth_controller_test.dart`.
  - `FakeServer` model: `memberships` (householdId → {userId → (role, joinedAt)}), `householdNames`, pozivnice (kod, rok, maxUses, uses, revoked), brojač `calls` po radnji; `_visible` za red sa `household_id` gleda članstvo umesto `households[userId]` (postojeći testovi ostaju zeleni jer lično domaćinstvo ostaje članstvo). Dodaj `FakeInviteRemote implements HouseholdInviteRemote` i `FakeMembershipRemote implements HouseholdMembershipRemote` nad istim stanjem (pravila kao migracije: samo vlasnik pravi/poništava, 5 neuspeha → `InviteTooManyAttempts`, redeem postojećeg člana ne troši upotrebu, vlasnik ne može da napusti, uklanjanje/prenos traže vlasnika); izloži ih kroz `FakeBackend.invites` / `FakeBackend.membership`.
  - `refreshAccount()` vraća `true` i postavlja novi `SignedIn` sa novim `householdId`; bez mreže vraća `false` i stanje ostaje; `SessionRevoked` ide u postojeći tok `sessionExpired`.
  - `start()` posle `SignedIn` iz keša poziva `refreshAccount()` bez čekanja (komentar sa razlogom za `unawaited`); test: server ima novije članstvo → posle `pumpEventQueue` stanje ima novo domaćinstvo; offline start i dalje daje `SignedIn` iz keša.
  - Integracioni test (Review Focus 1) u `test/sync/` ili `test/account/`: B ima kursor posle T0; A u zajedničkom domaćinstvu ima red sa `updated_at` pre T0; B se pridruži (`FakeBackend`), `refreshAccount`, `syncEngine.pull()` → red je u B-ovoj lokalnoj bazi.

### Akcije i tekstovi

- [ ] T011 Provajderi u `lib/providers.dart`: `householdInviteRepositoryProvider`, `householdMembershipRepositoryProvider` (Supabase remote kad je klijent konfigurisan, inače remote koji baca `InviteOffline`/`MembershipOffline`), `householdMembershipsProvider` (StreamProvider iz `watchMemberships`), `householdMembersProvider` (StreamProvider iz `watchMembers` za aktivni scope); `test/helpers/test_app.dart` override-uje oba remote-a vrednostima iz `FakeBackend`. Test: `test/app/providers_test.dart` ili postojeći ekvivalent — bez Supabase konfiguracije `householdMembershipRepositoryProvider.leave(...)` baca `MembershipOffline`.

- [ ] T012 [P] `householdErrorText(Object error)` u `lib/features/household/household_error_text.dart` (ugovor §7), test `test/features/household/household_error_text_test.dart`: svaka klasa iz tabele → tačan tekst; nepoznata greška → `'Nešto nije uspelo. Pokušaj ponovo.'`; nijedan tekst ne sadrži `toString()` greške.

- [ ] T013 `HouseholdActions` i `HouseholdOutcome` u `lib/features/household/household_actions.dart` (ugovor §6) + `householdActionsProvider`; testovi `test/features/household/household_actions_test.dart` nad `FakeBackend`.
  - Svaka radnja: poziv repozitorijumu → na uspeh `refreshAccount()` (i `reloadMembers()` gde ugovor kaže) → `HouseholdDone(tekst iz spec)`; na grešku `HouseholdFailed(householdErrorText(e))`; nikad ne baca.
  - `join(raw)`: `normalizeInviteCode` → `redeem` → `setPreferredHousehold(userId, vraćeniId)` → `refreshAccount()` → `HouseholdDone('Sada si član domaćinstva „{naziv}“.')` sa nazivom iz osveženog naloga.
  - `reloadMembers()`: `listMembers` → `cacheMembers`; vraća false bez mreže.
  - Testovi: `join` sa važećim kodom → aktivno domaćinstvo promenjeno, poruka sa nazivom; `join` koda domaćinstva čiji je već član → aktivno postaje to domaćinstvo, `uses` nepromenjen; `leave` vlasnika → `HouseholdFailed('Pre napuštanja prenesi vlasništvo drugom članu.')`; `removeMember` → član nestao iz keša, poruka „Član je uklonjen.“; offline → „Za ovo je potrebna internet veza.“, bez poziva `refreshAccount`.

**Checkpoint**: ceo `flutter test` i `supabase test db` zeleni pre UI zadataka.

---

## Phase 3: User Story 1 — Vlasnik poziva člana kodom (P1) 🎯 MVP

**Cilj**: vlasnik pravi, deli i poništava pozivnice. **Nezavisni test**: kod se pojavi u listi, posle poništavanja nestaje i redeem daje „Kod nije važeći ili je istekao.“

- [ ] T014 [US1] Ruta i ulaz: `/profile/household` u `lib/app/router.dart`, stavka „Domaćinstvo“ (podnaslov = naziv aktivnog domaćinstva) u `lib/features/settings/profile_screen.dart`, kostur `lib/features/household/household_screen.dart` (AppBar „Domaćinstvo“, naziv domaćinstva, sopstvena uloga). Test `test/features/household/household_screen_test.dart`: dodir na „Domaćinstvo“ u Profilu otvara ekran sa nazivom; postojeći test profila ostaje zelen.

- [ ] T015 [US1] `lib/features/household/invites_section.dart` + `lib/features/household/invite_code_sheet.dart`, testovi u `household_screen_test.dart`.
  - Vlasnik vidi „Pozovi člana“ i „Aktivne pozivnice“ (lista iz `loadInvites()`, samo `isInviteUsable`; prazno → „Nema aktivnih pozivnica.“); član ne vidi ništa od toga (US1-6).
  - „Pozovi člana“: dugme onemogućeno uz indikator dok traje zahtev (Review Focus 4: dupli dodir → `calls['create'] == 1`); uspeh otvara list sa „Kod za pozivanje“, `formatInviteCode`, „Važi do {inviteDate}“, `usesLeftText`.
  - „Kopiraj kod“ → `Clipboard` ima kod bez razmaka, SnackBar „Kod je kopiran.“ (test preko `SystemChannels.platform` mock-a).
  - „Podeli“ → `SharePlus.instance.share` sa tačnim tekstom iz spec (test preko override-a ili kanal mock-a `share_plus`; ako share nije testabilan bez platforme, izdvoji `inviteShareText(code)` u `household.dart` i testiraj tekst, a dugme samo poziva share).
  - „Poništi“ → dijalog „Poništiti pozivnicu?“ / „Kod više neće moći da se iskoristi.“ / „Otkaži“ / „Poništi“ → posle potvrde pozivnica nestaje, SnackBar „Pozivnica je poništena.“
  - Offline → „Za ovo je potrebna internet veza.“; lista nije menjana.
  - Široko (1200×800) i tekst 2× na telefonu (390×844): kod i dugmad vidljivi, bez `overflow` grešaka.

**Checkpoint**: US1 radi i demonstrira se samostalno.

---

## Phase 4: User Story 2 — Pridruživanje kodom (P1)

**Cilj**: korisnik se pridružuje i vidi zajedničke podatke bez ponovne prijave. **Nezavisni test**: važeći kod → novo aktivno domaćinstvo, zajednički red u Nabavci posle sinhronizacije.

- [ ] T016 [US2] `lib/features/household/join_household_screen.dart` + ruta `/profile/household/join` + dugme „Pridruži se kodom“ na ekranu Domaćinstvo; testovi `test/features/household/join_household_screen_test.dart`.
  - Polje sa oznakom „Unesi kod od 8 znakova“; objašnjenje iz spec (FR-009) iznad dugmeta.
  - „Pridruži se“ onemogućeno dok `normalizeInviteCode(tekst).length != 8` (US2-7) i dok zahtev traje (Review Focus 4: dupli dodir → jedan `redeem`).
  - Nalepljen `' abcd-efgh\n'` za važeći kod → uspeh (US2-2, Review Focus 3).
  - Uspeh → povratak na Domaćinstvo, SnackBar „Sada si član domaćinstva „{naziv}“.“, Profil pokazuje novi naziv; posle `pump` sinhronizacije red zajedničke nabavke je vidljiv u Nabavci (pumpTavli tok, SC-001/SC-004).
  - Nevažeći kod → „Kod nije važeći ili je istekao.“, aktivno domaćinstvo isto; šesti pokušaj posle 5 neuspeha → „Previše pokušaja. Pokušaj ponovo za 10 minuta.“; offline → poruka o mreži, tekst ostaje u polju.
  - Tekst 2× na telefonu: objašnjenje i dugme dostupni (skrol, bez overflow-a).

**Checkpoint**: US1 + US2 = celo deljenje; MVP spreman za demonstraciju.

---

## Phase 5: User Story 3 — Članovi i uklanjanje (P2)

**Cilj**: svi vide s kim dele podatke; vlasnik uklanja člana. **Nezavisni test**: dva člana vide oba imena; uklonjeni posle osvežavanja ima lično domaćinstvo bez zajedničkih podataka.

- [ ] T017 [US3] Lista članova u `household_screen.dart` + `lib/features/household/member_tile.dart`; testovi u `household_screen_test.dart`.
  - Na otvaranje ekrana i na povlačenje nadole (`RefreshIndicator`): `refreshAccount()` + `reloadMembers()`; prikaz uvek iz `householdMembersProvider`.
  - Red: ime ili „Član bez imena“, „Vlasnik“/„Član“, „Ti“ na sopstvenom redu; nigde imejl (test: `find.textContaining('@')` → nema).
  - Neuspelo osvežavanje → poslednja lista + „Prikazano je poslednje poznato stanje.“ (US3-5).
  - Vlasnik: meni na tuđem redu → „Ukloni iz domaćinstva“ → dijalog „Ukloniti {ime} iz domaćinstva?“ / „Više neće videti podatke ovog domaćinstva.“ → član nestaje, „Član je uklonjen.“; član nema meni (US3-6); vlasnik nema meni na sopstvenom redu.
  - US3-4 (uklonjeni korisnik): test na drugom nalogu u istom `FakeBackend` — posle `refreshAccount` aktivno lično domaćinstvo, zajednički redovi nisu u lokalnoj bazi.
  - Semantika: svaki red ima čitljivu oznaku (ime + uloga + „Ti“) za čitač ekrana.

---

## Phase 6: User Story 4 — Napuštanje i prenos vlasništva (P2)

**Cilj**: izlaz iz domaćinstva i predaja vlasništva. **Nezavisni test**: član napusti i vidi lične podatke; prenos menja uloge kod oba.

- [ ] T018 [US4] Radnje u `household_screen.dart` i `member_tile.dart`; testovi u `household_screen_test.dart`.
  - Član: „Napusti domaćinstvo“ → dijalog „Napustiti domaćinstvo?“ / „Vratićeš se u svoje domaćinstvo i više nećeš videti ove podatke.“ → aktivno lično, „Domaćinstvo je napušteno.“, zajednički redovi obrisani lokalno.
  - Vlasnik sa drugim članovima: umesto dugmeta tekst „Pre napuštanja prenesi vlasništvo drugom članu.“ (US4-2); vlasnik jedinog domaćinstva bez drugih članova: ni napuštanje ni prenos (US4-4).
  - Vlasnik: meni člana → „Prenesi vlasništvo“ → „Preneti vlasništvo na {ime}?“ / „Ti postaješ član i više ne možeš da pozivaš ni uklanjaš članove.“ → uloge zamenjene, „Vlasništvo je preneto.“, „Pozovi člana“ nestaje.
  - Server odbija (član je u međuvremenu otišao) → „Taj korisnik više nije član domaćinstva.“ i lista osvežena (US4-5).

---

## Phase 7: User Story 5 — Prebacivanje između domaćinstava (P3)

**Cilj**: korisnik sa više članstava bira aktivno. **Nezavisni test**: izbor ličnog ostaje posle ponovnog pokretanja.

- [ ] T019 [US5] Odeljak „Aktivno domaćinstvo“ u `household_screen.dart`; testovi u `household_screen_test.dart`.
  - Prikazuje se samo uz ≥ 2 članstva (`householdMembershipsProvider`); izbor kao `RadioGroup` + `RadioListTile` (obrazac iz `lib/features/settings/appearance_screen.dart`) + „Prebaci“ → `selectActive` → podaci izabranog domaćinstva u Nabavci posle sinhronizacije.
  - Ponovno pokretanje (`pumpTavli` sa istom bazom) → izabrano domaćinstvo ostaje (US5-3).
  - Izabrano domaćinstvo uklonjeno na serveru → posle osvežavanja aktivno poslednje pridruženo (US5-4).
  - Offline → poruka o mreži, izbor nepromenjen.

---

## Phase 8: Polish & Cross-Cutting

- [ ] T020 [P] Ažuriraj `docs/product-design.md` §9 (deljenje domaćinstva je isporučeno kao 034; realtime ostaje 009) i `docs/roadmap.md` ako navodi 008 — samo činjenice, bez menjanja istorije starih specifikacija.
- [ ] T021 Završna provera: `scripts/check.sh`; ceo `flutter test` (broj testova veći od 932, 0 padova); `supabase db reset && supabase test db`; `flutter build macos --debug`; ručni [quickstart.md](quickstart.md) koraci 1–10 na lokalnom Supabase-u; rezultate (komande i izlaz) zapiši u opis PR-a. Pre PR-a: `/code-review` nad granom.

---

## Dependencies & Execution Order

- T001 → Phase 2. U Phase 2: T002, T003, T004, T005 paralelno; T006 posle T003; T007 posle T003; T008 posle T003; T009 posle T007 i T008; T010 posle T006 i T009; T011 posle T010; T012 posle T004 i T006; T013 posle T011 i T012.
- US1 (T014–T015) i US2 (T016) posle T013; T016 koristi ekran iz T014.
- US3 (T017) posle T014; US4 (T018) posle T017 (meni člana); US5 (T019) posle T014.
- Polish posle svih priča.

## Parallel Example

```text
Phase 2, odmah posle T001:
  T002 (SQL + pgTAP) | T003 (domain/household.dart) | T004 (household_invite.dart) | T005 (invite remote)
Posle T014:
  T016 (join ekran) | T017 (članovi) | T019 (izbor domaćinstva) — različiti fajlovi osim household_screen.dart; spajati redom
```

## Implementation Strategy

1. **MVP** = Phase 1–4 (T001–T016): pozivanje + pridruživanje sa ispravnim preuzimanjem i osvežavanjem. Zaustavi se, pusti ceo suite i quickstart 1–4, pa PR.
2. Zatim US3 + US4 (T017–T018) u istom ili sledećem PR-u, pa US5 (T019).
3. Svaki zadatak je jedan commit; svaka faza se završava zelenim `flutter test` za pogođene fajlove.
