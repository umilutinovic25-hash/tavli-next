# Quickstart: provera 036

```bash
export PATH="$HOME/.cache/tavli-flutter-sdk/bin:$PATH"
scripts/check.sh
flutter test test/domain/food_catalog_test.dart test/domain/shopping_demand_test.dart \
  test/domain/supply_allocation_test.dart test/domain/ingredient_synonyms_test.dart
flutter test test/data/food_catalog_flow_test.dart     # SC-001 kroz repozitorijume
flutter test test/domain/legacy_snapshot_golden_test.dart   # SC-002
supabase start && supabase db reset && supabase test db     # SC-003, SC-004
flutter test
```

## Ručno (macOS, uska i široka širina)
1. Recept „Omlet“: sastojak „Jajce“ → odmah pokazuje namirnicu *jaje* (bez „Nepotvrđeno“).
2. Sastojak „zmajevo voće“ → „Nepotvrđeno“ → „Nova namirnica“ → sačuvaj → oznaka nestaje.
3. Ostava „jaja 2 kom“ (potvrđeno), plan sa dva recepta sa jajima → u Nabavci jedna stavka „jaje“ sa očekivanom razlikom.
4. Recept iz AI sa nepoznatim sastojkom → „AI predlaže novu namirnicu: …“ → „Odbaci“ → katalog bez promene.
5. Recept sa jajima i brašnom → „Sadrži: jaja, gluten“; sa nepotvrđenim sastojkom i „Podaci o alergenima nisu potpuni.“
6. Stari plan (pre 036) → iste količine u Nabavci kao pre nadogradnje.
