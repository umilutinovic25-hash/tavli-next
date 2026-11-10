# Plan i provera ustava

Jedna sinhronizovana tabela šablona sadrži samostalan JSON snimak nedelje, bez stranih ključeva prema promenljivim receptima. MealPlanRepository čuva i primenjuje šablon transakciono, preko postojećeg SyncedWriter i ShoppingRepository. Interfejs se dodaje postojećem Planu i traži potvrdu pregleda. Nema novih zavisnosti.

I: srpski Latin; II: drift migracija, outbox, RLS i grants, offline; III: bez AI; IV: bez tajni; V: testovi modela, repozitorijuma, UI, migracije i dva naloga; VI: postojeći prilagodljivi interfejs; VII: scoped commit; VIII: jedan spec i grana; IX: generator za drift, format, analiza, testovi i macOS build.

Otvorene grane 012–017 nisu preduslov. Šablon čuva odobrene snimke, a obračun koristi postojeći javni reconcilePlan, pa ne uvodi drugu ostavu ili sistem nabavke.

## Provera i ograničenja

Puna lokalna Flutter provera: 567 testova; posebno su provereni i migracija 5 → 6 (sada 5 → 8; grana koristi schemaVersion 8 i serversku migraciju 20261110120200 zbog redosleda spajanja 019 → v6, 020 → v7, 021 → v8, 023 → v9), očuvanje kupljene stavke, ponovljene primene i prikaz na telefonu i širokom prozoru. Lokalna Supabase migracija i 229 pgTAP provera su izvršene u izolovanom kontejneru, direktno preko psql jer `supabase test db` nije pronašao datoteke. `flutter build macos --debug` prolazi uz Xcode 27.2.

Grana 012 menja filter potvrđene ostave u istom repozitorijumu i obračun u ShoppingRepository; šabloni pozivaju postojeći javni reconcilePlan, bez zavisnosti od te grane. Konačna integracija se ponovo proverava nakon spajanja drugih grana.
