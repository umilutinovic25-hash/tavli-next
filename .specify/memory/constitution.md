<!--
Sync Impact Report
- Version change: 2.0.1 → 2.1.0 (MINOR: principle II allows shared reference
  data — the food catalog and allergen codes — to be readable by every
  `authenticated` user; no client role may write it; it changes only through
  migrations)
- Dependent docs updated: specs/036-food-catalog (plan, research R9)
- Templates requiring updates: none

Previous: 2.0.0 → 2.0.1 (PATCH: test gate split — affected tests run
  in the pre-commit hook, the full `flutter test` suite runs in CI before merge;
  `scripts/check.sh` is format + analyze only)
- Dependent docs updated: AGENTS.md, CLAUDE.md, README.md,
  docs/flutter-best-practices.md (§13, §17), .github/workflows/check.yml
- Templates requiring updates: none

Previous: 1.2.0 → 2.0.0 (MAJOR: principle II redefined — an account is
  mandatory and the server is the durable store; backend security rules added)
- Modified principles:
  - II. "Offline-First Local Data" → "II. Offline-First, Account-Backed Data"
    (sign-in required; all user data stored on Supabase under the account; drift
    is the offline cache with an outbox; RLS on every table; explicit GRANTs;
    tables never auto-exposed)
  - IV. Secrets Never Committed: covers Supabase URL/anon key (secrets.json),
    service-role key never in the app or repo, session tokens only in secure storage
  - V. Test-First: access rules (RLS) need database tests against local Supabase;
    Flutter tests fake the backend
- Modified sections: Platform & Technology Constraints (Supabase backend, EU
  region, local stack via `supabase start` on ports 5532x, migrations in
  `supabase/migrations/`)
- Dependent docs updated: AGENTS.md, CLAUDE.md, README.md, docs/architecture.md,
  docs/roadmap.md, docs/flutter-best-practices.md (§10, §12, §13),
  specs/006-account-login/spec.md, secrets.example.json, supabase/config.toml
  (auto_expose_new_tables = false)
- Templates requiring updates: none (plan template reads gates from this file)
- Follow-up TODOs: none
-->

# Tavli Constitution

Tavli is a Flutter app (Android, iOS, macOS) for recipes, meal planning,
pantry and shopping lists, with AI help that runs on free provider tiers. Using
the app requires an account; the user's data is stored on the server under that
account and cached on the device for offline use.

## Core Principles

### I. Serbian UI (NON-NEGOTIABLE)

All user-facing text — labels, buttons, messages, errors, empty states, AI output
shown to the user — MUST be in Serbian, Latin script (ćčđšž, never Cyrillic).
AI prompts MUST instruct the model to answer in Serbian (Latin). Code identifiers
are English; code comments may be Serbian (the existing codebase uses Serbian
comments) or English. Specs and agent docs may be written in English but every
spec MUST state the Serbian (Latin) copy for any new UI text it introduces.

**Rationale**: the app is built for a Serbian-speaking household; mixed-language
UI is a defect, not a style choice.

### II. Offline-First, Account-Backed Data

An account is REQUIRED to use the app: nothing except the intro and the sign-in
flow is reachable without a signed-in session. All user data (recipes, versions,
photos, pantry, shopping lists, meal plans, ratings, preferences, profile) is
stored durably on the server (Supabase, EU region) under the account — household
data under the household, personal data under the person. The local drift
(SQLite) database is the offline cache the UI reads from: every change is
written locally and to an outbox in one transaction, and the outbox is uploaded
when online; on sign-in the account's data is downloaded. The app MUST stay
fully usable offline for everything except sign-in, account deletion and AI.
Sign-out MUST NOT delete data; data is deleted only when the user deletes it or
deletes the account. Records use client-generated ids so retries never duplicate.

Server rules: every table in an exposed schema MUST have Row Level Security
enabled with policies limiting access to the owning person or to members of the
owning household; new tables are NOT exposed automatically
(`auto_expose_new_tables = false`) — access for `authenticated` is granted
explicitly per table, and `anon` gets no table access. Storage buckets are
private with the same rules. Schema changes go through migrations in
`supabase/migrations/`; drift schema changes MUST bump `schemaVersion` and ship
a migration.

Exception for shared reference data: tables that hold no personal data and are
the same for every account (the shared food catalog — `foods`, `food_aliases`,
`food_conversions`, `food_allergens` rows with `household_id is null` — and the
`allergens` code list) MAY be readable by every `authenticated` user. No client
role may insert, update or delete such rows; they change only through
migrations in `supabase/migrations/`, and RLS is still enabled on these tables.

**Rationale**: the user's data must survive a lost device and follow the user to
any device, while free AI tiers and connectivity stay unreliable — so the app
works offline and the server is the durable copy, protected per row.

### III. AI Only Through AIRouter

Every AI call MUST go through `AIRouter` (`lib/ai/ai_router.dart`) — via
`RecipeAI` or a similar feature-level façade — never by calling a provider or
`ChatClient` directly from UI or domain code. The router owns the vision/text
fallback chains, per-model cooldowns (persisted in drift), invalid-key and
missing-model handling, and the one-retry-on-bad-JSON rule. No feature may take
a hard dependency on a single provider or model; model names live only in
`ChainConfig`. Every AI response MUST be a JSON object parsed by a function that
throws `FormatException` on schema mismatch. AI failures MUST degrade gracefully
with a Serbian message (see `aiErrorText`), never a crash.

**Rationale**: free tiers hit rate limits constantly and model names change; resilience is the product.

### IV. Secrets Never Committed

API keys and backend credentials MUST NEVER appear in the repository, logs, test
fixtures, screenshots, or commit messages. User AI keys are stored in the
platform secure store (Keychain on iOS/macOS, Keystore on Android) via
`KeyStore`; the auth session (access/refresh tokens) is stored only in the same
secure store. Build-time values (built-in AI keys, Supabase URL and anon key)
come from a gitignored `secrets.json` passed with `--dart-define-from-file`;
`secrets.example.json` holds empty values only. The Supabase service-role key
MUST NEVER be in the app or the repository. Tests use `InMemoryKeyStore` and
fake backends with obviously fake values.

**Rationale**: the repo may become public; a leaked key burns a free quota or
exposes other people's data.

### V. Test-First for Domain and AI Parsing

Domain logic (`lib/domain/`), AI parsing (`fromAiJson`, prompt/JSON handling),
router behaviour and error mapping MUST be developed test-first: write the
failing test, then the code. AI is always faked in tests (fake `ChatClient` or
the `fake_adapter` Dio adapter) and the backend is faked in Flutter tests —
tests MUST NOT hit the network. Server access rules (RLS policies, grants,
storage policies) MUST have database tests run against the local Supabase stack
(`supabase test db`) with at least two test accounts. Widgets get widget tests
for key flows. `flutter analyze` MUST be clean and the tests affected by the
change (`scripts/test-changed.sh`, run by the pre-commit hook) MUST be green
before every commit; the full `flutter test` suite MUST be green in CI before
a pull request is merged.

**Rationale**: AI output is messy; parsers and fallback logic are where bugs hide.

### VI. Responsive by Default

Every screen MUST work on a phone and on a wide window (macOS, tablet). The
shell uses bottom navigation tabs below 720 px width and a `NavigationRail`
at 720 px and above (extended at ≥1000 px). New screens MUST NOT assume a
fixed width and SHOULD be checked at both sizes.

### VII. Small, Reviewable Commits

Each commit does one thing, builds, passes analyze and tests, and has a clear
message. Generated code (`*.g.dart`) is committed together with the source
change that caused it. No drive-by refactors mixed into feature commits.

### VIII. One Feature = One Spec = One Branch

Each feature starts with a Spec Kit spec in `specs/NNN-short-name/` on a branch
of the same name, and follows specify → clarify → plan → tasks → analyze →
implement. Scope changes update the spec first.

### IX. Flutter Best Practices & Agent Guardrails

Code MUST follow `docs/flutter-best-practices.md` (architecture layers, Riverpod
rules, async safety, error handling, accessibility, drift migrations, security,
testing). The strict lint set in `analysis_options.yaml` MUST NOT be loosened
without amending this constitution. AI agents MUST follow the guardrails in
`AGENTS.md`: no secrets, no skipped/disabled tests, no hand-edited generated
code, no unjustified dependencies, no schema change without migration and test,
changes scoped to the active spec, and confirmation before destructive git
operations.

**Rationale**: AI agents write most of the code; guardrails keep quality from drifting.

## Platform & Technology Constraints

- Flutter (Dart ≥ 3.13), Material 3, targets Android, iOS, macOS.
- State: Riverpod (`flutter_riverpod`); routing: `go_router` with a
  `StatefulShellRoute`; local cache: drift; HTTP: dio; keys and session:
  `flutter_secure_storage`.
- Backend: Supabase (Auth with email one-time code, Postgres with RLS, Storage),
  hosted project in the EU region. Local development uses the Supabase CLI stack
  started with `supabase start` in this repo (`supabase/config.toml`, ports
  5532x so it does not clash with other local Supabase projects); schema lives in
  `supabase/migrations/`, email templates in `supabase/templates/`.
- AI providers: Gemini, Groq, OpenRouter — free tiers only — through one
  OpenAI-compatible `/chat/completions` client.
- New dependencies require a one-line justification in the feature's `plan.md`.

## Development Workflow

1. Every new branch MUST be created from the latest `main`
   (`git fetch origin && git switch -c <branch> origin/main`) and named
   `NNN-feature-name` (Spec Kit numbering) or `chore/…` / `fix/…` / `docs/…`.
   Branches MUST NOT be stacked on other unmerged branches; nothing is committed
   directly to `main` — every change lands through a pull request. Git
   conventions (commit messages, rebasing, force-push rules) are in
   `docs/flutter-best-practices.md` §17.
2. `/speckit-specify` → `/speckit-clarify` → `/speckit-plan` → `/speckit-tasks`
   → `/speckit-analyze` → `/speckit-implement`.
3. Before each commit: `dart run build_runner build` (if drift tables changed),
   `dart format lib test`, then the pre-commit hook (`.githooks/pre-commit`:
   `scripts/check.sh` format check + analyze, `scripts/test-changed.sh`
   affected tests). CI runs the full test suite on every pull request.
4. A feature is done when its tasks are checked off, acceptance scenarios pass,
   UI text is Serbian, and it runs on macOS debug (`flutter build macos --debug`).

## Governance

This constitution overrides other conventions in the repo. `AGENTS.md` is the
operational guide and MUST stay consistent with it. Amendments are made by
editing this file with a Sync Impact Report, bumping the version (MAJOR: a
principle removed or redefined; MINOR: a principle or section added; PATCH:
wording), and updating dependent templates and docs in the same commit. Every
`plan.md` Constitution Check MUST evaluate principles I–IX; violations go in
its Complexity Tracking table with justification.

**Version**: 2.1.0 | **Ratified**: 2026-10-30 | **Last Amended**: 2026-11-11
