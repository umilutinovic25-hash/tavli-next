# 034 — Research

Svaka odluka: šta, zašto, šta je odbačeno. Nalazi su iz koda na `main` (`0e152cc`).

## R1. Imena drugih članova

**Nalaz:** `profiles: own select` (20261030120500) dozvoljava čitanje samo sopstvenog profila; `household_members: members select` dozvoljava članovima da vide redove članstva.

**Odluka:** nova `security definer` funkcija `public.household_member_list(p_household_id uuid)` koja proverava `private.is_member(p_household_id)` i vraća samo `user_id, display_name, role, joined_at`.

**Odbačeno:** nova RLS politika „co-member select“ na `profiles` (otkriva imejl i sve buduće kolone profila; Hyrum — svaka nova kolona bi postala vidljiva članovima); view (teže je kontrolisati grant i kolone u Supabase-u).

## R2. Osvežavanje naloga posle promene članstva

**Nalaz:** `AccountService.loadOrFetch` vraća keširan red iz `accounts` i servera pita samo kad reda nema. PR #31 (sortiranje po `joined_at`) zato sam po sebi ne menja aktivno domaćinstvo na uređaju koji je već prijavljen.

**Odluka:** `AccountService.refresh(...)` uvek čita server, upisuje nalog i keš članstava, i vraća `AccountChange` (šta se promenilo). `AuthController.refreshAccount()` postavlja novi `SignedIn`, pa `accountScopeProvider` i `syncEngineProvider` prave novi scope. Poziva se posle svake radnje nad članstvom, pri otvaranju ekrana Domaćinstvo, na povlačenje nadole i jednom pri pokretanju aplikacije (greška mreže se ignoriše, keš ostaje).

**Odbačeno:** realtime pretplata na `household_members` (009, van opsega); periodično osvežavanje (nepotreban saobraćaj).

## R3. Preuzimanje podataka novog domaćinstva

**Nalaz:** `Downloader` ne filtrira po domaćinstvu — RLS vraća redove svih domaćinstava čiji je korisnik član. Kursori (`sync_cursors`) su po `(accountId, entity)`, a `accounts.initialDownloadDone/lastPullAt` po nalogu.

**Posledica:** posle pridruživanja redovi zajedničkog domaćinstva sa `updated_at` starijim od kursora se nikad ne preuzmu.

**Odluka:** kad se skup članstava promeni, `refresh` u istoj transakciji briše kursore naloga i postavlja `initialDownloadDone = false`. Sledeće preuzimanje je puno (traka „Preuzimam…“ već postoji) i idempotentno (upsert po id-ju).

**Odbačeno:** kursori po domaćinstvu (zahteva filter po `household_id` u svakom upitu i promenu šeme kursora za sve entitete — veći zahvat bez koristi, jer RLS već ograničava redove).

## R4. Podaci domaćinstva koje korisnik više ne vidi

**Nalaz:** posle napuštanja ili uklanjanja redovi tog domaćinstva ostaju u drift-u (tombstone-i ih ne pokrivaju, server ih ne briše). `wipeLocal` već ima listu brisanja po `householdId`.

**Odluka:** izdvojiti `_purgeHousehold(String householdId)` iz `wipeLocal` (ponašanje `wipeLocal` ostaje isto) i pozvati ga u `refresh` za svako domaćinstvo koje je nestalo iz članstava; u istoj transakciji obrisati outbox stavke naloga čiji red pripada tom domaćinstvu (server bi ih ionako odbio) i fotografije sa uređaja tih recepata.

**Bezbednost:** sprečava da uklonjeni član i dalje čita zajedničke podatke iz keša (Information disclosure).

## R5. Izbor aktivnog domaćinstva

**Odluka:** čista funkcija `pickActiveHousehold(List<Membership>, {String? preferredId})` u `lib/domain/household.dart`: vraća `preferredId` ako je među članstvima, inače članstvo sa najnovijim `joinedAt`. `AccountApi.fetch` vraća sva članstva (sortirana po `joined_at desc`), a izbor radi `AccountService`. Izbor korisnika se čuva u `accounts.preferred_household_id` (lokalno, nullable).

**Odbačeno:** čuvanje izbora na serveru (spec: samo uređaj; nije potrebno drugim uređajima).

## R6. Testabilnost članstva

**Nalaz:** `HouseholdInviteRepository` zavisi od interfejsa `HouseholdInviteRemote`; `HouseholdMembershipRepository` direktno od `SupabaseClient`, a widget testovi lažiraju backend kroz interfejse (`FakeBackend`).

**Odluka:** uvesti `HouseholdMembershipRemote` (isti obrazac kao pozivnice) sa `removeMember`, `leave`, `transferOwnership`, `listMembers`; `SupabaseHouseholdMembershipRemote` sadrži sadašnji kod; postojeći testovi repozitorijuma se prebacuju na Supabase remote bez promene provera. `FakeBackend` dobija `FakeHouseholdServer` sa članstvima, pozivnicama i imenima domaćinstava.

## R7. Offline prikaz (UI čita iz drift-a)

**Odluka:** dve keš tabele bez outbox-a, jer ih menja samo server: `household_memberships` (domaćinstva korisnika, za izbor aktivnog) i `household_member_cache` (članovi domaćinstava sa imenima). Pune se u `refresh`/učitavanju članova; UI ih čita kao stream. Radnje nad članstvom idu direktno na server (kao brisanje naloga), jer zahtevaju mrežu (FR-015).

**Odbačeno:** čitanje članova direktno sa mreže u widgetu (krši AGENTS.md: UI čita iz drift-a).

## R8. Deljenje i kopiranje

**Odluka:** `share_plus` je već u `pubspec.yaml` — bez nove zavisnosti. Kopiranje kroz `Clipboard.setData` (Flutter SDK).

**Odbačeno:** QR (`qr_flutter`, `mobile_scanner`) — van opsega po specifikaciji.

## R9. Množina i datum

**Nalaz:** u `lib/` nema pomoćne funkcije za množinu. Datum „d.m.gggg.“ postoji kao `pantryDate` u `lib/features/pantry/pantry_item_tile.dart` (lokalno vreme, bez vodećih nula).

**Odluka:** `usesLeftText(int n)` u `lib/domain/household.dart` (1 → „upotreba“; 2–4 → „upotrebe“; ostalo → „upotreba“, uz pravilo 11–14 → „upotreba“); datum kroz novu `inviteDate(DateTime)` u `lib/domain/household.dart` sa istim formatom kao `pantryDate` (uvoz iz `features/pantry` u drugu funkciju bi vezao funkcije; premeštanje `pantryDate` je van opsega).

## R10. Threat model (STRIDE, sažeto)

| Granica | Pretnja | Mera |
|---|---|---|
| `household_member_list` | Information disclosure: imejl ili članovi tuđeg domaćinstva | provera članstva u funkciji; vraća samo 4 kolone; pgTAP sa tri naloga (vlasnik, član, stranac) |
| Radnje nad članstvom | Elevation: član uklanja/poziva | postojeće provere `not_owner` na serveru; UI samo skriva; widget test da odbijanje servera daje poruku |
| Keš na uređaju | Disclosure posle uklanjanja | R4 purge pri `refresh` |
| Outbox | Tampering/zaglavljeno slanje u tuđe domaćinstvo | R4 brisanje outbox stavki tog domaćinstva |
| Kod pozivnice | Enumeracija | van opsega (odluka korisnika: IP limit, dužina koda); kod se ne loguje |
| Deljena poruka | Disclosure | sadrži samo kod i uputstvo, bez imena i imejla |
