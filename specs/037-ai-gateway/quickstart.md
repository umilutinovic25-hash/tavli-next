# 037 — Quickstart

Pre izdanja primeniti serverske migracije, pa postaviti edge funkciju i tek
onda isporučiti klijent. `consume_ai_request` mora imati noviji `text` rezultat
(`ok`/`minute`/`day`); nove kolone kataloga i nabavke takođe moraju postojati.
Novi klijent nema dogovaranje verzije serverske šeme za upise.

Postavljanje (jednom, kad budu pravi ključevi; ne upisivati ih u repo ni u chat):

```bash
supabase secrets set GEMINI_API_KEY=… GROQ_API_KEY=… OPENROUTER_API_KEY=…
supabase functions deploy ai-complete
```

Lokalno: `supabase functions serve ai-complete --env-file <fajl sa ključevima>`
(fajl van repoa).

Ručna provera: prijavi se, obriši sopstvene AI ključeve, pokreni
„Napravi probni recept“; recept se pojavljuje preko ugrađenog Tavli AI-ja.
Bez ključa za provajdera na serveru funkcija vraća 503 i router prelazi na
sledeći model.

Testovi: `deno test supabase/functions/ai-complete/`, `supabase test db`,
`flutter test test/ai`.
