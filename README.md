# Tavli

> **Tavli Next — privatni razvojni nastavak.** Originalni Tavli kod i istorija su sačuvani iz [anjahubac/tavli](https://github.com/anjahubac/tavli), commit `1eca2c3`. Ovaj paket dodaje arhitekturu, plan za 90 predloga i proverljive reference iz izvornog koda; ne tvrdi da je tih 90 funkcija implementirano.
>
> Počni od [arhitekture](ARCHITECTURE.md), [redosleda realizacije](tasks/plan.md), [detaljnog plana svih 90 funkcija](tasks/FEATURE-PLAN.md), [indeksa zadataka](tasks/todo.md), [istraživanja u šest paketa](research/streams.json) i [YouTube nalaza](research/YOUTUBE.md). [Poreklo i licence](docs/expansion/UPSTREAM.md), [prikupljeni kod](research/REFERENCE-CODE.md). Provera dokumentacionog paketa: `python3 tools/verify_blueprint.py`.

[Srpski](#srpski) | [English](#english)

## Srpski

**Od plana obroka do organizovane nabavke i kuvanja.**

Tavli je pomoćnik za organizaciju obroka i lična zbirka recepata. Uslikaj jelo, unesi njegov
naziv ili zapiši svoj recept — a zatim ga prilagodi kroz razgovor sa AI
pomoćnikom. Zameni sastojke, promeni broj porcija ili pojednostavi pripremu,
uz istoriju izmena koja ti omogućava da se vratiš na prethodnu verziju.

Za korišćenje aplikacije potreban je nalog: prijavljuješ se e-poštom i kodom,
bez lozinke. Svi tvoji podaci čuvaju se u nalogu i dostupni su na svakom uređaju
na kom se prijaviš, a kopija na uređaju omogućava pregled i uređivanje i bez
interneta — izmene se šalju čim se veza vrati. Interfejs je na srpskom jeziku,
latinicom, i prilagođen telefonu, tabletu i računaru. Internet je potreban za
prijavu i AI funkcije.

### Šta Tavli trenutno omogućava

- Kreiranje recepata iz fotografije, naziva jela ili ručnim unosom.
- Pregled predloga pre čuvanja i pretragu sačuvanih recepata.
- Prilagođavanje recepata kroz AI razgovor, uz vraćanje prethodnih verzija.
- Korišćenje Gemini, Groq i OpenRouter servisa, sa automatskim prelaskom na
  sledeći model kada prethodni nije dostupan.
- Dodavanje sopstvenih API ključeva i njihovo čuvanje u bezbednom skladištu
  uređaja.
- Nalog sa prijavom kodom iz e-pošte (bez lozinke): svi podaci se čuvaju u
  nalogu, dostupni su na svakom uređaju i rade i bez interneta.

### U planu

Sledeći glavni korak su nedeljni i mesečni planovi sa predlozima recepata i
nabavkom po nedeljama. Izbor doručka, ručka i večere, porcije, zamena i
zaključavanje obroka povezaće se sa potrebnim količinama. Ostava, sopstvene
preference i ocene pomagaće budućim predlozima. Ciljna navigacija je Plan,
Nabavka, Recepti, Ostava, sa profilom iza avatara. Ove funkcije su planirane;
još nisu implementirane. Nabavka će moći da se pripremi i samo za jedan
sačuvan, pronađen ili generisan recept, bez pravljenja plana.

Tok i izgled opisani su u [dizajnu proizvoda](docs/product-design.md), a
scenariji, tehnički plan i zadaci u [specifikaciji 010](specs/010-plan-and-shopping/spec.md).

Detaljan pregled razvoja nalazi se u [planu razvoja](docs/roadmap.md).

### Tehnologije

Razvijeno u Flutteru za Android, iOS i macOS. Nalog i podaci su na Supabase-u
(prijava, Postgres sa pravilima pristupa po redu, skladište fotografija; EU
region), a Drift (SQLite) čuva kopiju na uređaju za rad bez interneta. Stanje
aplikacije vodi Riverpod, a navigaciju go_router.



## English

**From meal planning to organized shopping and cooking.**

Tavli is a meal-organization companion and personal recipe collection. Take a photo
of a dish, enter its name, or write your own recipe — then make it your own
through a conversation with an AI assistant. Swap ingredients, adjust the
number of servings, or simplify the preparation, with version history that
lets you return to an earlier version.

An account is required: you sign in with your email and a one-time code, no
password. All your data is saved to your account and available on every device
you sign in on, while a copy on the device lets you browse and edit offline —
changes are sent as soon as you are back online. The interface is in Serbian
(Latin script), with layouts for phones, tablets, and desktops. Sign-in and AI
features require an internet connection.

### Current features

- Create recipes from a photo, a dish name, or manual entry.
- Preview suggestions before saving and search your saved recipes.
- Adapt recipes through AI chat and restore previous versions.
- Use Gemini, Groq, and OpenRouter, with automatic fallback to the next model
  when the previous one is unavailable.
- Add your own API keys and keep them in your device's secure storage.
- Sign in with a code sent by email (no password): all your data is saved to
  your account, available on every device and usable offline.

### Planned features

The next priority is weekly/monthly meal planning with recipe suggestions and
shopping by week: choose breakfast/lunch/dinner, adjust servings, replace or
lock meals, and combine ingredient quantities. Pantry, the creator's personal
preferences and ratings inform suggestions. Target navigation is Plan,
Nabavka, Recepti, Ostava, with profile/settings behind an avatar. These
features are specified and are not implemented yet. Standalone shopping
for one saved, searched or generated recipe will also work without a meal plan.

See [product design](docs/product-design.md) and
[010 specification](specs/010-plan-and-shopping/spec.md) for flows and tasks.

See the [roadmap](docs/roadmap.md) for a detailed development overview.

### Technology

Built with Flutter for Android, iOS, and macOS. Accounts and data live on
Supabase (auth, Postgres with row-level security, photo storage; EU region),
and Drift (SQLite) keeps an on-device copy for offline use. Riverpod manages
application state, and go_router handles navigation.

## Development

Requirements: Flutter (stable), Docker and the Supabase CLI.

```bash
flutter pub get
supabase start                      # local backend on ports 5532x
supabase db reset && supabase test db
git config core.hooksPath .githooks # once: pre-commit runs check + affected tests
scripts/check.sh                    # format, analyze
flutter test                        # all Flutter tests (CI runs them on every PR)
```

Create your own gitignored `secrets.json` from `secrets.example.json` and put
in `SUPABASE_URL` (`http://127.0.0.1:55321` locally) and the anon key printed
by `supabase status` (never commit it). Then run the app with
`flutter run -d macos --dart-define-from-file=secrets.json`; sign-in codes
arrive in the local mail catcher at http://127.0.0.1:55324. Without
`secrets.json` the app shows "Prijava trenutno nije dostupna.". Details:
[docs/architecture.md](docs/architecture.md),
[specs/006-account-login/quickstart.md](specs/006-account-login/quickstart.md).
