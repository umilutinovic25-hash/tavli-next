# Stream A — AI, search and recipe ingestion

Research date: 2026-11-09. Tavli runtime baseline: `1eca2c3d14fb5dd9b25a42958aa018c8d8dfbb94` from [anjahubac/tavli](https://github.com/anjahubac/tavli/tree/1eca2c3d14fb5dd9b25a42958aa018c8d8dfbb94). This is a source-backed implementation blueprint, not implemented functionality. Owned feature set: F001, F002, F003, F004, F005, F019, F020, F024, F025, F026, F030, F035, F048, F058, F089.

## Existing architecture and verified gaps

The inspection covered the constitution, AGENTS.md, product feature register, actual Dart models/repositories/AI/provider and preview code, and pinned upstream source files listed below. Existing layers should be extended rather than replaced.

* `lib/domain/recipe.dart:Recipe` contains ingredients, steps, source enum, image path and answeredBy; `RecipeSource` only has photo/ai/manual. There is no immutable source-document, author URL, original language, extraction evidence or dietary-compliance model. The existing ingredient quantity parser accepts numeric/string/fraction forms; new adapters need stricter finite/nonnegative/domain validation and must preserve ambiguous raw values rather than silently coercing them.
* `lib/data/recipe_repository.dart:RecipeRepository.create/update` already uses transactions and SyncedWriter. `update` snapshots the previous state, but `maxVersions=30` means history is not a durable archive of original imported text. `_all` filters household and orders descending createdAt; it must remain the source of account-scoped local reads.
* `lib/domain/recipe_format.dart:filterRecipes` only searches a normalized title substring. `normalizeForSearch` folds Serbian diacritics for lookup. `lib/features/recipes/recipe_providers.dart:RecipeSearch` stores a transient string, not a saved combined query. Keep this basic behavior when adding typed filters.
* `lib/domain/shopping_sync.dart:ingredientKey`, `lib/domain/shopping_demand.dart:demandFor/normalizeUnit`, and `lib/domain/supply_allocation.dart:allocateSupply` are the existing quantity authority. They distinguish dimensions, scale to micros and deduplicate physically identical purchase/receipt stock. Unknown quantities stay unknown; use them, do not introduce an LLM stock calculator. `Supply` does not contain expiry dates; expiry preference needs a deliberately added policy adapter.
* `lib/data/database.dart:PantryItems` has expiresAt and confirmedAt. `lib/data/pantry_repository.dart:receivePurchases` is a receive flow, not a complete expiry-aware inventory interface. `lib/data/meal_plan_repository.dart:confirmedPantryNames` only returns names; it is not proof of numerical availability.
* `lib/ai/meal_plan_ai.dart:MealPlanAI.propose` takes `library.take(maxLibraryInPrompt)` with `maxLibraryInPrompt=60`, then supplies only id/title pairs. In combination with newest-first repository order this can exclude older applicable recipes. `request.wishes` reaches `planOutlinePrompt` but **does not reach** `recipeSummariesPrompt(batch)`. Titles such as “pasta” cannot preserve “bez mleka” across stages. `parseOutline` validates requested slots and known IDs, while `parseSummaries` validates batch shape/servings/ingredients, not dietary compliance. `draftRecipeKey` is title-based; use opaque generation IDs for new dishes before allowing same-title variants under different constraints.
* `lib/ai/ai_router.dart:AIRouter.run/_attempt` tries models and credentials, with one parse retry; `lib/ai/chat_client.dart:OpenAICompatibleClient.complete/_send` adds a transient retry and per-model receive timeout. No total router deadline is present. A fallback chain can therefore consume the sum of multiple attempt timeouts; `PlanCancellation` is checked between `step` calls, not as transport cancellation during an attempt.
* `lib/ai/key_store.dart:BuiltInKeys.fromEnvironment` reads compile-time provider keys; `LayeredKeySource.credentialsFor` offers user keys then built-in keys. Secure storage protects user keys at rest, but compiled built-in credentials are still delivered to clients. No real key/secret file was accessed. Moving shared credentials server-side requires a documented evolution of constitution III/IV, preserving AIRouter as the orchestration entry.
* `lib/domain/meal_plan.dart:PlanRequest/PlanDraft` and `lib/data/meal_plan_repository.dart:approve/fingerprint` already support scoped slots, unsaved drafts, snapshots and stale/protected-plan checks. F089 should produce the same draft and go through the same approval transaction. `MealPlanEntries.isCooked` and `setCooked` are flags; planned date is not proof of actual cooking date.

## Shared contracts and foundation gates

The following gates are implementation prerequisites, not additional shipped features. Each new feature still gets one spec/branch and small verified steps. New models must be immutable pure Dart; widgets consume providers/repositories, and AI remains behind AIRouter. No migration or source change is made by this research.

### G-SYNC — extend current persistence

Every new user record uses a client UUID, explicit person/household scope, a repository transaction plus outbox, entity registry/upload/download mapping, drift schema bump/migration, new Supabase migration with RLS and explicit authenticated grants, and two-account local database tests. Use existing cache and writer conventions. Add indexes/FTS only after profiling real query needs; the initial bounded local scan supports offline use without a second database/search service. Version serialized contracts and tolerate absent newly optional fields. New RecipeSource values require readers/export/sync compatibility before rollout: old readers currently cannot recognize unknown enum values reliably, so retain legacy source and add optional metadata first, then version/negotiate a new enum if necessary.

### G-PROVENANCE — evidence follows the recipe revision

Proposed `RecipeProvenanceV1`: id, recipeId, immutable revisionId, sourceKind, submittedUrl?, fetchedUrl?, claimedCanonicalUrl?, author?, publisher?, sourceLanguage?, capturedAt, originalTextDigest, originalAssetRef?, extractorId/version, method (`jsonld`, `microdata`, `text`, `ocr`, `ai`, `manual`), declaredRights?, and confirmation state. `FieldEvidenceV1` links a stable recipe/ingredient/step field ID to page/character span or JSON pointer and original lexeme, plus state (`extracted`, `inferred`, `corrected`, `unresolved`). Do not treat an LLM confidence score as calibrated correctness.

Keep originals private and independently retained from the 30-version history. Saving an import retains the necessary original extracted text/evidence; retaining an entire PDF/photo is an explicit product choice with storage limits, not an accidental permanent upload. Unaccepted transient assets expire within a proposed 24 h TTL; accepted evidence obeys account/item deletion and private storage policies. Store declared source attribution without claiming that a source-code license licenses website recipes/photos. Unknown source rights must not be presented as a grant to redistribute; ordinary private import does not imply permission to publish a collection. Content hashes are dedup hints, not identity: same URL can change and different sources can contain the same recipe. Display suspected duplicate and allow link/update/new item deliberately; do not overwrite on URL match.

`ImportDraftV1` is not a persisted Recipe until confirmed. Include schemaVersion, importId/clientRequestId, candidate recipe, provenance, field evidence, completeness, issues and capability status. Stable field IDs allow correction/translation and source comparison. A missing quantity stays null plus the raw string; a serving range remains an issue, not a guessed integer. Schema mismatch throws FormatException for normal AIRouter retry, while explicit insufficient-evidence returns a typed non-success draft. Reuse `AiRecipePreview` and existing ingredient review; add source comparison and issue acknowledgement rather than a second save workflow. On Save, atomically create recipe and provenance/outbox; on Discard no recipe write. An operation ID guards duplicate share/import delivery independently of URL dedup.

### G-SERVER — authenticated fetch and shared-provider boundary

Proposed endpoints (versioned service contracts; transport/runtime selected during implementation): `POST /v1/import-drafts` for URL/text intake, bounded upload -> import job for PDF/OCR, `GET /v1/import-jobs/{id}` for own job, and `POST /v1/ai/complete` for a constrained router adapter. Verify authentication server-side, derive account/household authorization from verified session and membership rather than trusting supplied IDs, enforce request sizes, per-user/household quotas, bounded concurrency, idempotency and cancellation. A job ID is never authorization to read another user's result. Only a dedicated fetch worker has outbound URL access; it cannot reach database/control-plane/private metadata networks. The AI worker has provider allowlist egress and no arbitrary URL-fetch tool. A raw provider proxy must not accept arbitrary base URLs, privileged roles, tools, model names or headers from the client.

Required URL policy (tests before endpoint release):

1. Parse a canonical URL once using a strict library. Allow only HTTP(S), proposed ports 80/443, no userinfo, no fragment-as-authority trick, no file/data/ftp/gopher schemes or ambiguous numeric IP forms. Reject local host suffixes, zone identifiers, malformed IDNs and overlong URLs. Normalize IDNA and host trailing dot before policy checks.
2. Resolve all A/AAAA answers and reject any non-global destination, including loopback, private, link-local/metadata, CGNAT, multicast, unspecified, reserved and IPv4-mapped IPv6 variants. Reject mixed public/private answers. Validate address classes with maintained IP parsing, not a regex list. Pin the selected validated IP to the actual connection while preserving original Host/SNI and TLS verification; DNS precheck alone is insufficient against rebinding. Enforce equivalent IPv4/IPv6 egress deny rules at infrastructure layer; no ambient corporate/environment proxy bypass.
3. Disable automatic redirects. At most 3 hops; resolve, validate and pin every hop, including relative Location targets and cross-domain redirects. Never forward auth cookies or provider/session headers. Revalidate independent image, canonical, feed enclosure and secondary resource URLs; simplest initial importer fetches no image until requested. Canonical metadata is untrusted text, not a permission to fetch.
4. Proposed HTML limits: 5 MiB decompressed content, bounded compressed bytes, content-type/sniff checks, 10 s connect and 20 s total fetch wall time including DNS/redirects/body; stop streaming at cap. PDF has separate explicit 10 MiB/10-page caps and parser CPU/memory/time budget. XML external entities/DTD disabled. No JavaScript/headless browser, plugins or downloaded executables in initial fetch. Abort stalled/chunked/zip-bomb bodies, invalid encodings, repeated redirects and TLS errors. No bypass of access challenges; return a usable paste/photo alternative.
5. Strip scripts/active HTML; treat retrieved text as untrusted data. Delimit source and user wishes separately, no tools in extraction prompts, use schema/allowlisted fields and grounded source spans. A page saying “ignore instructions” cannot change system rules, trigger a fetch or create a recipe without confirmation. Never log full URLs with query credentials, request bodies, recipes, tokens or key values; operational metrics use opaque request IDs and error classes.

When the chosen hosted runtime cannot guarantee address pinning/egress isolation or enforce a true total timeout, **URL fetching is unavailable**, not an insecure DNS-check-only fallback. Expose capability to UI: „Uvoz sa linka trenutno nije dostupan. Nalepi tekst recepta.” Do not assume a Supabase Edge Function alone provides all those network controls; select a worker/runtime that can demonstrate them.

### G-AI — one router, bounded work and no client shared secret

Preserve `RecipeAI`/feature facade -> `AIRouter` as the only AI entry. Introduce an explicit transport/credential-reference abstraction so cloud routing uses opaque provider slots and server-held shared secrets, while optional BYOK mode can continue direct local secure-store calls without uploading user keys. Do not fake a cloud credential as an API key. Server and client policies must not each retry an entire chain independently: one layer owns each retry and reports normalized attempts to the other. The server enforces quotas even if clients are modified. Shared provider credentials are removed from release artifacts once migration passes; no real key rotation is part of this task.

Proposed configurable defaults: 45 s overall per router operation, 180 s per interactive plan session with partial draft checkpoints; use monotonic remaining duration, not wall-clock subtraction for timeout accounting. Clock injection still serves cooldown/date tests. Every credential lookup, cooldown access, parse retry, transient delay and HTTP attempt consumes the remaining budget; transport timeout is min(model limit, remaining). Carry cancellation to the underlying HTTP request, and stop all further retries immediately. A Dart Future.timeout alone does not cancel network requests. Distinguish timeout/cancel/rate limit/invalid output, preserve completed draft batches and let resume request only missing items. Provider capabilities are probed/validated rather than assuming configured model names stay available. Metrics never store personal content.

Regression gates: fake slow first provider cannot exceed total budget by falling back repeatedly; malformed JSON cannot reset timer; cancellation aborts in-flight request; invalid key cooldown remains per slot; one client retry plus one server retry cannot multiply into another whole fallback tree. Preserve safe Serbian error mapping and existing animation/reduced-motion behavior.

### G-RULES — dietary restrictions are code, wishes remain text

Introduce `PlanConstraintsV1` with confirmed excluded canonical ingredients/allergen taxonomy IDs, dietary preferences, max time, equipment needs, repetition policy, participants and policy revision; integrate participant/profile scope with stream B/D. Personal diet rules live under the person and only the explicitly relevant eaters' rules apply to that meal. Free-form wishes are helpful preference text, never the sole representation of a hard restriction. Unknown/ambiguous ingredient or compound product compliance is `unknown`, not safe. In strict mode reject/hold unknown compliance for review. Do not claim absence of cross-contamination from recipe text. No real dietary or personal records were inspected.

`ConstraintEvaluation` returns eligible/rejected/needsReview with stable reason codes and field evidence. Filter library candidates locally using complete ingredient/time facts **before** token budgeting. Feed normalized rules, request.wishes, selected portions and resolved meal contexts into both outline and summary stages, and into later recipe expansion/refine/translation where relevant. Replace title-key identity for new proposals with opaque draft IDs; include plan/request revision in resume validation. Validate every generated summary and expanded recipe against the same rules after parsing. An LLM statement “bez mleka” does not override a milk ingredient. Do not silently remove allergens as an automatic correction; show alternative draft or an unresolved slot.

Retrieval then ranking: query all local household recipes -> hard eligibility -> deterministic score with facts -> diverse candidate selection -> token/byte budget with compact typed facts (ID, ingredient IDs, time, serving base, compliance evidence). The maximum prompt payload is a transport budget, not “first 60 titles”. User-visible notice shows if candidates were capped; an older matching recipe must be retrievable regardless of insertion order. Titles never prove ingredient safety. Generated recipe expansion is rechecked before approval; immutable accepted snapshots remain the shopping authority.

### G-PLANNER — one local engine used with or without AI

Implement pure `CandidateSelector` and `RecipeScorer` shared by search, quick ingredients and plan generation. Keep score components separate: matched selected ingredients; quantitatively covered demand; eligible expiry use; duration; last actual cooked date; seasonality. Use dimension-aware amounts and bounded ratios/counts, not a raw comparison of grams to millilitres. Return `RecommendationEvidenceV1`, never ask AI to invent reasons. Unknown components are absent and coverage is disclosed. Proposed default rank is lexicographic hard eligibility -> unresolved count -> missing demand-group count -> expiry/selected-ingredient utility -> repetition/time preference -> stable recipe ID; weights/policy live in versioned configuration, not scattered prompts.

For F089, freeze local recipe/stock/history/rule snapshots and CivilDate today. Enumerate requested slots in canonical date/meal order; maintain protected entries and one physical-stock ledger across the plan. Use a bounded beam (proposed width 16, hard node cap 25,000; benchmark before finalizing) with stable branching/order and incremental existing allocation calculations. The node cap is deterministic; a separate wall-time/cancel interrupt may return a clearly partial result. No claim of global optimality. Search exhaustion yields unfilled slots/unsatisfied-rule reasons, never automatically relaxed dietary constraints. Never generate a new offline recipe; saved summaries can fill a plan but still need steps before guided cooking. PlanDraft and MealPlanRepository.approve remain integration points. Approval rechecks recipe/rule/stock versions as well as existing plan fingerprint, so a stale safe-looking draft cannot overwrite changed inputs.

## Implementation order and cross-stream integration

1. Foundation specs: G-SYNC compatibility, G-PROVENANCE, G-RULES and G-AI regressions. These are concrete vertical work items, not permission to refactor unrelated files.
2. F002 -> F003 and F004 -> F030/F058; add F005 after stream C's pantry confirmation/date semantics are reliable. F001 can proceed independently after G-SERVER and source metadata are safe.
3. F019 -> F020/F024; F035 consumes E/F047 cooking events, never invents cookedAt from plan date. F048 waits for a licensed regional source. F089 single-slot works after deterministic candidate rules; enrich it with each later scorer only after that feature passes its own checks.
4. F025/F026 remain later adapters over the same import contract. Browser/social/OCR/RSS capabilities degrade to unavailable or paste input, without promising vendor integration.

B owns plan calendar/participant constraints and approval semantics; C owns pantry lot confirmation, expiry/availability and physical stock; D owns household membership scopes; E owns actual cooking occurrence (F047); F owns schema.org portable adapter (F022), OCR review (F049), quality checks (F084) and tested-version state (F085). Share interface contracts and fixtures with those streams; do not create parallel models. Import provenance remains independent of “tested recipe” evidence. Dietary evaluation and quantity allocation must be shared across every plan mode, not duplicated in AI and offline implementations.

## Feature-by-feature vertical plan

The checks below are proposed implementation acceptance tests. They were not executed in this research delivery.


### F001 — Uvoz recepta sa URL-a (P1)

**Observed current state:** lib/features/recipes/add_recipe_sheet.dart offers existing photo/name/manual inputs; lib/features/recipes/ai_preview.dart:AiRecipePreview already reviews before save. lib/domain/recipe.dart:RecipeSource has only photo/ai/manual; Recipe has no URL/author/extraction provenance. lib/data/recipe_repository.dart:RecipeRepository.create is transactional with outbox.

**Contract/change:** ImportRequestV1(kind=url, input, clientRequestId) -> ImportDraftV1(recipe candidate, provenance, field evidence, warnings, completeness). Server fetch -> schema.org JSON-LD/microdata -> bounded text extraction -> opt-in AIRouter fallback -> existing preview -> RecipeRepository transaction. Keep author, original URL, final fetched URL and claimed canonical URL distinct; none authorizes another fetch.

**Dependencies:** G-SERVER, G-PROVENANCE, G-SYNC.

**Small sequential slices:**

1. Add pure adapter and synthetic HTML fixtures for single Recipe and @graph, returning unsaved drafts.

2. Add isolated server fetch policy and authenticated endpoint; reject unavailable capability.

3. Connect existing add/preview/save flow, source metadata and outbox migration; add fallback only after structured import works.


**Measurable acceptance:**

* Structured fixture imports with zero AI requests and zero recipe writes before confirmation.

* Multiple Recipe entities require explicit selection; absent quantities remain null with review flags.

* Discard produces zero recipe/outbox writes; retry with same accepted operation ID creates one recipe.

* All redirect/image/canonical-derived requests pass G-SERVER; private target makes zero outbound connections.


**Concrete verification:**

* Unit fixtures: JSON-LD object/list/@graph, microdata, malformed JSON, HowToSection, ranges and unknown yields.

* Fake DNS/HTTP tests: public->private redirect, DNS rebinding, mapped IPv6, oversized/chunked/decompression body and timeout.

* Widget save/discard/retry and local two-account RLS/outbox tests after implementation.


### F002 — Potvrđeni sinonimi sastojaka i jedinica (P1)

**Observed current state:** lib/domain/shopping_sync.dart:ingredientKey normalizes spelling; lib/domain/shopping_demand.dart:normalizeUnit and demandFor separate mass/volume/count, without household synonym records. lib/domain/supply_allocation.dart:allocateSupply requires equal keys and unit groups.

**Contract/change:** AliasV1(id, householdId, kind=ingredient|unit, normalizedAlias, canonicalId, confirmedBy, revision, retiredAt). Pure resolver used by search/demand/allocation; ingredients retain display spelling. Unit aliases map labels to an existing dimension and exact factor, never infer density. Suggestions require confirmation; changed aliases preview affected live demands and preserve approved historical snapshots.

**Dependencies:** G-SYNC.

**Small sequential slices:**

1. Introduce immutable alias resolver with cycle/collision rejection and fixture tests.

2. Persist confirmed household aliases through repository/outbox and migration; expose review action.

3. Use one resolver in search/demand/allocation, rebuilding affected live projections transactionally with versioned snapshots.


**Measurable acceptance:**

* beli luk/češnjak user-confirmed mapping resolves to one ingredient; unconfirmed suggestion changes nothing.

* 500 g plus 0.5 kg canonical demand equals 1,000,000,000 micros; g and ml remain separate.

* Cycles, ambiguous canonical mappings and cross-household aliases are rejected; retirement does not rewrite history.


**Concrete verification:**

* Pure tests for Serbian Latin diacritics, whitespace, duplicate/cyclic aliases and dimension mismatch.

* Golden demand/allocation before/after alias migration; two-account isolation and outbox replay.


### F003 — Sačuvane kombinovane pretrage (P1)

**Observed current state:** lib/domain/recipe_format.dart:filterRecipes searches only normalized title substring; lib/features/recipes/recipe_providers.dart:RecipeSearch holds an ephemeral string; RecipeRepository.watchAll supplies current household recipes.

**Contract/change:** RecipeQueryV1(text, includeIngredientIds, excludeIngredientIds, maxPrepMinutes, includeUnknownDuration=false, dietaryRuleSetId) plus SavedRecipeQuery(id, owner, name, queryJson, version). Extend current list/provider and pure query engine; persist user data via repository/outbox. Start with local scan, add drift index only when measured. Fuzzy title matches cannot satisfy hard ingredient exclusions.

**Dependencies:** F002, G-RULES, G-SYNC.

**Small sequential slices:**

1. Implement typed predicates and query serialization over existing Recipe list.

2. Expose combined filters on existing list; preserve title-search behavior and animations.

3. Persist, rename and delete saved queries; later add migration-backed index from benchmark evidence.


**Measurable acceptance:**

* AND query <=30 min + piletina + exclude kikiriki returns exactly fixture set.

* Unknown duration excluded for strict <=30 unless explicitly included; missing metadata shown.

* Saved query survives restart/offline/sync and never leaks between accounts.

* 1,000 recipes/20 ingredients predicate benchmark target p95 <200 ms on declared baseline device, recorded rather than presumed.


**Concrete verification:**

* Truth-table tests for conjunction/exclusion, unknowns, Serbian spelling and deterministic ordering.

* Widget save/load/delete; replay serialization round trip; benchmark without network or AI.


### F004 — Mogu danas da skuvam (P1)

**Observed current state:** lib/domain/shopping_demand.dart:demandFor provides scaled micros and unknownGroup; lib/domain/supply_allocation.dart:allocateSupply deduplicates purchase/receipt physical stock. lib/data/pantry_repository.dart:receivePurchases persists receipts; no recipe feasibility ranking API exists.

**Contract/change:** RecipeFeasibilityV1(recipeId, servings, status=covered|missing|needsReview, remainingLines, allocations, snapshotRevision). Build from existing demandFor/allocateSupply on confirmed usable pantry supplies, considering current reservations. Standalone candidate evaluation uses a fresh copy of the same stock, while accepted multi-slot plans share one allocation ledger. Quantity-free or uncertain lines never imply numerical coverage.

**Dependencies:** F002, G-PANTRY, G-RULES.

**Small sequential slices:**

1. Add pure feasibility façade over existing quantity functions.

2. Read confirmed stock/reservations through pantry data layer and show covered/missing/review groups.

3. Connect serving changes and approval refresh against current stock revision.


**Measurable acceptance:**

* Recipe requiring 400 g with 250 g confirmed stock shows exactly 150 g missing.

* Unknown stock or recipe quantity yields needsReview, never covered.

* One purchase and its pantry receipt count once; two 200 g meals cannot both claim the same 250 g in a joint plan.

* Missing 1–2 counts distinct demand groups and lists incompatible units separately.


**Concrete verification:**

* Hand-calculated 400-250=150 g fixture, serving scaling, reservations and receipt canonicalId tests.

* Regression existing demand/allocation tests plus offline recipe list/widget update on pantry edits.


### F005 — Potroši prvo (P1)

**Observed current state:** lib/data/database.dart:PantryItems.expiresAt/confirmedAt exist. Supply in lib/domain/supply_allocation.dart has no expiration metadata and allocates by supply ID; no expiry-aware ranking is present.

**Contract/change:** ExpiryEvidence(supplyCanonicalId, confirmedExpiresOn, dateKind, confirmationRevision). Rank candidates by actually allocatable known quantity from eligible soon-expiring lots, through an adapter around existing allocation. Do not change generic allocator ordering silently: introduce explicit lot preference policy after agreement with stream C. Date-only CivilDate and injected today; past date is review/exclude policy, never a safety judgment.

**Dependencies:** F004, G-PANTRY.

**Small sequential slices:**

1. Add pure expiring-lot ranking with fixed today and date-kind handling.

2. Expose window and confirmed dates on existing pantry-backed suggestions.

3. Add versioned policy to plan candidate scoring and explanation evidence.


**Measurable acceptance:**

* Only confirmed expiry within chosen 3-day window contributes; unknown and expired dates do not earn a bonus.

* Bonus capped by quantity actually consumed by candidate; duplicated receipt earns no extra credit.

* Identical input and today produce identical order; reasons show the actual item/date.


**Concrete verification:**

* Fixed-clock tests across month/year boundaries and Europe/Belgrade DST dates.

* Competing-lot fixture proving 50 g consumed from 100 g soon-expiring stock earns 50 g evidence, not 100 g.

* Widget unknown-date/expired-review and stock-revision refresh tests.


### F019 — PDF i nalepljeni tekst (P2)

**Observed current state:** lib/ai/recipe_ai.dart:RecipeAI supports fromImage/fromDishName/refine; lib/features/recipes/from_photo_screen.dart and AiRecipePreview provide image draft flow. No PDF/text import endpoint or source-document model exists.

**Contract/change:** Reuse ImportDraftV1 with kind=text|pdf, immutable source digest, page/character spans and extraction mode=text|ocr|ai. Proposed limits: 10 MiB PDF, 10 selected pages, 100k extracted characters; enforce byte/magic/type limits and sandbox parser with network disabled. Text first, optional OCR on empty/scanned pages; capability response reports unsupported encrypted PDF/OCR. AI must preserve unresolved quantity strings and flag uncertainty.

**Dependencies:** F001, G-AI, G-PROVENANCE.

**Small sequential slices:**

1. Add paste-text pure parser/draft into same preview.

2. Add bounded PDF text service and page selection; source spans retained.

3. Add OCR capability adapter for scans with explicit unavailable state and same review/save transaction.


**Measurable acceptance:**

* Pasted fixture and text PDF preserve ingredients, source spans and null unknown quantities with no auto-save.

* Scanned PDF without OCR reports „Prepoznavanje ovog dokumenta nije dostupno” and offers text/photo input.

* Encrypted, overlimit and malformed PDFs fail boundedly; temporary uploads expire within 24 h unless explicitly retained.


**Concrete verification:**

* Synthetic PDF/text/scanned/encrypted fixtures, page/byte/time cap tests and sandbox no-egress assertion.

* Parser mismatch fake-AI tests and preview corrections/discard; no upstream code executed.


### F020 — Prevod uz očuvan original (P2)

**Observed current state:** lib/domain/recipe_version.dart:RecipeVersion stores previous recipe; lib/data/recipe_repository.dart:update retains at most 30 historical versions. lib/domain/recipe.dart:toAiJson contains numeric quantities and steps, but no immutable original language/document.

**Contract/change:** TranslationDraft(sourceRevisionId, targetLocale=sr-Latn, translated text by stable field IDs, numericInvariantDiff). Freeze original in provenance asset, not only the 30-version rolling history. Send text fields and placeholder tokens for quantities/units/times to AIRouter; reconstruct typed numeric fields deterministically. Unit conversions are a separate confirmed operation. Save a normal version with translation link and provenance.

**Dependencies:** F019, G-AI, G-PROVENANCE, G-SYNC.

**Small sequential slices:**

1. Implement field/token mapping and numeric-invariant validator.

2. Add AIRouter translation draft and paired original/translation preview.

3. Persist confirmed version and immutable original reference with delete/restore coverage.


**Measurable acceptance:**

* 2.5 g, 180 °C, 1/2 and 20 minutes preserve their original numeric/unit facts, including numbers inside steps.

* Any missing/changed placeholder blocks save with a review issue.

* After 31 later edits original source remains retrievable; output UI is Serbian Latin.


**Concrete verification:**

* Fake provider attempts altering numeric tokens, reordered fields and Cyrillic response.

* Round-trip source/version restore, prune/delete and private asset access tests.


### F024 — Share meni i browser unos (P2)

**Observed current state:** lib/app/router.dart contains in-app routes; existing add_recipe_sheet.dart lacks a share/extension intake contract. Existing repository and preview can own eventual save.

**Contract/change:** ExternalIntakeV1(kind=url|text|image, payload, intakeId, receivedAt, platform). OS share adapter and optional browser bridge feed existing ImportRequestV1; no separate storage. Persist small pending intake in account-scoped local queue; require sign-in before preview and explicit save. Reject executable schemes and oversize payload; browser extension uses least privilege active tab and never embeds provider credentials.

**Dependencies:** F001, F019, G-SYNC.

**Small sequential slices:**

1. Define deduplicated intake queue and route adapter with fake platform tests.

2. Implement capability probe/share intake per supported Android/iOS/macOS target and normal URL fallback.

3. Evaluate browser extension separately after app share works; consume same schema and endpoint.


**Measurable acceptance:**

* Same intake delivered twice yields one pending draft; no background recipe save.

* Cold/warm start and sign-in handoff preserve payload only within selected account.

* Unsupported platform displays „Nalepi link recepta”; URL parser rejects file/javascript/data schemes.


**Concrete verification:**

* Platform integration matrix for cold/warm app, canceled sign-in, account switch, app restart and invalid deep link.

* Fake hostile extension payload and preview discard/idempotent save tests.


### F025 — Uvoz objave sa društvene mreže (P3)

**Observed current state:** No social import integration exists in inspected lib/ai/recipe_ai.dart or add_recipe_sheet.dart. RecipeSource cannot express source post/transcript provenance.

**Contract/change:** SocialImportCapability(platform, supportedMedia, publicUrlOnly, status) delegates URL/text/image material to ImportDraftV1. Record post URL, submitted caption/transcript ownership/source and unavailable sections. Begin user-supplied caption/image rather than promise platform API access. No authenticated scraping, paywall bypass, remote code execution or invention from thumbnail/title; platform adapter returns needsUserContent when insufficient.

**Dependencies:** F001, F019, F024, G-PROVENANCE.

**Small sequential slices:**

1. Accept supplied post URL plus caption/image through shared draft flow.

2. Add supported-public-domain capability adapter only after API/terms review.

3. Add transcript spans when available; retain partial draft and review state.


**Measurable acceptance:**

* Title+thumbnail alone produces insufficient evidence, not a full recipe.

* Private/deleted/blocked post offers paste/photo path without requesting social credentials.

* Every inferred field is marked; confirmation needed before recipe save.


**Concrete verification:**

* Synthetic public-caption, partial-caption, unavailable-post and prompt-injection fixtures.

* Capability-off and timeout widget flows; provenance and no-autosave checks.


### F026 — RSS predlozi (P3)

**Observed current state:** No feed entities or subscription scheduler in lib/data/database.dart; RecipeRepository stores only explicitly saved recipes.

**Contract/change:** FeedSubscriptionV1(id, householdId, url, enabled, etag, lastModified, checkedAt) and FeedEntryV1(feedId, entryKey, title, link, publishedAt, state). Feed entries are suggestions, separate from Recipes. Fetch server-side via G-SERVER, parse bounded RSS/Atom with XML external entities/DTD/network disabled; conditional HTTP, capped poll/backoff and per-household uniqueness. Selecting entry invokes F001 preview.

**Dependencies:** F001, G-SERVER, G-SYNC.

**Small sequential slices:**

1. Implement bounded synthetic RSS/Atom parser and stable entry identity.

2. Add subscription repository/cache and constrained server polling.

3. Show suggestions with explicit import preview and unsubscribe/delete lifecycle.


**Measurable acceptance:**

* Repeated fetch/304 produces zero duplicate entries and zero recipe writes.

* Unknown/non-date publication time stays unknown; GUID-less stable key uses normalized link and feed scope.

* XXE/entity expansion blocked; private enclosure/image/link cannot bypass fetch boundary.

* Unsubscribe halts later polling; offline shows last successful check time.


**Concrete verification:**

* RSS/Atom/namespace fixtures, GUID reuse, 304, bad ETag, redirects, XML bomb and malicious link tests.

* Fake clock rate/backoff and unsubscribe; preview/discard/offline widgets and RLS.


### F030 — Potroši ove tri namirnice (P1)

**Observed current state:** filterRecipes in lib/domain/recipe_format.dart only searches titles; F004 quantity engine exists at domain level but no session-only ingredient selector.

**Contract/change:** QuickIngredientIntentV1(selected canonical ingredient IDs, optional quantities/unit, expiresWithSession=true). Feed same RecipeQuery/feasibility/scoring contracts. Name-only entries contribute matched-ingredient reasons, never confirmed availability. No phantom pantry entries or supply IDs; optional quantities are ephemeral scenario supply and clearly distinct from confirmed stock.

**Dependencies:** F002, F004.

**Small sequential slices:**

1. Add pure matching by canonical ingredients and evidence type.

2. Add 1–3 ingredient quick action on existing search flow.

3. Allow optional quantity scenario and transition to normal plan preview with no pantry writes.


**Measurable acceptance:**

* Three selected ingredient names produce ranked matches even with an empty pantry.

* Name-only match shows „Sadrži izabrane namirnice”, never „Imaš sve”.

* Closing flow leaves pantry/outbox unchanged; duplicate synonyms count once.


**Concrete verification:**

* Empty-pantry, synonym-duplicate and unknown-quantity tests.

* Widget enter/clear/close and verify zero database writes until explicit recipe/plan approval.


### F035 — Kontrola ponavljanja (P2)

**Observed current state:** lib/ai/meal_plan_ai.dart:propose only passes already planned draft titles to outline. lib/data/meal_plan_repository.dart:setCooked toggles bool; lib/data/database.dart:MealPlanEntries has isCooked but no actual cookedAt event history.

**Contract/change:** RepetitionRuleV1(canonicalRecipeId, windowDays, maxOccurrences, mode=hard|prefer) and CookingOccurrence(eventId, entryId?, recipeIdentity, recipeRevision, cookedOn, reversesEventId?). Integrate F047 actual cooking history; existing true flags have unknown actual dates and must not be fabricated from planned dates. Count actual cooking plus accepted prospective slots for planning limits, without counting canceled/undone cooking twice. Tie history to stable recipe identity, not title.

**Dependencies:** F047, G-RULES, G-SYNC.

**Small sequential slices:**

1. Agree cooking-event contract with stream E and migrate legacy flags as undated evidence.

2. Add pure rolling-window counter and candidate predicate.

3. Expose frequency setting and reason; use in offline and AI candidate validation.


**Measurable acceptance:**

* One cooking yesterday with max 1/7 days prevents another proposed occurrence; unexecuted old plans do not.

* Two recipes sharing a title remain distinct; rename does not erase history.

* Unsatisfiable frequency leaves slot unresolved and offers explicit rule edit; no silent relaxation.


**Concrete verification:**

* Fixed-date 7-day boundary, undo/duplicate event, rename and same-title fixtures.

* Legacy isCooked import shows unknown date; fake AI violating frequency rejected.


### F048 — Sezonski izbor (P2)

**Observed current state:** No region/season ingredient calendar in lib/domain/recipe.dart or database.dart; mealPlanSystemPrompt broadly mentions Serbian supermarkets but has no seasonal evidence.

**Contract/change:** SeasonCalendarV1(id, regionCode, publisher, sourceUrl, sourceRevision, license, reviewedAt, monthRanges, canonicalIngredientIds). Start manually curated and independently licensed Serbian region data; no claimed dataset collected in this pass. Seasonal scoring is a soft preference after hard rules, never availability or freshness fact. Preserve date and region of reason; offline uses last reviewed dataset.

**Dependencies:** F002, G-RULES, G-PROVENANCE.

**Small sequential slices:**

1. Define versioned calendar and pure month-wrap lookup with synthetic data.

2. Validate a region-specific dataset license/source before shipping real entries.

3. Add opt-in regional preference, local cache and bounded scoring reason.


**Measurable acceptance:**

* Fixture spanning Nov-Feb matches Nov/Jan but not June; unsupported region produces no seasonal bonus.

* Reason shows region, month and calendar version/source; missing data produces no invented claim.

* Seasonality never outranks a hard exclusion or substitutes for pantry stock.


**Concrete verification:**

* Synthetic month/hemisphere/region tests and offline cache/version update.

* Data review checks licensing, source date, canonical mapping and no unsupported Serbian coverage claim.


### F058 — Zašto je ovo predloženo (P1)

**Observed current state:** lib/ai/meal_plan_ai.dart constructs SlotProposal(title, libraryRecipeId/draftRecipeKey); lib/domain/meal_plan.dart:PlanDraft has no score evidence. AIResult.attempts tracks technical attempts, not user recommendation reasons.

**Contract/change:** RecommendationEvidenceV1(ruleId, inputRevision, metric, value, unit, sourceIds, observedAt) and RecommendationScoreV1(components, rankKey, rulesVersion). Pure scorer emits typed evidence; Serbian formatter renders only present facts. Explain available amount, expiry, duration and cooked history using respective adapters. Technical provider attempts remain separate; model prose cannot become factual evidence.

**Dependencies:** F004, G-RULES.

**Small sequential slices:**

1. Add score/evidence value objects and deterministic reason formatter.

2. Show a reason sheet for F004/F030; enrich with F005/F035/F048 as available.

3. Persist evidence with draft snapshot and revalidate on approval; show changed-input warning.


**Measurable acceptance:**

* 400 g demand/250 g supply reason reports exactly 250 g covered and 150 g missing.

* No duration/expiry/history data yields no corresponding statement.

* Score order reconstructs exactly from components; stock edit marks evidence stale until refreshed.

* Explanations in Serbian Latin show reference date rather than unsupported „sveže” claims.


**Concrete verification:**

* Hand-computed score golden, absent-field and rule-version tests.

* Widget stale evidence/refreshed rank; fake AI cannot inject new reason type or external URL.


### F089 — Determinističko novo planiranje offline (P2-foundation-first)

**Observed current state:** lib/features/planning/plan_generation.dart orchestrates MealPlanAI; lib/ai/meal_plan_ai.dart:propose needs network. Existing lib/domain/meal_plan.dart:PlanDraft and MealPlanRepository.approve already support review, snapshots, protected entries and transactional shopping reconciliation.

**Contract/change:** LocalPlanEngineV1(input: PlanRequest + typed rules + recipe/stock/history snapshots + today + rulesVersion; output: existing PlanDraft plus diagnostics/evidence). Strict candidate filter -> deterministic scorer -> bounded beam search across slots with shared allocateSupply ledger. Stable recipe IDs/slots break ties; no random UUID/time calls in engine. Search caps and deterministic node count provide partial/unsatisfiable diagnostics, not an optimality claim. Existing approve remains sole plan/shopping write path.

**Dependencies:** F003, F004, F058, G-RULES, G-PLANNER, G-PANTRY.

**Small sequential slices:**

1. Add pure single-slot candidate chooser returning existing SlotProposal/library snapshot.

2. Extend to chronological multi-slot bounded search with shared stock and protected slots.

3. Connect offline option to existing preview/approve; add F005/F035/F048 scoring only as each lands.

4. Benchmark fixed node budget and expose unresolved constraints/unsupported free-text wishes.


**Measurable acceptance:**

* Same serialized inputs/rulesVersion yield byte-equivalent normalized draft/evidence in 100 runs regardless recipe insertion order.

* All hard rules hold for every filled slot; no solution yields explicit empty slots/reasons, never unsafe fallback.

* Single 250 g stock across two 200 g slots records 150 g total shortfall, with no repeated stock allocation.

* Network-disabled generation makes zero AI/backend calls and persists nothing until approval.

* Target <=2 s for 31 days x3 slots x1,000 candidates with declared node cap/device; if unmet reduce candidate cap transparently without dropping hard rules.


**Concrete verification:**

* Tiny exhaustive oracle verifies hard constraints and expected ranking; infeasible and locked/cooked replacement cases.

* Permutation/property tests for determinism, quantity conservation, unknowns and cancellation/node cap.

* Offline widget generation/edit/approve, stale fingerprint and outbox idempotency regression; measured benchmark.


## Pinned upstream observations and reuse decisions

These are repository-source observations, not claims of security audits or hosted product guarantees. All paths below were inspected as text in read-only cached clones. Full commits make the links stable. Restricted source informs independently written contracts only. README descriptions were not used as proof of these code behaviors.


### [mealie](https://github.com/mealie-recipes/mealie/tree/471c7936d3c782a431fd2081b632f404cb3dbb1a)

Commit `471c7936d3c782a431fd2081b632f404cb3dbb1a`; license classification `AGPL-3.0-only`.


* [`LICENSE`](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/LICENSE) — `repository license`: AGPL v3 text; study-only policy applies.

* [`mealie/services/scraper/scraper.py`](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/services/scraper/scraper.py) — `create_from_html / finalize_scraped_recipe`: Creates/finalizes draft separately from caller persistence; image fetching is another trust boundary.

* [`mealie/services/scraper/recipe_scraper.py`](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/services/scraper/recipe_scraper.py) — `RecipeScraper.scrape / DEFAULT_SCRAPER_STRATEGIES`: Fetch once then strategy chain: package, transcription, OpenAI, OpenGraph; stops at first cleaned result.

* [`mealie/pkgs/safehttp/transport.py`](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/pkgs/safehttp/transport.py) — `is_blocked_ip / _check_target / _SafeTransportMixin._apply_pin`: Normalizes IPv4-mapped IPv6, rejects nonpublic destinations by default, resolves hosts and pins connection addresses.

* [`mealie/pkgs/safehttp/fetch.py`](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/pkgs/safehttp/fetch.py) — `_read_capped / resilient_fetch`: Stream cap and deadline/backoff machinery are separate from parsing.

* [`mealie/repos/repository_recipes.py`](https://github.com/mealie-recipes/mealie/blob/471c7936d3c782a431fd2081b632f404cb3dbb1a/mealie/repos/repository_recipes.py) — `RepositoryRecipes.page_all`: Household-scoped query, organizer/food filters and text search before pagination; do not truncate candidates before filtering.


**Reuse:** Study and cite only; no AGPL code copied. Implement Tavli-specific draft/fetch/search contracts independently.


### [recipes](https://github.com/TandoorRecipes/recipes/tree/cbb96e151fe0c57c16a4456fe1bd04230b1c1e5c)

Commit `cbb96e151fe0c57c16a4456fe1bd04230b1c1e5c`; license classification `LicenseRef-AGPL-3.0-with-Commons-Clause`.


* [`LICENSE.md`](https://github.com/TandoorRecipes/recipes/blob/cbb96e151fe0c57c16a4456fe1bd04230b1c1e5c/LICENSE.md) — `repository license`: AGPL v3 with Commons Clause restriction; not plain AGPL or permissive.

* [`cookbook/helper/recipe_url_import.py`](https://github.com/TandoorRecipes/recipes/blob/cbb96e151fe0c57c16a4456fe1bd04230b1c1e5c/cookbook/helper/recipe_url_import.py) — `get_from_scraper`: Maps scraper output to existing recipe JSON, attaches source URL, applies automation, parses servings/times.

* [`cookbook/helper/automation_helper.py`](https://github.com/TandoorRecipes/recipes/blob/cbb96e151fe0c57c16a4456fe1bd04230b1c1e5c/cookbook/helper/automation_helper.py) — `AutomationEngine.apply_food_automation / apply_unit_automation`: Space-scoped confirmed rules and cache; aliases separate from regex replacement; useful design pattern, not copied implementation.

* [`cookbook/helper/recipe_search.py`](https://github.com/TandoorRecipes/recipes/blob/cbb96e151fe0c57c16a4456fe1bd04230b1c1e5c/cookbook/helper/recipe_search.py) — `SearchParams.from_params / RecipeSearch.get_queryset / _resolve_params`: Typed combined filters, saved-filter scoping and cooked-history annotations/filtering.


**Reuse:** Study-only; custom added restriction. Independent exact-match alias and query model, no copied code or datasets.


### [RecipeSage](https://github.com/julianpoy/RecipeSage/tree/6d92e4804618e81bb463c9ab22345d92819e4448)

Commit `6d92e4804618e81bb463c9ab22345d92819e4448`; license classification `LicenseRef-RecipeSage-personal-use-or-commercial`.


* [`LICENSE.md`](https://github.com/julianpoy/RecipeSage/blob/6d92e4804618e81bb463c9ab22345d92819e4448/LICENSE.md) — `repository license`: Personal-use restriction with AGPL text and separate written license for other use; classify custom, not AGPL-only.

* [`packages/util/server/src/general/clip/clip.ts`](https://github.com/julianpoy/RecipeSage/blob/6d92e4804618e81bb463c9ab22345d92819e4448/packages/util/server/src/general/clip/clip.ts) — `clipUrl / clipHtml / attemptEach`: URL intake and JSON-LD -> microdata -> LLM strategy chain with usable/grounded checks and partial merge.

* [`packages/util/server/src/ml/pdfToRecipe.ts`](https://github.com/julianpoy/RecipeSage/blob/6d92e4804618e81bb463c9ab22345d92819e4448/packages/util/server/src/ml/pdfToRecipe.ts) — `pdfToRecipe`: Text extraction first, default 5-page bound, image OCR fallback if extracted text below threshold.

* [`packages/express/src/routes/import/job/pdfs.ts`](https://github.com/julianpoy/RecipeSage/blob/6d92e4804618e81bb463c9ab22345d92819e4448/packages/express/src/routes/import/job/pdfs.ts) — `pdfsHandler`: Authenticated upload, size limit, temporary file/storage and queued job ID; useful async intake boundary.

* [`packages/util/server/src/search/searchRecipeIds.ts`](https://github.com/julianpoy/RecipeSage/blob/6d92e4804618e81bb463c9ab22345d92819e4448/packages/util/server/src/search/searchRecipeIds.ts) — `searchRecipeIds`: Scoped fulltext-prefix and fuzzy title searches merged/deduplicated under limit.

* [`packages/trpc/src/procedures/recipes/searchRecipesByIngredients.ts`](https://github.com/julianpoy/RecipeSage/blob/6d92e4804618e81bb463c9ab22345d92819e4448/packages/trpc/src/procedures/recipes/searchRecipesByIngredients.ts) — `searchRecipesByIngredients`: Bounded input terms with matchedTerms evidence and visibility constraints.

* [`packages/util/server/src/db/findRecipesByIngredients.ts`](https://github.com/julianpoy/RecipeSage/blob/6d92e4804618e81bb463c9ab22345d92819e4448/packages/util/server/src/db/findRecipesByIngredients.ts) — `findRecipesByIngredients`: Matched ingredient count then unmatched count/title/ID ordering; term matching is not quantitative stock proof.


**Reuse:** Study-only; custom terms, no code copied. Independent PDF draft and local quantitative retrieval implementation.


### [recipe-scrapers](https://github.com/hhursev/recipe-scrapers/tree/80266d1db324d58f1426d78facbe2e342662b990)

Commit `80266d1db324d58f1426d78facbe2e342662b990`; license classification `MIT`.


* [`LICENSE`](https://github.com/hhursev/recipe-scrapers/blob/80266d1db324d58f1426d78facbe2e342662b990/LICENSE) — `repository license`: MIT, copyright 2015 The recipe-scrapers contributors.

* [`recipe_scrapers/_schemaorg.py`](https://github.com/hhursev/recipe-scrapers/blob/80266d1db324d58f1426d78facbe2e342662b990/recipe_scrapers/_schemaorg.py) — `SchemaOrg.__init__ / _find_entity`: JSON-LD and microdata extraction; handles @graph, WebPage.mainEntity and person references. Not a safe fetch boundary.

* [`recipe_scrapers/_opengraph.py`](https://github.com/hhursev/recipe-scrapers/blob/80266d1db324d58f1426d78facbe2e342662b990/recipe_scrapers/_opengraph.py) — `OpenGraph.site_name / title / description / image`: Small complete metadata extraction class on caller-supplied soup; copied unchanged.

* [`recipe_scrapers/_exceptions.py`](https://github.com/hhursev/recipe-scrapers/blob/80266d1db324d58f1426d78facbe2e342662b990/recipe_scrapers/_exceptions.py) — `OpenGraphException / RecipeScrapersExceptions`: Internal dependency copied unchanged, with version dependency.

* [`recipe_scrapers/__version__.py`](https://github.com/hhursev/recipe-scrapers/blob/80266d1db324d58f1426d78facbe2e342662b990/recipe_scrapers/__version__.py) — `__version__`: Version constant copied to complete internal imports; no upstream initializer executed.


**Reuse:** Copy only complete OpenGraph metadata module plus its two internal dependencies and MIT license. Reference only; schema.org extraction is a proposed adapter, not implemented by this kit.


### What the reference kit does and does not deliver

`research/reference-code/A/recipe-scrapers/` contains four unmodified upstream files (including license), totaling a complete OpenGraph metadata component and its internal exception/version dependencies. This is useful for source title/site/description/image preview extraction, not a complete recipe extraction engine or a safe HTTP client. Original copyright remains in LICENSE. The source had no separate NOTICE file found in the filename inventory. Every upstream file including LICENSE has a SHA-256 and pinned source URL in A.json. The local README is authored documentation and is not mislabeled as upstream code.

For actual structured recipe extraction, `SchemaOrg.__init__/_find_entity` provides a reviewed permissive reference for JSON-LD/microdata graph handling, but is not vendored with its third-party parser dependencies here. That portion remains an adapter to implement and test. No Mealie/Tandoor/RecipeSage code, brand assets, sample photos or recipe datasets were copied. None of this reference code is connected to Flutter/runtime.

## Migration, security and compatibility risks

* Rolling recipe history is insufficient for immutable originals. Provenance needs independent private lifecycle and deletion behavior; child records must never outlive account deletion accidentally.
* New source enums, sync schema and JSON payloads must support old clients; metadata-first additive fields and explicit schema versions precede enum expansion. All new server rows require RLS/grants tests and all user writes transactional outbox coverage.
* Alias edits can change demand identity and existing shopping contributions. Preview and recalculate live views atomically while retaining approved snapshots/alias revision; do not erase bought-item history or turn label equivalence into physical-unit conversion.
* Pantry ranking must account for reservations and expired/unknown lots and must not alter confirmed quantity. Spec 010 completion is a gate for relying on the full pantry UI, regardless of existing quantity-domain functions.
* AI prompt propagation fixes are necessary but insufficient: hard post-parse dietary validation and same-title draft identity are required. Strict unknown states must be visible to the user and never described as proof of allergen safety.
* Actual cooked time is unknown for current boolean flags. Repetition should distinguish unknown history from “never cooked”; importing planned dates as actual events would corrupt ranking.
* Shared keys compiled into app artifacts cannot become server secrets merely by hiding settings UI. Move the authority, budgets and credentials to server, audit build definitions after migration without printing values, and preserve BYOK policy explicitly.
* PDF/OCR engines, extension/share targets, social endpoints and safe egress primitives need capability checks. No dependency is approved or installed by this research; each eventual plan must justify one.

## Unresolved questions and bounded verification


* No upstream software, install script, provider call or production backend was run. Runtime behavior/performance and platform capability remain unverified.

* No licensed Serbia-specific season dataset was collected; F048 must not ship real seasonal claims before data/license review.

* No platform social API permission, browser extension distribution or OCR/PDF engine capability guaranteed; probe before implementation.

* All acceptance checks are proposed future tests; this delivery validates only artifact schema, coverage, hashes and Python syntax statically.

* Hard dietary rule taxonomy and unknown-ingredient policy need product confirmation during feature specification; default strict mode blocks unknown compliance, never claims allergen safety.

* Tavli runtime source is original baseline 1eca2c3d14fb5dd9b25a42958aa018c8d8dfbb94; research uses upstream HEAD snapshots independently pinned, not claims of installed compatibility.

* Server routing/governance must explicitly update constitution III/IV: keep AIRouter as orchestration entry and move built-in credentials to server without a parallel UI/provider bypass.


Delivery verification: validate A.json object/required entry fields, exact equality of 15 assigned IDs to streams.json, dependency identifiers, existence of every cited upstream source file, symbol strings where applicable, byte identity and SHA-256 of every copied upstream file, and static Python AST syntax of the three copied modules. These are artifact integrity checks; upstream modules/importers and Tavli tests are not run. The report and manifest define future checks separately. Runtime source, tests, migrations, shared docs and git state are untouched by stream A.

### Completed artifact checks

PASS: JSON parsing and required fields; exact set of 15 assigned IDs; dependencies resolve; 15 report sections; 4 pinned commits; 22 existing inspected source paths; 4 copied upstream files byte-identical with SHA-256 and license-path checks; MIT copyright retained; 3 Python modules statically parsed using `ast.parse` (not imported or executed). No Flutter/runtime/upstream/API tests or benchmarks were run. The reference-code README is authored documentation; copied_files records upstream files only.
