# Open Food Facts Dart reference only

Repository: https://github.com/openfoodfacts/openfoodfacts-dart
Commit: `64237b8c7c69dabb17fc1c894ab11dedec5bd1c4`.
License: Apache-2.0; exact upstream LICENSE is included. No repository NOTICE file was found in the inspected checkout. The two source files contain no copyright header; original contents and comments are preserved byte for byte. Do not substitute a new author. File hashes are in research/manifests/C.json.

Complete dependency-closed pair: `UnitHelper.stringToUnit` maps external spelling to a tagged Unit, using `OffTagged.fromOffTag`. Useful at an external API parsing boundary; it does not convert mass to volume and is NOT a replacement for Tavli normalizeUnit or fixed-point accounting. These are nutrient/API units, not evidence of a confirmed package size. No generated code, SDK installation or runtime wiring is included. No upstream code was executed.

Before future adoption: write boundary tests for null, unknown units, g, l, ml, microgram aliases and unsupported nutrient units; map only compatible dimensions to Tavli. Keep adapters behind the existing data layer. The copied code is reference material, not a shipped integration.
