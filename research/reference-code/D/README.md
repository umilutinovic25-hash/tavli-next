# D reference code

The complete `distribute.ts` file is copied unchanged from Dinero.js under MIT, with the original copyright and full LICENSE. Exact commit, upstream paths and SHA-256 hashes are in `provenance.json` and `research/manifests/D.json`. No upstream NOTICE file was found.

This is a readable allocation reference, not a standalone executable library: imports remain as upstream and dependencies are not vendored. Do not run this subset or wire it into Flutter. Tavli should implement and test its own integer allocator with explicit input validation and stable member-ID tie breaking. Dinero distributes remaining units by descending weight; that is distinct from largest-fractional-remainder allocation. Its upstream test file was inspected, not copied or executed.

KitchenOwl and Open Prices were inspected under their actual root AGPL-3.0 LICENSE files; no code, tests, assets or license files from either project are copied here. Their findings are architectural patterns for independent implementation.
