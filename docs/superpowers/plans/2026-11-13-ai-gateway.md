# 037 AI gateway — plan implementacije

> **Za agente:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (preporučeno) ili superpowers:executing-plans. Koraci koriste `- [ ]`.

**Cilj:** AI zahtevi „ugrađenog“ Tavli AI-ja idu preko Supabase edge funkcije `ai-complete` koja drži provajder ključeve; aplikacija u izdanju nema nijedan provajder ključ.

**Arhitektura:** Edge funkcija po uzoru na `recipe-url-import` (prijava, limit po nalogu kroz bazu, secrets). Klijent dobija `GatewayChatClient`; `AIRouter` ostaje nepromenjen. „Ugrađeni“ ključ postaje marker `gatewayCredentialValue` koji `RoutingChatClient` šalje na gateway umesto direktno provajderu.

**Tehnologije:** Deno (edge funkcija, `deno test`), Postgres + pgTAP, Dart/Flutter (Riverpod, `package:supabase`).

**Spec:** `docs/superpowers/specs/2026-11-13-ai-gateway-design.md`

## Globalna ograničenja
- Limit po nalogu: **20 u minuti, 300 dnevno**; odbijeni pozivi se takođe broje; ako brojač ne radi, zahtev se odbija (503).
- Najveće telo zahteva **6 MB** (`6 * 1024 * 1024` bajtova).
- Samo provajderi `gemini`, `groq`, `openrouter` i modeli iz `ModelSpec` lanaca (`lib/ai/chain_config.dart`) — lista modela na serveru; ništa drugo se ne prosleđuje.
- Ključevi, tekst upita i slike se nikad ne loguju.
- Tekstovi za korisnika na srpskom (latinica). Izdanje (`kReleaseMode`) nikad ne čita `--dart-define` ključeve.
- Spec broj 037; grana `037-ai-gateway`; pre commita `scripts/check.sh` mora da prođe.

## Review Focus
- Korisnik nije prijavljen: ugrađeni AI se preskače uz jasnu poruku (ne „Proveri ključeve“) — test u Zadatku 5.
- Istekla sesija (gateway 401): mapira se u `TransientError`, ne `AuthError`, da router ne isključi gateway do restarta — Zadatak 4.
- Telo veće od 6 MB ili slika koja ga prelazi: 413, bez poziva provajdera — Zadatak 2.
- Model ili provajder van liste: 400, bez poziva provajdera — Zadatak 2.
- Provajder vrati prazan ili ne-JSON odgovor: `provider_error` (502), ne pad funkcije — Zadatak 2.
- Dnevni limit naloga: `RateLimitError(isDaily: true)` sa `retryAfter` — Zadatak 4.

---

### Zadatak 1: Brojač po nalogu (baza)

**Fajlovi:**
- Create: `supabase/migrations/20261113150000_ai_gateway_limit.sql`
- Test: `supabase/tests/20_ai_gateway_limit_test.sql`

**Interfaces:**
- Produces: `public.consume_ai_request(uid uuid, at timestamptz default now()) returns boolean` (true = u okviru limita), izvršava samo `service_role`.

- [ ] **Korak 1: Napiši pgTAP test** po uzoru na `08_recipe_import_limit_test.sql`: 20 poziva u minuti prolazi, 21. je odbijen; drugi nalog ima svoj brojač; nova minuta vraća pristup; 300 dnevno pa 301. odbijen; novi dan vraća; `authenticated` i `anon` nemaju `execute` ni `select` na tabeli; brisanje naloga briše red.
- [ ] **Korak 2: Pokreni, očekuj pad** — `supabase test db` (funkcija ne postoji).
- [ ] **Korak 3: Napiši migraciju** kopijom šablona iz `20261110120110_recipe_import_limit.sql`: tabela `private.ai_gateway_usage`, funkcija `consume_ai_request`, `mc <= 20 and dc <= 300`, ista prava (`service_role` only).
- [ ] **Korak 4: Pokreni testove** — `supabase test db`; očekuj sve PASS.
- [ ] **Korak 5: Commit** — `feat(037): brojač AI zahteva po nalogu`.

### Zadatak 2: Logika gatewaya (Deno, bez mreže)

**Fajlovi:**
- Create: `supabase/functions/ai-complete/gateway.ts`
- Test: `supabase/functions/ai-complete/gateway_test.ts`

**Interfaces:**
- Produces:
  - `parseRequest(raw: unknown, byteLength: number): GatewayRequest | GatewayError` — proverava polja `provider`, `model`, `system`, `prompt`, `images[{mime,base64}]`, `temperature` (0–2), dozvoljene provajdere/modele, `byteLength <= 6 MiB`.
  - `buildUpstream(req: GatewayRequest, keys: Record<string,string>): { url: string; init: RequestInit }` — isto telo kao `OpenAICompatibleClient.buildBody` (`response_format: json_object`, slike kao `image_url` data URL), baseUrl i zaglavlja po provajderu (`X-Title: Tavli` za OpenRouter).
  - `mapUpstream(res: Response): Promise<{status:number; body:Record<string,unknown>}>` — 200 → `{text}`; provajder 429 → 429 `{error:"rate_limited", retry_after?:number, daily:boolean}`; 401/403 → 502 `provider_error` (ključ servera je problem, ne korisnika); 404 → 404 `model_not_found`; 5xx, prazan ili neispravan odgovor → 502 `provider_error`.
  - `type GatewayError = { status: number; error: string }`; kodovi: `bad_request` 400, `too_large` 413.

- [ ] **Korak 1: Napiši Deno testove** za svaki Review Focus red iz ovog zadatka (telo > 6 MiB → 413; nepoznat model/provajder → 400; prazan `choices` → 502; ne-JSON → 502) plus srećan put i `daily` detekciju (kopija pravila `looksLikeDailyLimit` iz `lib/ai/chat_client.dart`).
- [ ] **Korak 2: Pokreni** — `deno test supabase/functions/ai-complete/`; očekuj pad.
- [ ] **Korak 3: Implementiraj** `gateway.ts` (čist kod, `fetch` se ne zove ovde). Lista modela: uzeti iz `ChainConfig.defaults` u `lib/ai/chain_config.dart` i prepisati kao konstantu; u komentaru navesti da se održava uz taj fajl.
- [ ] **Korak 4: Pokreni testove** — očekuj PASS.
- [ ] **Korak 5: Commit** — `feat(037): logika AI gatewaya (provera zahteva i mapiranje odgovora)`.

### Zadatak 3: Edge funkcija `ai-complete`

**Fajlovi:**
- Create: `supabase/functions/ai-complete/index.ts`
- Modify: `supabase/config.toml` (dodati `[functions.ai-complete]` sa `enabled = true`, `verify_jwt = true`, kao `recipe-url-import`)
- Create: `specs/037-ai-gateway/spec.md` (kratko: link na dizajn, status, ključne odluke i naredba za secrets)

**Interfaces:**
- Consumes: `parseRequest`, `buildUpstream`, `mapUpstream` (Zadatak 2); `public.consume_ai_request` (Zadatak 1).
- Produces: POST `/functions/v1/ai-complete` → telo `{text}` ili `{error, retry_after?, daily?}` sa statusima iz Zadatka 2; 401 `unauthorized`, 405 `method`, 429 `rate_limited` (limit naloga, `daily` po brojaču), 503 `unavailable` (brojač ne radi).

- [ ] **Korak 1: Implementiraj `index.ts`** po redosledu iz `recipe-url-import/index.ts`: metoda → token → `getUser` → `consume_ai_request` (greška → 503, `false` → 429) → čitanje tela sa prekidom na 6 MiB → `parseRequest` → `fetch(buildUpstream(...))` sa `AbortSignal.timeout(60_000)` → `mapUpstream`. Ključevi iz `Deno.env` (`GEMINI_API_KEY`, `GROQ_API_KEY`, `OPENROUTER_API_KEY`); ako ključ za provajdera ne postoji → 503 `unavailable`. Ništa iz tela se ne loguje.
- [ ] **Korak 2: Pokreni lokalno** `supabase functions serve ai-complete` i pozovi `curl` bez tokena; očekuj 401.
- [ ] **Korak 3: Commit** — `feat(037): edge funkcija ai-complete`.

### Zadatak 4: `GatewayChatClient` (klijent)

**Fajlovi:**
- Create: `lib/ai/gateway_chat_client.dart`
- Test: `test/ai/gateway_chat_client_test.dart`

**Interfaces:**
- Consumes: `ChatClient` (`lib/ai/chat_client.dart`), `AIError` klase (`lib/ai/ai_errors.dart`), `SupabaseClient`.
- Produces: `class GatewayChatClient implements ChatClient { GatewayChatClient(SupabaseClient? client); Future<String> complete(ModelSpec model, AIRequest request, {required String apiKey}); }` — `apiKey` se ignoriše. Mapiranje: 429 → `RateLimitError(message, retryAfter: Duration(seconds: retry_after), isDaily: daily)`; 401 → `TransientError('Sesija je istekla')`; 404 → `ModelNotFoundError`; 400/413 → `BadRequestError`; 502/503/ostalo → `TransientError`; `client == null` → `TransientError('Nije prijavljen')`.

- [ ] **Korak 1: Napiši testove** sa lažnim pozivačem funkcije (injektuj `Future<FunctionResponse> Function(String name, Map body)`, podrazumevano `client.functions.invoke`): srećan put vraća `text`; po jedan test za svako mapiranje iznad, uključujući dnevni 429 sa `retry_after`.
- [ ] **Korak 2: Pokreni** — `flutter test test/ai/gateway_chat_client_test.dart`; očekuj pad.
- [ ] **Korak 3: Implementiraj** klasu (telo zahteva: `provider`, `model`, `system`, `prompt`, `temperature`, `images` kao `{mime, base64}`).
- [ ] **Korak 4: Pokreni testove** — očekuj PASS.
- [ ] **Korak 5: Commit** — `feat(037): GatewayChatClient i mapiranje grešaka`.

### Zadatak 5: Usmeravanje i povezivanje

**Fajlovi:**
- Modify: `lib/ai/key_store.dart` (konstanta `gatewayCredentialValue = 'tavli-gateway'`; `factory BuiltInKeys.gateway()` sa markerom za sva tri provajdera)
- Create: `lib/ai/routing_chat_client.dart`
- Modify: `lib/providers.dart` (`builtInKeysProvider`, novi `aiChatClientProvider`, `aiRouterProvider` koristi njega; `chatClientProvider` ostaje za `ai_keys_screen.dart`)
- Modify: `lib/features/settings/ai_error_text.dart` (poruka kad nije prijavljen)
- Test: `test/ai/routing_chat_client_test.dart`, `test/ai/builtin_keys_policy_test.dart`

**Interfaces:**
- Consumes: `GatewayChatClient` (Zadatak 4), `OpenAICompatibleClient`.
- Produces:
  - `class RoutingChatClient implements ChatClient { RoutingChatClient({required ChatClient direct, required ChatClient gateway}); }` — `apiKey == gatewayCredentialValue` → `gateway`, inače `direct`.
  - `BuiltInKeys builtInKeysFor({required bool release, required bool signedIn, required BuiltInKeys fromEnvironment})` — izdanje: prijavljen → `BuiltInKeys.gateway()`, inače `BuiltInKeys()`; razvoj: ako `fromEnvironment` ima bar jedan ključ → on, inače kao izdanje.

- [ ] **Korak 1: Napiši testove**: `RoutingChatClient` usmerava marker na gateway, ostalo direktno; `builtInKeysFor` u izdanju nikad ne vraća `fromEnvironment` ključeve, ni kad postoje; nije prijavljen → prazno; razvoj sa ključevima → direktni ključevi; `ai_error_text` za slučaj „nema ključa i nije prijavljen“ daje „Prijavi se da bi koristio Tavli AI ili dodaj svoj ključ.“
- [ ] **Korak 2: Pokreni** — `flutter test test/ai/routing_chat_client_test.dart test/ai/builtin_keys_policy_test.dart`; očekuj pad.
- [ ] **Korak 3: Implementiraj** `RoutingChatClient`, `builtInKeysFor`, `BuiltInKeys.gateway()`; u `providers.dart` `builtInKeysProvider` zove `builtInKeysFor(release: kReleaseMode, signedIn: ref.watch(accountScopeProvider) != null, fromEnvironment: BuiltInKeys.fromEnvironment())`.
- [ ] **Korak 4: Pokreni sve** — `flutter test` i `scripts/check.sh`; očekuj PASS, bez izmene postojećih testova routera.
- [ ] **Korak 5: Commit** — `feat(037): ugrađeni AI preko gatewaya, bez ključeva u izdanju`.

### Zadatak 6: Dokumentacija i zatvaranje

**Fajlovi:**
- Modify: `ARCHITECTURE.md` (red „AI“: gateway umesto build-time ključeva), `docs/roadmap.md` (stavka 8 označena kao urađena, Supabase umesto Cloudflare), komentar u `key_store.dart` kod `KeySource` (ukloniti „Cloudflare proxy“).
- Create: `specs/037-ai-gateway/quickstart.md`

- [ ] **Korak 1: Ažuriraj dokumente**; u `quickstart.md`: `supabase secrets set GEMINI_API_KEY=… GROQ_API_KEY=… OPENROUTER_API_KEY=…`, `supabase functions deploy ai-complete`, ručna provera (prijavi se, „Napravi probni recept“ bez sopstvenog ključa radi).
- [ ] **Korak 2: Pokreni** `scripts/check.sh`; očekuj PASS.
- [ ] **Korak 3: Commit** — `docs(037): AI gateway u arhitekturi, roadmapu i quickstart-u`.
