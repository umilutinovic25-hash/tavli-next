# Zadaci

- [x] Bezbedan HTTP fetch: provera i vezivanje javne IP adrese, ručno obrađena preusmeravanja, ograničenja i testovi.
- [x] JSON-LD parser i testovi; izvorni tekst nejasnih sastojaka ostaje za proveru.
- [x] Poreklo kroz model, lokalnu i serversku migraciju, sync i verzije; RLS provera sa dva naloga.
- [x] Pregled i izmena pre čuvanja kroz postojeći formular i repozitorijum, test na telefonu i širokom ekranu.
- [x] Flutter analiza i pun skup testova; Deno testovi i konkretni pgTAP scenario.
- [x] macOS build (`flutter build macos --debug`, Xcode 27.2).
- [x] Integraciona provera u lokalnom Supabase Edge runtime-u; transport prebačen na `Deno.connect`/`Deno.startTls` jer runtime nema `Buffer` ni `lookup` u `node:http`.
- [x] Ograničenje po nalogu: 10 uvoza u minuti i 60 dnevno (`public.consume_recipe_import`, samo service_role; pgTAP sa dva naloga, 429 i poruka u aplikaciji; provereno u Edge runtime-u).
- [ ] Pre objave: nezavisan bezbednosni pregled.
