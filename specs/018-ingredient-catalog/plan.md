# Implementation plan: Shared ingredient catalog and matching

**Status**: scoped proposal; runtime implementation not started by this revision.
**Spec**: [requirements](spec.md) | **Lead/review**: Dev 1 / Dev 2 and Dev 3
**Baseline**: dev 207c94c; every implementing branch starts from then-current origin/dev.

## Existing boundaries and proposed files

- `lib/domain/`
- `lib/data/database.dart`
- `lib/data/recipe_repository.dart`
- `lib/sync/entities.dart`
- `lib/ai/prompts.dart`
- `lib/features/recipes/`
- `supabase/migrations/`

Items marked new/proposed/external do not exist at baseline. Verify exact existing
files and consumers before editing; new files remain in current feature/domain/
data/AI/account/sync layers. Shared providers and schema versions are coordinated.

## Contract and data plan

Proposed foods/aliases/units/household overrides; immutable UUID and readable slug. Shared reviewed catalog read-only to clients; household additions scoped by RLS. Recipe ingredients remain embedded with optional food_id and original text.

Producer dependencies: [017](../017-kitchen-unit-conversion/spec.md)

The [ingredient identity and lookup proposal](ingredient-model-proposal.md)
is available for consumer review. It is a draft, not an accepted contract or
evidence that T001 has been completed.

The [food-specific quantity conversion proposal](unit-conversion-proposal.md)
records the team's accepted T014–T015 conversion rules and synthetic quantity
fixtures. Factor persistence and consumer rollout remain gated on the coordinated
server/Drift migration sequence described in that contract.

Use [shared boundaries](../011-team-development/contracts/shared-boundaries.md)
and the [contract template](../../.specify/templates/contract-template.md).
Before implementation, record typed fields, validation, identity/units/CivilDate,
error/retry/undo, ownership, compatibility and producer/consumer fixtures. If data
changes, add data-model.md with current→target columns and a reviewed migration;
allocate drift version only after preceding schema merges. New SQL is additive
where possible, with RLS/grants and local two-account tests. Applied SQL is immutable.
If no schema change is needed, explicitly record that decision in the slice PR.

## Delivery slices

1. Resolve only blocking decisions; map each source requirement to existing code,
   identify work already present and record remaining effort. Never redo completed
   behavior simply because a source ticket is unassessed.
2. Merge the agreed contract/fixtures first; no consumer branch stacks on an
   unmerged producer. Independent research/tests may proceed in developers' existing
   checkouts, with one active writer per checkout; no automatic extra worktrees.
3. Implement one source task vertically through affected layers with test-first
   logic/parsing and ownership review. Keep phase boundaries in tasks.md.
4. Integrate consumers after producer merge, preserving offline/replay and previous
   UI/quantity behavior. Run relevant 012/013 gates and update real evidence.

## Constitution check (3.0.0)

| Gate | Required response before implementation |
| --- | --- |
| I | English docs; exact Serbian Latin UI/copy for changed screens |
| II | Preserve outbox/account scope; explicit personal/device/reference classification |
| III | Any AI through AIRouter and validated task contract; N/A documented if none |
| IV | No real secrets/logged private content; apply 012 trust-boundary controls |
| V | Test-first logic/parsing; local SQL/Edge tests when backend changes |
| VI | Phone/wide/text/motion/keyboard proof for UI; N/A for technical-only slice |
| VII | Reviewable task slices; generated files via generator only |
| VIII | This canonical spec, owned dev-based branch/task IDs, no stacking |
| IX | Existing paths/interfaces; justify dependencies and migration decisions |
| X | Named human reviewer, producer/consumer contract and schema coordinator |

These are design obligations, not executed pass results. Any violation blocks Ready
until resolved under governance. No dependency is added by this documentation;
implementer records each proposed package/service with a reason before adoption.

## Verification, rollout and risks

Use [testing 013](../013-testing-strategy/spec.md), its journey matrix, and
[security 012](../012-security-baseline/spec.md). Tests must prove the scenarios
in spec.md and source task outcomes using synthetic data/fake AI. Default Flutter
tests do not contact a network; explicit guarded integration uses local services.
No speculative hosted deployment or publication. Record old-client/snapshot
compatibility, pending-outbox migration, failure/undo and forward recovery for
state changes. No destructive reset as a migration. Platform/source/legal/retention
limits from open questions remain release gates. UI follows the design canvas and the
UI standard; do not invent layouts or move components into the package incidentally.
