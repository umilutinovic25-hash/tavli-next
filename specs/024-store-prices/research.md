# Store-price source and basket research

**Status:** Owner-approved source proposal, confirmed against the portal on
2026-11-23; implementation remains in progress. Source tasks: D1-017 and D1-018 / FR-001–002 in
[spec 024](spec.md). No store data, user basket or price history is added to
this repository.

## Public source observations

On 2026-11-15, the public open-data portal listed retail CSV resources for
[Delhaize](https://data.gov.rs/sr/datasets/cenovnici-proizvoda-prema-pravilniku-o-uslovima-sadrzaju-i-nacinu-objavljivanja-cenovnika-delhaize-serbia-doo-beograd/)
and [Europrom](https://data.gov.rs/sr/datasets/cenovnici-proizvoda-prema-pravilniku-o-uslovima-sadrzaju-i-nacinu-objavljivanja-cenovnika-europrom-doo/).
Both dataset descriptions state the Serbian Open Data License, require source
and retrieval-date attribution, and distinguish historical monthly snapshots
from the latest valid price lists. The descriptions also state that their
consolidated lists may show the highest applicable price where stores differ.
That is not a guaranteed price at a particular location.

The portal metadata describes semicolon-separated UTF-8 CSV and product,
barcode, unit, price and price-list-type fields. Metadata and resource URLs
can change; these observations are not evidence that every live file was
downloaded, complete, current or compatible on 2026-11-15. Source terms,
update schedules, coverage and acceptable processing limits still require
review before selection or integration.

An earlier exploratory check reported that the two
CSV endpoints returned data on 2026-11-13. Its sampled files contained both
historical and current-list rows. It also reported product names containing
package sizes that were not safely inferable from the observed unit-price
fields. These are historical sample observations, not claims about the current
contents of every retailer file.

## Source decision and current portal metadata — 2026-11-23

The project owner approved using the Delhaize Serbia and Europrom datasets
listed above. The portal currently identifies both as available under the
Serbian Open Data License, with country-level coverage, real-time update
frequency and source plus retrieval-date attribution requirements. Both
descriptions warn that a consolidated list can show the highest current price
when store prices differ. The application therefore presents a retailer and
published format estimate, never a particular branch's price. The importer is
operator-triggered; a recurring schedule and location-specific feed remain
outside this decision.

Sources: [Delhaize dataset](https://data.gov.rs/sr/datasets/cenovnici-proizvoda-prema-pravilniku-o-uslovima-sadrzaju-i-nacinu-objavljivanja-cenovnika-delhaize-serbia-doo-beograd/) and [Europrom dataset](https://data.gov.rs/sr/datasets/cenovnici-proizvoda-prema-pravilniku-o-uslovima-sadrzaju-i-nacinu-objavljivanja-cenovnika-europrom-doo/).

## Download verification — 2026-11-21

Both CSV resources listed by the public portal returned HTTP 200. A complete
strict semicolon-separated UTF-8 parse produced 15 columns per record in both
files. These counts describe the downloaded bytes for this observation.
The records dated 2026-11-21 all carry the `VAZECI_CENOVNIK` list type.

| Source | Current rows | Historical rows | Current formats |
| --- | ---: | ---: | --- |
| [Delhaize CSV](https://data.gov.rs/sr/datasets/r/aa0a4ab4-1dc8-49e2-abef-67612a2abcbb) | 27,473 | 84,051 | Maxi, Mega Maxi, Maxi Online, Shop and Go, Profi |
| [Europrom CSV](https://data.gov.rs/sr/datasets/r/7bcd8e5e-a89f-4dc8-9b7d-70ce27e31096) | 7,962 | 24,802 | Europrom |

The format header is `Naziv trgovca - formata` for Delhaize and
`Naziv trgovca – formata` for Europrom. Delhaize responded with
`application/octet-stream`. Europrom responded with `text/csv`. Both files
include a price-list date, ordinary price, price per unit of measure, promotion
price and promotion start/end dates. There is no dedicated net package size or
store ID column in either sampled CSV. The Delhaize ordinary and unit prices
are numerically equal in every current row, including rows labeled `kg` or
`lit`. A ratio between the two price columns therefore does not establish
package size or a conversion factor.

Checking current data by retailer format, barcode and date found 27,463 keys
in Delhaize. Nine repeat. One is an identical row, and eight differ in at
least one of unit, unit price or promotion fields while agreeing on ordinary
price. Europrom had 7,962 distinct keys. Keeping the format in the identity
preserves separate observations for Maxi and Maxi Online. Both datasets contain
historical `MESECNI_PRESEK` rows for 1 September, 1 October and 1 November
2026. The latest-list and historical dates need separate import paths.

The exact snapshots can be identified by SHA-256 even when the retailers
replace the content at the same URL.

- Delhaize, 16,268,024 bytes,
  `98cfe16513351848170204de83749e6c8970fb63df226d1eba9b3f003243b706`.
- Europrom, 4,613,513 bytes,
  `63547275f02f6a75d9cdda7f77e185e9037a556dd4682f35e25b86959031e0e2`.

### Initial import proposal for Trello #30

Start with current ordinary prices at the published retailer/format scope.
Record source, retrieval time, price-list date, file hash and original format
on import. Label the result as a published consolidated price. Require a
separate store-level source before showing a location-specific quote.
Keep product identity and net package size as reviewed mappings. Price
observations with unresolved mappings stay available for inspection while the
corresponding basket items count as uncovered.

For duplicate keys, collapse identical rows. Preserve distinct evidence
and flag conflicting fields for review. A stable ordinary price can be
retained as an observation if those values agree. A conflicted unit or
package basis prevents basket use until resolved. Promotions and historical
observations need separate acceptance before appearing in a basket estimate.
Replaying the same valid file must leave the same set of observations.

| Import case | Expected result |
| --- | --- |
| Same barcode and date under Maxi and Maxi Online | Two current format-scoped observations. |
| Identical regular row appears twice, then the same dataset is downloaded again | One observation for that key across both imports. |
| Same key has two ordinary prices | Mark the ordinary price conflicted and leave the item uncovered. |
| Same key has one ordinary price and conflicting promotional fields | Retain the ordinary observation. Keep the promotion unavailable for comparison. |
| Same barcode has a monthly snapshot and a current row | Keep the snapshot separate from the current observation. |
| A pack name contains a size but the product has no confirmed mapping | Preserve the row and count it as uncovered for basket comparison. |

Source selection and attribution are approved. Direct package-to-food mappings
still require human review and evidence. Unmapped products remain unpriced;
the two public files do not establish store-level prices. Monthly snapshots and
promotions remain excluded from the current comparison.

## Synthetic comparison evidence

The [fixture](fixtures/basket_comparison_test.dart.txt) holds four synthetic
test cases for basket comparison. It is stored as text because the
`basket_comparison.dart` module is still absent from team `dev`.

The synthetic cases cover full packages, missing or conflicting offers and
sharing a single pack across repeated lines. One hand-checkable example is
1,500 ml of milk in 1,000 ml packs at 120 RSD plus six eggs in a ten-pack at
250 RSD: `2 × 120 + 1 × 250 = 490 RSD`. A store with only the milk price has
a partial 200 RSD subtotal and an uncovered egg item; it is not a complete
basket comparison. Another test confirms two 400 ml needs share one 1,000 ml
pack. All prices, products and source URLs in the fixture are fictional.

For Trello #101, the four-item case adds 500 g of flour at 95 RSD per 1 kg
bag and 1 kg of rice without an offer. Whole-package costs give a partial
subtotal of `2 × 120 + 250 + 95 = 585 RSD`. The fixture checks coverage of
3 out of 4 items, identifies rice as the only missing price and marks the
basket incomplete. The eventual UI should show “Delimičan zbir: 585 RSD”,
“3 od 4 stavke” and “Pirinač — nema cene”.

The fixture is not run in this repository yet, because `dev` has no
`lib/domain/basket_comparison.dart`, and the repository does not execute
`.dart.txt` files. The arithmetic was checked by hand. When the comparison
module lands, copy the fixture to `test/domain/basket_comparison_test.dart`
and run `flutter test test/domain/basket_comparison_test.dart`; the module must
export the `BasketOffer`, `BasketLine` and `BasketUnit` types that the fixture
imports.

## Proposed price acceptance cases

Record each observation with retailer, explicit retailer or store scope, source
and observation time. Display scope and age together with the comparison. Use
store-specific prices only for their matching store. Label any retailer-wide
fallback and preserve its age so it cannot appear to be a fresh store quote.

| Scenario | Expected result |
| --- | --- |
| A needed item has no comparable price | Show coverage and label the subtotal partial. Exclude it from cheapest complete basket ranking. |
| The same demand is offered in different pack sizes | Compare the cost of enough whole packs for the requested amount and show the purchased quantities. |
| Import the same source observation twice | Reuse the existing observation and keep the same basket totals. |
| Refresh fails | Retain the last successful observation and its original time. Display that the refresh failed. |
| A store price and a retailer-wide price both exist | Retain both scopes and prefer the matching store observation for that store. |

These are acceptance cases for the eventual importer and comparison against the
team catalog. They are not results from the existing synthetic fixture.

## Decisions and checks still required

- Review allowed sources, license obligations, retailer coverage, ingestion
  frequency, source versions, store/location semantics and data retention.
- Specify package-size and barcode-to-food confirmation. Missing, ambiguous,
  expired or contradictory observations must remain visible as uncovered;
  a product's display name alone is not proof of a pack size or food identity.
- Keep household basket data private. Define bounded parsing, timeouts,
  redirects, source failures and stale-result disclosure before networking.
- Verify the partial subtotal, coverage and missing item in the team UI once
  implemented. Test same-source reimport without duplicate history, different
  package sizes, conflicting same-date offers, failed refresh and date
  boundaries. Recheck actual files and source terms before integration.

No implementation, source approval or D1-017/D1-018 completion is claimed.
