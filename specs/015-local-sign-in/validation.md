# Rezultat provere

- macOS build zajedničke 011/012/013/014 aplikacije sa lokalnom konfiguracijom:
  uspešan, Xcode 27.2 i Flutter 3.47.9. Flutter kod ove popravke nije menjan.
- Novi lokalni probni nalog: Pošalji kod → Mailpit confirmation poruka sa šest
  cifara → unos u macOS aplikaciju → „Kako da te zovemo?“ → „Probni pregled“ →
  glavni ekran Plan sa tabovima Plan/Nabavka/Recepti/Ostava. Potvrđeno kroz UI.
- Postojeći probni nalog: lokalni OTP endpoint šalje magic_link poruku koja
  sadrži kod; pogrešan kod je odbijen, ispravan je prihvaćen i vraća sesiju.
  Kodovi, sesije i ključevi nisu ispisani ili sačuvani u dokumentaciji.
- Lokalni backend dva puta zaustavljen standardnim stop i vraćen iz backup-a.
  Korišćene su postojeće migracije, bez resetovanja baze.
- Samostalna 015 grana iz origin/main: **562 Flutter testa prolaze**.
- `supabase test db` nalazi **0 SQL testova** u postojećem direktorijumu; to
  nije prolaz pgTAP zbirke. Stvarni auth tok je odvojeno proveren iznad.
- GitHub CI ostaje blokiran naplatom/limitom naloga, koju je vlasnik odložio.
  Popravka ide u draft PR, bez merge-a i bez izmene hosted konfiguracije.

## Lokalni resursi
Backend: home worktree `/Users/urosmilutinovic/tavli-login-fix`.
Aplikacija sa novim frontendom i Ostavom: `/tmp/tavli-integration-014`.
Konfiguracija aplikacije: njegov gitignored `build/local-preview.json`.
Lokalno sanduče: `http://127.0.0.1:55324`.
Probni nalog: `pregled@tavli.test`, prikazano ime „Probni pregled“.
