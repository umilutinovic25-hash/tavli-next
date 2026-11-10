# 034 — Ugovori

## 1. Server: `public.household_member_list`

Migracija: `supabase/migrations/20261111130300_household_member_list.sql`.

```sql
create or replace function public.household_member_list(p_household_id uuid)
returns table (user_id uuid, display_name text, role text, joined_at timestamptz)
language plpgsql stable security definer set search_path = ''
```

| Uslov | Rezultat |
|---|---|
| `auth.uid()` je null | `raise 'not_authenticated'` (`42501`) |
| pozivalac nije član `p_household_id` (`private.is_member`) | `raise 'not_household_member'` (`42501`) |
| inače | svi članovi, `order by role = 'owner' desc, joined_at asc`; `display_name` iz `profiles` (može biti null) |

Grant: `revoke execute ... from public, anon; grant execute ... to authenticated;`. Funkcija ne vraća imejl ni druge kolone profila.

pgTAP `supabase/tests/14_household_member_list_test.sql` (tri naloga: vlasnik A, član B pridružen kodom, stranac C):

- A i B dobijaju po 2 reda sa tačnim imenima i ulogama; vlasnik je prvi.
- C dobija `not_household_member`.
- `anon` nema `execute`.
- Kolone rezultata su tačno `user_id, display_name, role, joined_at` (provera kroz `pg_get_function_result`).

## 2. Dart: `HouseholdMembershipRemote` (`lib/data/household_membership_repository.dart`)

```dart
abstract interface class HouseholdMembershipRemote {
  Future<void> removeMember(String householdId, String userId);
  Future<void> leave(String householdId);
  Future<void> transferOwnership(String householdId, String userId);
  /// Članovi domaćinstva sa imenima (rpc household_member_list).
  Future<List<HouseholdMember>> listMembers(String householdId);
}

class SupabaseHouseholdMembershipRemote implements HouseholdMembershipRemote { ... } // sadašnji _call/_classify
class HouseholdMembershipRepository {
  HouseholdMembershipRepository(this._remote);   // bio: (SupabaseClient)
  // iste tri metode + listMembers; baca MembershipFailure
}
```

Greške: postojeća hijerarhija `MembershipFailure` bez novih klasa (`listMembers` za ne-člana → `NotHouseholdMember`, pošto `_classify` već prvo gleda poruku).

## 3. Dart: `AccountApi` (`lib/account/account_api.dart`)

`fetch()` ostaje bez parametara. Upit za članstvo: `select('household_id, role, joined_at, households(name)').eq('user_id', uid).order('joined_at', ascending: false)` bez `limit`; `RemoteAccount.memberships` dobija sve redove, a postojeća polja prvo članstvo.

## 4. Dart: `AccountService` (`lib/account/account_service.dart`)

```dart
/// Uvek čita server; upisuje nalog i household_memberships; prazni kursore
/// kad se skup članstava promeni; briše lokalne podatke domaćinstava koja su
/// nestala. Baca AuthFailure (Offline, SessionRevoked, Unavailable).
Future<Account> refresh(AuthSession session);

/// Pamti ručni izbor (null = poslednje pridruženo); ne zove mrežu.
Future<void> setPreferredHousehold(String userId, String? householdId);

/// Upisuje članove iz [members] kao ceo skup za (userId, householdId).
Future<void> cacheMembers(String userId, String householdId, List<HouseholdMember> members, DateTime fetchedAt);

Stream<List<Membership>> watchMemberships(String userId);
Stream<List<HouseholdMember>> watchMembers(String userId, String householdId);
```

`wipeLocal` zadržava ponašanje; deljeni deo postaje privatni `_purgeHousehold(String householdId)`.

## 5. Dart: `AuthController` (`lib/account/auth_controller.dart`)

```dart
/// Osvežava nalog sa servera i, ako je uspelo, postavlja novi SignedIn.
/// Vraća false bez mreže (stanje ostaje). Ne baca.
Future<bool> refreshAccount();
```

`start()` posle `SignedIn` iz keša jednom poziva `refreshAccount()` bez čekanja (`unawaited`, uz razlog u komentaru).

## 6. Dart: `HouseholdActions` (`lib/features/household/household_actions.dart`)

Jedino mesto koje UI zove za radnje; svaka radnja vraća `HouseholdOutcome`, nikad ne baca.

```dart
sealed class HouseholdOutcome { const HouseholdOutcome(); }
class HouseholdDone extends HouseholdOutcome { const HouseholdDone(this.message); final String message; }
class HouseholdFailed extends HouseholdOutcome { const HouseholdFailed(this.message); final String message; }

class HouseholdActions {
  Future<(HouseholdOutcome, String? code)> createInvite();
  Future<HouseholdOutcome> revokeInvite(HouseholdInvite invite);
  Future<HouseholdOutcome> join(String rawCode);               // redeem → setPreferred → refresh
  Future<HouseholdOutcome> removeMember(HouseholdMember m);     // → refresh + reloadMembers
  Future<HouseholdOutcome> leave();                             // → refresh
  Future<HouseholdOutcome> transferOwnership(HouseholdMember m);// → refresh + reloadMembers
  Future<HouseholdOutcome> selectActive(String householdId);    // setPreferred → refresh
  Future<bool> reloadMembers();                                 // false = prikaz zastareo
  Future<List<HouseholdInvite>?> loadInvites();                 // null = nema mreže
}
```

## 7. Mapiranje grešaka → tekst (`lib/features/household/household_error_text.dart`)

| Greška | Tekst |
|---|---|
| `InviteOffline`, `MembershipOffline`, `Offline` | „Za ovo je potrebna internet veza.“ |
| `InviteUnusable` | „Kod nije važeći ili je istekao.“ |
| `InviteTooManyAttempts` | „Previše pokušaja. Pokušaj ponovo za 10 minuta.“ |
| `InviteForbidden`, `NotHouseholdOwner` | „Samo vlasnik može to da uradi.“ |
| `NotHouseholdMember` | „Taj korisnik više nije član domaćinstva.“ |
| `OwnerMustTransfer` | „Pre napuštanja prenesi vlasništvo drugom članu.“ |
| `MembershipUnauthorized`, `SessionRevoked` | postojeći tok opozvane sesije (`sessionExpired`), bez posebne poruke |
| sve ostalo | „Nešto nije uspelo. Pokušaj ponovo.“ |

## 8. Rute (`lib/app/router.dart`)

- `/profile/household` → `HouseholdScreen`
- `/profile/household/join` → `JoinHouseholdScreen`
