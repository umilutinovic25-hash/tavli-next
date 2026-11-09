# Stream A reference code — documentation only

Unmodified complete files from `hhursev/recipe-scrapers`, commit `80266d1db324d58f1426d78facbe2e342662b990` (MIT).
Copyright (c) 2015 The recipe-scrapers contributors. Original license is preserved in `recipe-scrapers/LICENSE`.
No upstream NOTICE file was found by filename inventory. No notices were removed from copied files.

`OpenGraph` extracts site name, title, description and image metadata from a supplied BeautifulSoup-compatible document. This is a useful small metadata extraction component for import previews and provenance, **not a complete recipe importer**. `_exceptions.py` and `__version__.py` close its internal import dependencies. No upstream package initializer was copied; these files are reference-only and are not installed, executed, or wired into Tavli. A later Python adapter would need a package namespace and an HTML parser (e.g. BeautifulSoup); a Dart implementation can use the behavior as a test oracle after separate review. An extracted image URL must still pass the server fetch policy.

Inspect `research/manifests/A.json` for source URLs and SHA-256 of every copied upstream file, including LICENSE. Metadata alone must never be turned into invented ingredients or steps. For schema.org recipes, the report cites `_schemaorg.py` but does not vendor its dependency tree. Mealie, Tandoor and RecipeSage are study-only: no code copied.
