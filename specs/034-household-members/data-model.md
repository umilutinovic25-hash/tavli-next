# 034 — Data model

## Server (Postgres)

Bez novih tabela. Nova funkcija u migraciji `supabase/migrations/20261111130300_household_member_list.sql` — ugovor u [contracts/household-api.md](contracts/household-api.md).

Postojeće (ne menja se): `households(id, name)`, `household_members(household_id, user_id, role ∈ {owner, member}, joined_at)`, `household_invites(id, household_id, code, created_at, expires_at, max_uses=5, uses, revoked_at)`, `profiles(id, email, display_name)`.

## Drift (lokalni keš) — `schemaVersion` 15 → 16

### `accounts` (izmena)

| Kolona | Tip | Napomena |
|---|---|---|
| `preferred_household_id` | text, nullable | ručni izbor aktivnog domaćinstva (FR-017); null = poslednje pridruženo |

### `household_memberships` (nova) — domaćinstva korisnika

| Kolona | Tip | Napomena |
|---|---|---|
| `account_id` | text | korisnik ovog uređaja |
| `household_id` | text | |
| `household_name` | text | |
| `role` | text | `owner` / `member` |
| `joined_at` | datetime | |

PK `(account_id, household_id)`. Zamenjuje se ceo skup za nalog pri svakom uspešnom `refresh`.

### `household_member_cache` (nova) — članovi domaćinstva

| Kolona | Tip | Napomena |
|---|---|---|
| `account_id` | text | čiji je keš |
| `household_id` | text | |
| `user_id` | text | |
| `display_name` | text, nullable | null → „Član bez imena“ |
| `role` | text | |
| `joined_at` | datetime | |
| `fetched_at` | datetime | vreme poslednjeg uspešnog čitanja sa servera |

PK `(account_id, household_id, user_id)`. Zamenjuje se ceo skup za `(account_id, household_id)` pri svakom uspešnom čitanju. Kad poslednji pokušaj čitanja ne uspe (npr. nema mreže), kontroler ekrana u memoriji pamti da je prikaz zastareo i ekran pokazuje „Prikazano je poslednje poznato stanje.“; tabela to ne čuva.

**Migracija 15 → 16:** `addColumn(accounts, preferredHouseholdId)`, `createTable(householdMemberships)`, `createTable(householdMemberCache)`. Test u `test/data/migration_test.dart`: v15 baza sa nalogom → v16, nalog ostaje, nova kolona je null, tabele postoje i prazne su.

Obe nove tabele nisu u registru sinhronizacije (`lib/sync/entities.dart`) i nemaju outbox: menja ih samo server.

## Domen (`lib/domain/household.dart`, čist Dart)

```dart
enum HouseholdRole { owner, member }        // već postoji u household_role.dart — koristi se postojeći

class Membership {                          // jedno članstvo korisnika
  final String householdId;
  final String householdName;
  final HouseholdRole role;
  final DateTime joinedAt;
}

class HouseholdMember {                     // član u listi
  final String userId;
  final String? displayName;
  final HouseholdRole role;
  final DateTime joinedAt;
}

Membership pickActiveHousehold(List<Membership> all, {String? preferredId});
String formatInviteCode(String code);       // 'ABCDEFGH' → 'ABCD EFGH'
String usesLeftText(int n);                 // 'Još 1 upotreba' / 'Još 3 upotrebe' / 'Još 5 upotreba'
String inviteDate(DateTime t);              // 'd.m.gggg.' u lokalnom vremenu
```

Izmene postojećeg domena:

- `normalizeInviteCode(String)` (`lib/domain/household_invite.dart`): uklanja sve razmake (uključujući prelome reda) i `-`, pa velika slova. Postojeći testovi i dalje važe.
- `HouseholdInvite`: novo polje `maxUses` (int, podrazumevano 5 kad ga red nema) i getter `usesLeft => maxUses - uses`; `isInviteUsable` dodatno traži `usesLeft > 0`.
- `RemoteAccount` (`lib/account/account_api.dart`): novo opciono polje `memberships: List<Membership>` (podrazumevano `const []`, sortirano po `joinedAt` opadajuće). Postojeća polja ostaju i opisuju poslednje pridruženo članstvo, da postojeći pozivaoci rade bez izmena.

## Prelazi stanja aktivnog domaćinstva

```
refresh() ──► server vraća memberships M
  aktivno = pickActiveHousehold(M, preferredId: accounts.preferred_household_id)
  nestala = (stari skup household_memberships) − M
  promenjen skup? ──► obriši sync_cursors naloga, initialDownloadDone = false
  za svako h ∈ nestala ──► _purgeHousehold(h) + obriši outbox stavke reda iz h
  preferred ∉ M ──► preferred_household_id = null
  upiši accounts (householdId/name/role = aktivno) i household_memberships = M
redeem(code) ──► preferred_household_id = vraćeni householdId, pa refresh()
leave(h) / removeMember / transferOwnership ──► refresh()
selectActive(h) ──► preferred_household_id = h, pa refresh()
```
