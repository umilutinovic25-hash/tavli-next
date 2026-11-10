# Stream B reference code

Source: https://github.com/cooklang/cookcli/tree/4e53c8c9c29a5ced2b444b19133cb38a5217c8bb

Complete unmodified file: `cookcli/days.rs` from `crates/core/src/shopping_list/days.rs`.
License: MIT; complete unmodified `crates/core/LICENSE` is `cookcli/LICENSE`, including Copyright (c) 2021-2023 Alexey Dubovskoy. No NOTICE file was found in the inspected source tree.

Purpose: reference for date-scoped ingredient selection and summing selected members of a quantity group, for F007/F014/period-boundary checks. It does not solve leftovers, undo, ICS or distributed sync. It depends on Rust std, chrono, cooklang and regex and is not standalone executable code. No source installation/build or execution occurred; no runtime integration is proposed. Adapt the idea to existing Tavli CivilDate, RecipeSnapshot and demand machinery.

SHA-256:

- days.rs: `5ce078aa4ebc0ad54217eaef958d249f64c776a463de4c98285fb65f848d700c`
- LICENSE: `af27681b98fd4549e7966762a119a1bd90c5ea547b42964da2407d7678dc6ddf`

Mealie AGPL and ical.js MPL source were read only; no files from them were copied.
