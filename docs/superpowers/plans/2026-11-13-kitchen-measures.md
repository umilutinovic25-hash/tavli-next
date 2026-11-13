# 043 Kuhinjske mere — plan implementacije

> Izvršava se inline (superpowers:executing-plans), TDD po zadatku.

**Cilj:** rečnik jedinica v3 sa kuhinjskim merama i oznakom `~` u nabavci.
**Spec:** `specs/043-kitchen-measures/spec.md`

## Globalna ograničenja
- v0/v1/v2 rečnici se ne menjaju. Nova šema: drift `schemaVersion` 19→20 sa migracijom i testom; server kolona kao nov fajl u `supabase/migrations/`.
- Tekstovi na srpskom. `scripts/check.sh` i `flutter test` prolaze. Bez `--no-verify`.
- Flutter: `export PATH="$HOME/.cache/tavli-flutter-sdk/bin:$PATH"`.

## Zadaci
1. **Rečnik v3** (`lib/domain/shopping_demand.dart`): `NormalizedUnit` dobija `approximate`; `normalizeUnit(dictionaryVersion >= 3)` poznaje dl, dkg (tačno) i čaša, šolja, kašika, kašičica (približno, sa oblicima bez dijakritika i množinom); `dictionaryIngredientKey` prihvata 3. Test: `test/domain/shopping_demand_v3_test.dart`.
2. **Sabiranje** (`demandFor`, `summarize`): v3 se ponaša kao v2 (identitet, zamrznute konverzije); `DemandLine.approximate` i `ShoppingNeed.approximate` (ILI preko spojenih redova). Test: primer jogurt + kg/g + v2 netaknut.
3. **Novi snimci su v3** (`lib/domain/shopping_source.dart`): potvrda daje `dictionaryVersion: 3`; ažurirati testove koji očekuju 2.
4. **Čuvanje `~`**: drift kolona `approximate` na `ShoppingContributions` (v20, `addColumn`, build_runner), `entities.dart` toRemote/fromRemote, server migracija, upis u `shopping_repository.dart` (i poređenje izmena), izvoz (`personal_export.dart`). Testovi: migracija v19→v20, entities, export.
5. **Prikaz**: `PlanTotal.approximate`; „~“ ispred količine u `shopping_screen.dart`. Widget/data test za „~350 ml“ i „1,5 kg“ bez `~`.
6. **Dokumenti**: ARCHITECTURE.md (rečnik v3), spec status.
