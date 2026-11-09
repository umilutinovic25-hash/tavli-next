# 015 — Ispravna prva prijava e-poštom

## Problem i reprodukcija
Build bez SUPABASE_URL/SUPABASE_ANON_KEY namerno nema backend i prikazuje
„Prijava trenutno nije dostupna.“. Za lokalni pregled treba postojeći Supabase
stack i build sa njegovom lokalnom konfiguracijom.

Nakon povezivanja, nov nalog dobija confirmation poruku. Postojeći confirmation
HTML sadrži samo link, a Flutter CodeStep prihvata i automatski proverava
šestocifreni kod. Poruka čak pominje dugme koje više ne postoji u aplikaciji.
Očekivano: i novi i postojeći korisnik dobijaju kod koji mogu uneti u aplikaciju.

## Opseg
Izmeniti samo confirmation šablon da koristi isti prikaz `{{ .Token }}` kao
postojeći magic_link. Sačuvati postojeći izgled, rok 10 minuta i jednokratnost.
Ukloniti instrukciju za nepostojeći tok potvrde linkom. Auth, RLS, model i
aplikaciona navigacija ostaju postojeći; nema novih zavisnosti ili šeme.

## Prihvatanje
1. Svež nalog → Pošalji kod → lokalni Mailpit prima poruku sa šest cifara.
2. Unos tog koda u macOS aplikaciju vodi na unos imena, zatim glavne tabove.
3. Postojeći nalog i dalje koristi magic_link kod; pogrešan kod ne prijavljuje.
4. Lokalni backend i konfiguracija mogu se ponovo pokrenuti bez gubitka podataka.
5. Konfiguracija i vrednosti ključeva/kodova ne ulaze u git, log ili dokumentaciju.

## Tekst poruke
Tvoj kod za prijavu je {{ .Token }}. Važi 10 minuta.
Upiši ovaj kod u aplikaciju Tavli da potvrdiš adresu i prijaviš se. Lozinka ti nije potrebna.
Kod važi 10 minuta i može da se iskoristi samo jednom.
