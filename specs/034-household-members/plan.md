# Implementation Plan: Domaćinstvo — pozivanje, pridruživanje i članovi

**Branch**: `034-household-members` (from latest `main`) | **Date**: 2026-11-10 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/034-household-members/spec.md`

**Prateći dokumenti**: [research.md](research.md) · [data-model.md](data-model.md) · [contracts/household-api.md](contracts/household-api.md) · [quickstart.md](quickstart.md)

## Summary

Ekrani Domaćinstvo i Pridruži se kodom, nadograđeni na postojeće repozitorijume pozivnica i članstva. Dodaje se ono bez čega ekrani ne mogu da rade ispravno: serverska funkcija `household_member_list` (samo ime i uloga, bez imejla), osvežavanje naloga sa servera posle svake promene članstva (`AccountService.refresh`), puno ponovno preuzimanje kad se skup članstava promeni (kursori su po nalogu, a ne po domaćinstvu), brisanje lokalnih podataka domaćinstva iz kog je korisnik izašao, keš članova u drift-u za prikaz bez mreže i ručni izbor aktivnog domaćinstva.

**Zavisnost:** PR #31 (sortiranje članstva po `joined_at`) mora biti spojen pre početka implementacije; ova grana se tada rebase-uje na novi `main`.

## Technical Context

**Language/Version**: Dart ≥ 3.13 (Flutter 3.47.9 iz `~/.cache/tavli-flutter-sdk`), PL/pgSQL (Supabase Postgres)

**Primary Dependencies**: postojeće — `flutter_riverpod`, `go_router`, `drift`, `supabase`, `share_plus`. **Nema novih zavisnosti.**

**Storage**: Supabase Postgres (bez novih tabela, jedna nova funkcija); drift `schemaVersion` 15 → 16 (kolona `accounts.preferred_household_id`, tabele `household_memberships`, `household_member_cache`).

**Testing**: `flutter test` (domen test-first, repozitorijumi kroz lažni HTTP, widget testovi kroz `FakeBackend` + `test_app.dart`), `supabase test db` (pgTAP, tri naloga).

**Target Platform**: Android, iOS, macOS.

**Project Type**: mobilna/desktop Flutter aplikacija + Supabase.

**Performance Goals**: ekran Domaćinstvo se iscrtava iz keša odmah; osvežavanje je jedan RPC + jedan upit. Puno preuzimanje posle pridruživanja koristi postojeći `Downloader` (stranice po `pageSize`).

**Constraints**: radnje nad članstvom samo uz mrežu; prikaz radi bez mreže; nijedan poziv prema produkcijskom projektu iz testova ili skripti.

**Scale/Scope**: domaćinstvo do ~10 članova (bez paginacije liste članova; pozivnica ima najviše 5 upotreba).

## Global Constraints

- Sav novi tekst je srpska latinica i doslovno iz odeljka Tekstovi u spec.md (uz ispravljenu množinu: „Još 1 upotreba“ / „Još 2–4 upotrebe“ / „Još 5 upotreba“).
- Kod pozivnice: 8 znakova iz serverskog alfabeta `[2-9A-HJ-KM-NP-Z]`, prikaz 4 + 4, kopiranje/deljenje bez razmaka.
- Pozivnica važi 7 dana i ima najviše 5 upotreba (vrednosti dolaze sa servera, ne hardkoduju se u UI).
- Previše pokušaja = 5 neuspeha za 10 minuta (server, `P0429`).
- Imejl drugog člana se nigde ne prikazuje, ne kešira i ne vraća sa servera.
- UI čita iz drift-a; widgeti ne zovu Supabase; sve radnje idu kroz `HouseholdActions`.
- Responsive: telefon (< 720 px), rail (≥ 720 px), prošireni rail (≥ 1000 px), tekst 2×.
- Strogi lintovi; bez `// ignore:` bez razloga; `dart format lib test` pre commita; pre-commit hook bez `--no-verify`.
- Commitovi bez `Co-Authored-By`.

## Review Focus

Ulazi i stanja koje spec podrazumeva, a koje nijedan scenario prihvatanja ne pokriva direktno; svaki dobija test u zadatku koji poseduje kod (tasks.md):

1. **Pridruživanje domaćinstvu čiji su podaci stariji od kursora preuzimanja** → posle pridruživanja svi zajednički redovi su lokalno (test: `AccountService.refresh` prazni kursore i `initialDownloadDone`; integracioni test sa `FakeBackend` gde red ima `updated_at` pre kursora).
2. **Uklonjen ili otišao član ima zajedničke podatke u kešu** → posle `refresh` redovi tog domaćinstva, njihove fotografije i outbox stavke su obrisani, a lični podaci ostaju (test u `account_service_test.dart`).
3. **Nalepljen kod sa razmacima, prelomom reda, crticom ili malim slovima** (`" abcd-efgh\n"`) → prihvata se kao `ABCDEFGH`; dugme je omogućeno tek kad normalizovan kod ima 8 znakova (test domena + widget test).
4. **Dupli dodir na „Pridruži se“ / „Pozovi člana“ dok zahtev traje** → samo jedan poziv serveru, dugme onemogućeno uz indikator (widget test sa brojanjem poziva u lažnom serveru).
5. **Ručno izabrano domaćinstvo više nije dostupno** (uklonjen dok je bio offline) → posle `refresh` aktivno je poslednje pridruženo, `preferred_household_id` je null (test domena `pickActiveHousehold` + test servisa).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.* — **Prolazi** (pre i posle dizajna), uz jedno opravdanje u Complexity Tracking.

| Princip | Ocena |
|---|---|
| I. Srpski UI | ✅ Svi tekstovi navedeni u spec.md; greške kroz `householdErrorText`. |
| II. Offline-first, nalog | ⚠️ Prikaz radi offline iz drift-a; radnje nad članstvom i pozivnicama traže mrežu (kao brisanje naloga) — opravdano niže. Nove tabele su keš bez outbox-a jer ih menja samo server. Nova serverska funkcija je `security definer` sa proverom članstva; grant samo `authenticated`. Drift 15 → 16 sa migracijom i testom. |
| III. AI kroz AIRouter | ✅ N/A — nema AI poziva. |
| IV. Tajne | ✅ Nema ključeva; deljena poruka sadrži samo kod; kod se ne loguje. |
| V. Test-first | ✅ Domen (`household.dart`, `normalizeInviteCode`) test-first; `refresh`, purge i izbor domaćinstva test-first; pgTAP sa tri naloga; widget testovi za ključne tokove. |
| VI. Responsive | ✅ Provera na telefonu, rail i tekst 2× (widget testovi sa `MediaQuery` veličinama, kao postojeći). |
| VII. Mali commitovi | ✅ Jedan zadatak = jedan commit (tasks.md). |
| VIII. Jedna funkcija = spec = grana | ✅ `034-household-members`. |
| IX. Smernice | ✅ Bez nove zavisnosti; generisani `database.g.dart` se commituje sa izvorom; promena konstruktora `HouseholdMembershipRepository` je u opsegu (uvođenje interfejsa za testove). |

## Project Structure

### Documentation (this feature)

```text
specs/034-household-members/
├── spec.md
├── plan.md              # ovaj fajl
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/household-api.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
supabase/
├── migrations/20261111130300_household_member_list.sql     # nova funkcija
└── tests/14_household_member_list_test.sql                 # pgTAP, 3 naloga

lib/
├── domain/
│   ├── household.dart              # NOVO: Membership, HouseholdMember, pickActiveHousehold,
│   │                               #       formatInviteCode, usesLeftText, inviteDate
│   └── household_invite.dart       # normalizeInviteCode (razmaci/crtice), maxUses, usesLeft
├── data/
│   ├── database.dart               # v16: accounts.preferredHouseholdId, 2 keš tabele, migracija
│   ├── household_invite_repository.dart      # _fromRow čita max_uses
│   └── household_membership_repository.dart  # HouseholdMembershipRemote + listMembers
├── account/
│   ├── account_api.dart            # RemoteAccount.memberships
│   ├── account_service.dart        # refresh, setPreferredHousehold, cacheMembers, watch*, _purgeHousehold
│   └── auth_controller.dart        # refreshAccount, osvežavanje pri pokretanju
├── providers.dart                  # repozitorijumi, householdActionsProvider, stream provajderi
├── app/router.dart                 # /profile/household, /profile/household/join
└── features/
    ├── settings/profile_screen.dart          # stavka „Domaćinstvo“
    └── household/                            # NOVO
        ├── household_screen.dart             # zaglavlje, izbor aktivnog, članovi, radnje
        ├── member_tile.dart                  # red člana + meni vlasnika
        ├── invites_section.dart              # „Pozovi člana“, aktivne pozivnice, poništi
        ├── invite_code_sheet.dart            # prikaz koda, kopiraj, podeli
        ├── join_household_screen.dart        # unos koda + objašnjenje
        ├── household_actions.dart            # HouseholdActions, HouseholdOutcome
        └── household_error_text.dart         # greška → tekst

test/
├── domain/household_test.dart, household_invite_test.dart
├── data/household_membership_repository_test.dart, household_invite_repository_test.dart, migration_test.dart
├── account/account_service_test.dart, auth_controller_test.dart (postojeći fajlovi, novi slučajevi)
├── features/household/household_screen_test.dart, join_household_screen_test.dart, household_error_text_test.dart
└── helpers/fake_backend.dart       # FakeHouseholdServer: članstva, pozivnice, imena, brojanje poziva
```

**Structure Decision**: nova funkcija u `lib/features/household/` (isti obrazac kao `features/pantry`, `features/planning`); domen i podaci u postojećim slojevima. Nijedan widget ne zavisi od Supabase-a.

## Redosled implementacije (detalji u tasks.md)

1. Server: migracija + pgTAP (nezavisno od klijenta).
2. Domen test-first: `household.dart`, izmene `household_invite.dart`.
3. Podaci: interfejs članstva + `listMembers`; `max_uses`; drift v16 + migracioni test.
4. Nalog: `AccountApi.memberships` → `AccountService.refresh` (kursori, purge, preferred) → `AuthController.refreshAccount`.
5. `FakeBackend` sa više članstava; `HouseholdActions` + mapiranje grešaka.
6. UI po prioritetu priča: P1 pozivanje → P1 pridruživanje → P2 članovi i uklanjanje → P2 napuštanje i prenos → P3 izbor aktivnog.
7. Završno: `scripts/check.sh`, ceo `flutter test`, `supabase test db`, `flutter build macos --debug`, quickstart ručno.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Princip II: radnje nad članstvom i pozivnicama ne rade offline | Server je jedini koji može da proveri vlasništvo, napravi kod i potroši upotrebu; offline red bi omogućio radnje koje server kasnije odbije posle što ih je korisnik video kao gotove | Outbox za RPC radnje: korisnik bi „pridružio“ domaćinstvo bez provere koda i video tuđe podatke tek kasnije ili nikad; prenos vlasništva bi mogao da se sudari sa radnjom drugog vlasnikovog uređaja |
| Keš tabele bez outbox-a | Podatke menja samo server (RPC); lokalno se samo prikazuju | Sinhronizovani entiteti bi zahtevali RLS upis za članove i otvorili mogućnost lokalne izmene uloga |
