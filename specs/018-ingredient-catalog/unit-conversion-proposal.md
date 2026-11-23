# Food-specific quantity conversion proposal

**Status** — Conversion rules accepted by the team on 2026-11-23; persistence and consumer rollout remain implementation work. The examples use synthetic conversion factors.
**Owner** — Dev 1. Proposed reviewers are Dev 2 for the nutrition consumer
and Dev 4 for the pantry and shopping boundary.
**Scope** — D1-010 / FR-007, T014–T015,
[Trello #23](https://trello.com/c/wYOhwrwt).

## Existing behavior

`normalizeUnit` in [shopping_demand.dart](../../lib/domain/shopping_demand.dart)
uses the shared `canonicalUnit` vocabulary for unit spelling. It normalizes
physical units within their dimension and keeps other units in separate groups.
Kitchen measures are opt-in per demand source. `demandFor` uses the ingredient
name as its key today and stores demand in integer millionths of a base unit.

[FoodBaseUnit](../../lib/domain/food_matcher.dart) already defines `gram`,
`milliliter`, and `piece`. Those are the catalog values. Display continues to
use `g`, `ml`, and `kom`. A usable embedded link follows the
[ingredient identity contract](ingredient-model-proposal.md), including the
current name key and the food's visibility in the active household.

## Inputs and outcomes

The consumer supplies the original quantity and unit, the target base unit and,
for a food-specific conversion, the verified food identity and active household.
An approved plan uses a saved conversion snapshot containing the resulting
micros, base unit, approximation flag, and factor ids, values, sources,
revisions and scope. A later factor revision applies only to a new approval or
an explicit recalculation; it never silently changes an approved amount.
An explicit package selection also supplies the package identifier.

The proposed result is one of these outcomes.

- **Converted** carries the resulting integer micros, the target base unit,
  and an exact or approximate flag. When a factor is used, evidence identifies
  the factor, its source, revision and scope.
- **Needs review** preserves the original entry and identifies the reason,
  such as unknown quantity, unsupported unit, missing factor, conflicting
  evidence or an unverified package. Shopping keeps that amount in its
  original group and displays “Proveri količinu” when the requested conversion
  is necessary to combine it. Nutrition counts the entry as uncovered.

Food-specific factors are optional, positive and finite.

| Factor | Unit | Use |
| --- | --- | --- |
| Density | Grams per milliliter | Convert volume to mass and mass to volume for the same food and preparation state. |
| Piece weight | Grams per piece | Convert count to mass and mass to an equivalent count for the same food and defined piece. |
| Package amount | Net quantity with a physical unit or piece count | Convert an explicitly identified package to its contents. Several package sizes can exist for one food. |

Use exact unit ratios first for quantities already in the target dimension.
For a necessary food-specific factor, an applicable household override takes
precedence over reviewed shared evidence for the same food, preparation state
and factor. A missing override permits a shared fallback. Factors are immutable
revisions with an id, source, revision number and scope; shared revisions must
be reviewed before use. Conflicting applicable overrides leave the amount for
review and never fall back to the shared value. Package size comes from the
selected package, so a plain “pakovanje” with several possible sizes remains
unresolved. Resolution receives only the current revision for each factor
scope; historical revisions remain available to reproduce saved snapshots.
Apply the [017 measures proposal](../017-kitchen-unit-conversion/measure-contract-proposal.md)
when an eligible source uses a kitchen volume such as a cup or tablespoon.
Convert a volume to grams only with applicable density.

Shopping normalizes a linked ingredient to its catalog base unit before
summing compatible demand. Keep fractional piece equivalents during the
calculation. A basket package count is a separate consumer decision. Nutrition
can request grams directly. Count a line that used density, piece weight,
package size or an approximate kitchen volume as approximate and carry the
flag into the aggregate shown with “~”. Round new converted demand to integer
micros once, after portion scaling. Existing exact paths retain their current
rounding behavior. A missing conversion contributes neither zero nor an
invented equivalent.

## Acceptance examples

The factors in this table are fixture data for validating arithmetic. The
catalog still requires reviewed sources for actual foods and packages.

| Scenario | Expected result |
| --- | --- |
| Two linked eggs and 100 g of the same eggs, using 50 g per piece | For a catalog base of `piece`, display approximately 4 pieces and store 4,000,000 micros. A nutrition call asking for grams resolves the two inputs to 200 g altogether. |
| 1 kg and 500 g of the same food | 1,500 g, 1,500,000,000 micros, exact. |
| Two tablespoons plus one teaspoon of the same food on a source with kitchen measures enabled | Approximately 35 ml. A request for grams with no density leaves the amount for review. |
| One 250 ml cup of linked flour with a fixture density of 0.6 g/ml | 150 g, 150,000,000 micros, approximate. |
| One pinch of salt | Keep the original quantity and unit and show “Proveri količinu” when combining demand. No conversion to grams. |
| Two explicitly selected 400 g packages versus an unspecified pack | The explicit selection contributes approximately 800 g. The unspecified pack remains separate. |
| The same shared egg has a 50 g factor, and household A defines a 60 g override | Two pieces contribute approximately 120 g in A and 100 g in household B. Two conflicting applicable factors in A require review. |
| Approved demand already used a versioned 50 g factor, then a 60 g factor arrives | Existing approved demand and allocation preserve the prior conversion. The new factor applies on a new approval or explicit recalculation. |

## Ownership and rollout

Shared factors require a reviewed source and revision. Household factors are
scoped to the active household and need ownership, access and departure tests
before sync. A change in catalog values must preserve the original recipe
words, quantities, existing approved shopping allocations and pending outbox
writes. Reconciliation must account for one physical stock amount once when
older and newer representations coexist.

The team confirmed household precedence, reviewed shared fallback, versioned
source evidence, frozen approved snapshots, and review on conflicting evidence
on 2026-11-23. The [catalog rollout](data-model.md#rollout) places consumer
writes after the server and read-only catalog client. The domain resolver and
fixtures are being implemented first; persisted factor rows and consumer
integration must use the next coordinated Drift/server migration after the
currently open catalog migration PR, and must retain the mixed-client rollout
gate. This ordering avoids reusing the Drift schema version already claimed by
PR #137.
