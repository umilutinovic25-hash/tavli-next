# Tavli Next — six-chat research contract

The user authorized a new GitHub repository preserving original Tavli and a complete architecture/implementation plan for 90 feature proposals, plus code/idea research and YouTube discovery.

This initial delivery is a source-backed blueprint and reference-code collection, not a claim that 90 features are implemented. The original app remains the baseline.

Read AGENTS.md, .specify/memory/constitution.md, docs/expansion/IDEAS-90.md, research/feature-register.json and research/streams.json. Existing code wins over stale README status.

Each chat owns ONLY research/streams/LETTER.md, research/manifests/LETTER.json and research/reference-code/LETTER/. Do not modify app source, generated files, shared documents, migrations, git state, or another stream's output. Root integrates and commits after all reports are reviewed. Do not create more chats or agents.

Inspect public source, not just README. Pin repository HEAD, inspect exact file paths and named functions/classes, distinguish source observations from proposals and unknowns. Do not run upstream software/install scripts or access production services. Cache read-only clones outside this repository under /Users/urosmilutinovic/.cache/tavli-next-sources/LETTER/.

Do not read or print secrets, credentials or personal data. Do not copy proprietary assets or videos. For reference code, copy at least one useful small complete upstream file ONLY when its actual license and file notices permit it, include the exact license/NOTICE and source/commit/hash. MIT/BSD/Apache candidates preferred. AGPL/GPL/custom/unlicensed sources can be inspected and cited, but no code copied in this pass. If nothing suitable, explicitly report that instead of pretending code was collected. No upstream code is wired into runtime in this task. Preserve original authorship; never add Codex co-author or session lines.

Manifest: JSON object with stream, features (exact owned Fnnn IDs), sources (repo_url, commit, license_spdx_or_unknown, inspected_files with path/symbol/finding, reuse_decision), copied_files (local_path, upstream_path, sha256, source_url, license_path), unknowns. Features array entries must have id, current_state (observed), proposed_changes, dependencies (Fnnn or foundation gates), acceptance_criteria, verification, phase, scope_slices (small sequential vertical slices). Do not claim tests were run unless actually run.

Markdown report: current-state evidence; architecture/module contracts; one entry per assigned feature with explicit acceptance and verification; migration/compatibility risks; exact upstream evidence and reuse decisions. For conditional API/device features define capability probes and graceful unavailable states; do not promise integrations. Finish bounded research with concrete files, and state unresolved questions.
