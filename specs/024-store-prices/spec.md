# Specification: Store price imports and basket estimates

**ID**: 024-store-prices | **Feature key**: PRICES
**Created**: 2026-11-14 | **Baseline**: dev 207c94c
**Status**: Source choice approved by project owner on 2026-11-23; implementation in progress.
**Lead**: Dev 1 | **Proposed independent reviewer**: Dev 3

## Scope and source

Implements the PRICES portion of the [accepted product plan](../../docs/product-plan.md).
Existing behavior is documented in [architecture](../../docs/architecture.md);
this spec does not claim the target is shipped. Preserve inherited 010 quantity,
snapshot, offline and account invariants. No new framework or folder reorganization.
Source tickets below retain original assignments/phases; the lead coordinates,
not reassigns them. No additional feature is authorized merely by a technical seam.

## Requirements and source traceability

- **FR-001**: Deliver **Import store price lists**. Source D1-017; Dev 1; phase 4. Completion must satisfy the behavior and evidence below, not only code presence.
- **FR-002**: Deliver **Compare basket prices by store**. Source D1-018; Dev 1; phase 4. Completion must satisfy the behavior and evidence below, not only code presence.

## Behavioral requirements

- **FR-101**: Ingest approved store price sources with bounded processing, provenance, retry and stale/unmapped states.
- **FR-102**: Compare basket estimates by consistent package/unit conversions; show covered items, missing prices and observation date.
- **FR-103**: Do not present partial/stale totals as guaranteed checkout prices or substitute unknown food mappings silently.

## User scenarios and acceptance

- **US1 / SC-001**: A basket with three priced items and one unknown displays partial coverage and the missing item, not a falsely complete cheapest total.
- **US2 / SC-002**: Repeated import of the same source version does not duplicate price history.

Include empty/error/offline/cancel/retry, repeated action and ownership transitions
where applicable. Use deterministic fixtures and observable state assertions;
security denials require allowed-case controls as well. Acceptance is unverified
until execution evidence is linked.

## Data and privacy

Price reference records carry retailer, product/food mapping, package unit, date, source and version. Ingestion is server-owned; household basket stays private.

## Exact UI copy carried forward

“Cena korpe”, “Procenjena cena”, “Nedostaje cena”.
Additional screen/error/consent copy must be finalized in Serbian Latin before
that UI task becomes Ready. English is used for engineering documents only.

## Dependencies and open decisions

Producer specs: [018](../018-ingredient-catalog/spec.md), [020](../020-catalog-shopping/spec.md)

- **Q1a — source choice and attribution**: Project owner approved the proposed Delhaize Serbia and Europrom public data.gov.rs files on 2026-11-23. The Serbian Open Data License requires source and retrieval-date attribution. Delhaize and Europrom list country-level coverage and state that a consolidated price may show the highest price across their stores. Import and display them as retailer/format price lists; never call them a local-store quote.
- **Q1b — freshness and operation**: Import is an authenticated, manually triggered server operation. No recurring schedule is enabled until an operator owns its cadence and failure alerting. Retain source URL, SHA-256, retrieved time, price-list date and format with each import.
- **Q1c — product and package mapping**: No source name or measure text is enough to infer a food identity or package size. A barcode becomes comparable only after a reviewed mapping records food ID, package quantity, compatible base unit, reviewer and direct evidence. Unmapped and conflicted rows stay out of estimates; those basket needs count as missing prices.
- **Q1d — exact store selection**: These two chosen files do not provide reliable location-specific prices, so no location selector or store-specific promise is included.

Unresolved questions block their dependent code, not independent research/tests.
Do not invent answers to linked proposals that were not provided. Before Ready,
record decision owner/date, precise typed contract and reviewed acceptance fixtures.
