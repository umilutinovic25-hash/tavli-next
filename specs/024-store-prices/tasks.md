# Tasks: Store price imports and basket estimates

Status: implementation drafted in a separate feature branch; not merged or deployed. Source selection is recorded. Acceptance remains unverified where local SQL or reviewed product/package mappings are unavailable. Source roles/phases are preserved. Lead: Dev 1;
proposed reviewers: Dev 3 (choose a different human from the implementer).
Paths and contracts are in plan.md; finalize exact filenames and remaining
implementation/test/review estimates before Ready.

- [ ] T001 Resolve blocking questions in spec.md, agree typed contract/migration needs and acceptance fixtures. Owner Dev 1; reviewer Dev 3; depends on producer specs in plan.md; evidence: accepted decision/contract links.
- [ ] T002 [US1] D1-017 / FR-001, phase 4: inspect existing evidence and add missing failing behavior/acceptance cases for **Import store price lists** at the tiers required by 013. Owner Dev 1; reviewer independent domain consumer; depends T001 and relevant producer; evidence: reproducible missing behavior or documented existing coverage.
- [ ] T003 [US1] D1-017 / FR-001, phase 4: **Import store price lists** using plan.md paths and its agreed contract; update consumers and docs. Owner Dev 1; reviewer independent domain consumer; depends T002; evidence: spec scenarios, applicable checks and reviewed PR.
- [ ] T004 [US1] D1-018 / FR-002, phase 4: inspect existing evidence and add missing failing behavior/acceptance cases for **Compare basket prices by store** at the tiers required by 013. Owner Dev 1; reviewer independent domain consumer; depends T001 and relevant producer; evidence: reproducible missing behavior or documented existing coverage.
- [ ] T005 [US1] D1-018 / FR-002, phase 4: **Compare basket prices by store** using plan.md paths and its agreed contract; update consumers and docs. Owner Dev 1; reviewer independent domain consumer; depends T004; evidence: spec scenarios, applicable checks and reviewed PR.
- [ ] T006 Integrate consumer/release evidence, reconcile source ticket status and record unresolved limits. Owner Dev 1; reviewer Dev 3; depends on applicable implementation tasks; evidence: check commands/SHA/results and release decisions.

## Sequencing and effort

Do not treat this file's order as permission to run every task concurrently.
Dependencies are contracts plus phase/feature gates in the product plan. Tests
for future behavior land with that behavior; do not weaken current tests to make
it appear implemented. For research/infrastructure tasks use meaningful evidence
checks, not artificial Dart tests. Add task-specific subtasks when a source card
exceeds a 1–2-day reviewable slice. Cross-owner/shared-file changes need coordination.

Each Ready task records: exact files, named reviewer, producer PR, remaining days
(implementation + tests + review/integration), confidence and risk. Estimates are
not invented from ticket counts. Done requires accepted behavior, actual evidence
and merged PR; checkbox completion alone is not a release or an external approval.
