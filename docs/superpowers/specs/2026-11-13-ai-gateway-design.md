# 037 — AI gateway (serverski AI ključevi)

Status: predlog, čeka odobrenje. Veličina: projekat (nova edge funkcija, izmena klijenta, uklanjanje ključeva iz izdanja).

## Namera i zašto
Pre objave aplikacije provajder ključevi (Gemini, Groq, OpenRouter) ne smeju da budu u aplikaciji (`secrets.json` → `--dart-define`). Aplikacija šalje AI zahteve našem serveru, a server drži ključeve i ograničava upotrebu po nalogu. Pravi ključevi se unose kasnije kao serverski secrets, bez izmene koda. Ovo je stavka 8 roadmapa i korak 5 plana („priprema za objavu“).

## Ciljevi
- Nijedan provajder ključ nije u izdanju aplikacije.
- Zahtev je dozvoljen samo prijavljenom nalogu; limit po nalogu (minut i dan); ako brojač ne radi, zahtev se odbija.
- Postojeći `AIRouter` (lanac modela, pauze, ponovni pokušaj) ostaje; menja se samo odakle dolazi „ugrađeni“ ključ.
- Sopstveni ključevi korisnika (BYOK) rade kao i do sada, direktno ka provajderu sa uređaja.

## Nije cilj
- Cloudflare Worker (nema potrebe: već koristimo Supabase edge funkcije).
- Streaming odgovora, plaćanje, kvote po planu.
- ADR o čuvanju korisničkih (BYOK) ključeva na serveru (ostaje van opsega, kao u ARCHITECTURE.md).

## Anti-ciljevi (neuspeh i ako tehnički radi)
- Server postaje otvoren proxy: prima proizvoljan URL, model ili provajdera.
- Ključevi, tekst upita ili slike završe u logovima.
- Aplikacija bez prijave više nema nikakav AI bez ikakve poruke zašto.

## Pristupi
1. **Supabase edge funkcija `ai-complete` (izabrano).** Isti obrazac kao `recipe-url-import`: provera prijave, limit po nalogu kroz bazu, secrets u Supabase. Nema novog servisa.
2. Cloudflare Worker (iz roadmapa). Odbačeno: novi nalog, deploy i način provere Supabase prijave bez dobitka za naš slučaj.
3. Ostaviti ključeve u aplikaciji. Odbačeno: ključeve je moguće izvući iz izdanja.

Izbor: 1 (korisnik: „radi ovako“; ostavljeno mojoj preporuci).

## Dizajn
**Server (`supabase/functions/ai-complete`):**
- POST `{provider, model, system, prompt, images[], temperature}`; zaglavlje `Authorization: Bearer <JWT>`.
- Redom: provera tela i veličine → provera prijave → limit (RPC kao `consume_recipe_import`, nova tabela/funkcija) → samo dozvoljeni provajderi i modeli (lista na serveru) → poziv `/chat/completions` provajdera sa serverskim ključem → vraća sirov tekst odgovora.
- Greške provajdera se prevode u stabilne kodove: `unauthorized`, `rate_limited` (+ `retry_after`, `daily`), `model_not_found`, `provider_error`, `unavailable`.
- Secrets: `GEMINI_API_KEY`, `GROQ_API_KEY`, `OPENROUTER_API_KEY`.

**Klijent:**
- Novi `ChatClient` za gateway (`supabase.functions.invoke('ai-complete')`) koji greške mapira u postojeće `AIError` klase, pa router radi bez izmena logike.
- „Ugrađeni“ ključ (`KeyOrigin.builtIn`) više nije vrednost iz `--dart-define` nego znači „preko gatewaya“; sopstveni ključevi idu starim direktnim klijentom.
- `BuiltInKeys.fromEnvironment` ostaje samo za debug/razvoj, nikad u izdanju.

## Moje odluke (da ih proveriš)
- Ugrađeni AI traži prijavljen nalog (potreban zbog limita po nalogu); bez naloga radi samo sopstveni ključ, uz jasnu poruku.
- Početni limit: 20 zahteva u minuti i 300 dnevno po nalogu (podesivo u bazi).
- Najveće telo zahteva 6 MB (zbog slika); veće se odbija.
- Spec broj 037 (rezervisan za AI ugovor).

## Prepušteno graditelju
Tačan naziv tabele za brojač, oblik tela greške, testovi (Deno test za funkciju, Dart test za klijent i mapiranje grešaka), redosled migracija i ažuriranje ARCHITECTURE.md.
