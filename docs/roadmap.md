# Tavli roadmap

Each phase below becomes one or more Spec Kit features (`specs/NNN-name/`).
Spec numbers are assigned when a feature is specified, in the order it is started.

Last updated: 2026-11-02.

## Product direction (2026-11-02)

Tavli centers on **weekly/monthly meal plans and their shopping**. Target
navigation is **Plan, Nabavka, Recepti, Ostava**, with profile/settings behind
the avatar. "Danas" is inside Plan. See [product design](product-design.md)
and [010](../specs/010-plan-and-shopping/spec.md).

Standalone recipe → ingredient review → shopping is also a first-class path,
with no plan required. Generate → review/replace/lock → save → confirm pantry → shop by week → cook
→ rate. This is the target, not a claim that the screens are implemented.
Historical specs retain their delivered acceptance criteria.

## Done (on `main`)

- **Phase 0 — project setup**: Flutter project for Android, iOS, macOS.
- **Phase 1 — foundation** (`specs/001-foundation-ai-router`): app shell with
  responsive tabs/rail, drift schema for all planned data, AI layer
  (OpenAI-compatible client, vision/text fallback chains, persisted cooldowns),
  `RecipeAI` (photo, dish name, refine), recipe domain model.
- **AI keys screen**: enter/check/delete Gemini, Groq, OpenRouter keys
  (Keychain/Keystore), compare chain models with the provider's model list,
  chain test that generates a sample recipe and shows the attempt log.
- **Built-in Tavli AI keys** (`specs/002-builtin-ai-keys`): local gitignored
  `secrets.json` via `--dart-define-from-file`; own key first, built-in second
  per model; cooldowns per key. Cloudflare proxy remains a later phase.
- **Phase 2 — recipe screens** (`specs/003-recipe-screens`): recipe list with
  search and detail (list–detail on wide windows); add from a photo, a dish
  name or manually with a preview before saving; AI chat edits with version
  history, undo and restore; delete.
- **AI keys list** (`specs/004-ai-keys-list`): one generic "API ključ" field
  (service detected from the key), any number of keys per service, list of
  added keys with check/delete; keys used in order with per-key cooldowns.
- **Hide built-in keys** (PR #4): the keys page never shows built-in keys;
  "Probaj AI" removed from the keys page.
- **Keep screen on while cooking** (`specs/007-keep-screen-on`): "Ne gasi ekran"
  toggle on the recipe screen, remembered in `AppSettings`.
- **Dev process**: Spec Kit, constitution, AGENTS.md, CLAUDE.md,
  `docs/flutter-best-practices.md`, strict lints, `scripts/check.sh`, git rules
  (branch from latest `main`, squash-merge, delete branch after merge).

## In review / specified

- **005 Themes & animations**: implemented and pushed on 005-themes-animations,
  awaiting merge/review. Light/dark palettes, appearance, animations and the
  add-only-the-difference demo; startup fixes preserve already-upgraded caches.
  The recipe-name-only demo is not a complete plan quantity ledger.
- **010 Plan & shopping**: specification, plan and tasks prepared; **not
  implemented**. Documentation starts from latest main; app implementation
  waits for 005 to land through main, without stacking feature branches.
- **006a account/server storage** and **007 keep screen on** are already on
  main. Preserve them as dependencies rather than listing them as unfinished.

## Next — implementation order

1. **010 Plan & shopping**: next product priority on the existing personal
   household. Deliver tested slices:
   - Plan-first shell/prototype, four tabs, profile avatar, phone/wide layouts.
   - Weekly and calendar-month AI plans; breakfast/lunch/dinner selection,
     editable servings, personal preferences and optional confirmed pantry.
     Preview before saving; progress and resumable in-session partial drafts.
   - Calendar review, replacement, locked/cooked flags, protection of past meals,
     approved recipe snapshots and today's cooking inside Plan.
   - Shopping per entry and per calendar week, including six-week months;
     whole-month views aggregate the same underlying weekly rows. Compatible
     units sum, repeated recipes count per occurrence, only the difference is
     reconciled, bought/manual rows remain.
   - Standalone saved/searched/imported/generated recipe shopping without a
     plan or forced library save; stable preparation identity distinguishes
     repeated adds from an explicit later preparation.
   - Pantry CRUD/expiry/search, supply allocated once, idempotent purchase-to-
     pantry transfer, personal preferences and optional ratings.
   - Add a saved recipe to Plan; readable cooking steps and existing wake lock.
     Saved planning/shopping/pantry remain offline-capable and account-synced.
   See [spec](../specs/010-plan-and-shopping/spec.md),
   [plan](../specs/010-plan-and-shopping/plan.md),
   [tasks](../specs/010-plan-and-shopping/tasks.md). Monthly planning and weekly
   shopping are release requirements, not an unspecified follow-up.
2. **008 Household invites & roles** (number retained): invite by link, code
   or QR (7-day expiry/revocation), join confirmation, Vlasnik/Član,
   leave/remove/transfer ownership. Share plans, recipes, shopping and pantry;
   keep taste profiles, ratings, AI keys and themes personal. Solo planning
   does not wait for invitations.
   **Delivered as [034](../specs/034-household-members/spec.md):** owner-only
   invite codes (8 characters, 7 days, 5 uses) with copy/share, join by code,
   member list (name and role, no email), remove, leave, transfer ownership,
   and choosing the active household when a user belongs to several. Still
   open: invite link and QR (need a domain and new dependencies), a preview of
   the household before joining, and an IP-based redeem limit.
3. **009 Realtime sharing** (number retained): household change notifications
   and simultaneous-edit conflict handling. Until then retain 006a record-level
   last-write-wins/delete-wins behavior; do not claim realtime or conflict-free
   multi-user stock allocation.
4. **Recipe media refinement**: distinct original recipe documents and actual
   dish photos, classification of old photos, storage/sync/version cleanup.
   010 must not present an unclassified scan as a confirmed dish photograph.
5. **Planning refinements**: household-level servings default (not in today's
   Account schema), richer taste/favorite feedback and pantry suggestions.
   Basic plan servings, preferences, ratings and expiry are already in 010.
6. **006b Apple/Google sign-in** after the Apple Developer account; email code
   sign-in remains available during planning development.
7. **AI models screen**: persisted ordering/enabling of fallback-chain models.
8. **AI key gateway** (`specs/037-ai-gateway`, done): Supabase edge function
   `ai-complete` instead of a Cloudflare Worker; account-verified requests,
   provider keys as server secrets, per-user limits; release builds carry no
   provider keys.
9. **Store release**: privacy/terms/domain, declarations/manifests, deletion
   page, review account, export, crash reporting and optional notifications.

Unspecified future features receive numbers when work starts. 008/009 retain
their existing roadmap reservations; 010 preserves those references. Every
new feature branch starts from current main.

## Decisions (account & household)

Proposal: <https://claude.ai/artifact/A9M8mfChMncTQW43DRVV6d>
Full plan with flows: <https://claude.ai/artifact/KLvzjyHrPn6HWjnDwFvF5z>

Decided (2026-10-30):

- Backend: Supabase (Auth, Postgres with RLS, Storage), EU region. Local
  development with `supabase start` in this repo (ports 5532x).
- Account mandatory; all user data on the server, drift as offline cache with an
  outbox; sign-out keeps data; deletion only by the user (item or account).
- Sign-in methods: email code (006a), Apple + Google (006b).
- A user can belong to several households; one is active at a time (latest
  joined by default, manual choice kept on the device) — 034.
- AI keys stay on the device on sign-out, deleted on account deletion.

Still open:

- Recipes shared by default with a "private" option (008).
- Whether members (not only the owner) can invite (008; 034 keeps owner-only).
- App domain (for invite links, sign-in emails and the privacy policy).

Prerequisites: Supabase account and EU project (006a), app domain and a custom
email sender (before release), Apple Developer account (006b).

## Planning decisions (2026-11-02)

- Plan and shopping are the primary value; today's cooking is inside the plan.
- Repeated recipes count per occurrence and servings. Approved snapshots keep
  later library edits from silently changing plan quantities.
- Monday–Sunday periods are clipped to a calendar month; six are supported.
- Bought stock and its pantry receipt are the same supply. Never credit them
  twice or independently reuse one pantry quantity in every week.
- Planning uses the creator's private profile and explicit plan requirements,
  without reading or sharing other members' private taste data.
- This documentation revision implements no UI, AI calls or schema changes.
