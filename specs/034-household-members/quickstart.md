# 034 — Quickstart (ručna provera na lokalnom Supabase-u)

Nikad protiv produkcije. `supabase/.temp` je vezan za produkcijski projekat — koristi samo `supabase start`, `supabase db reset`, `supabase test db` (lokalno); nikad `db push` ni `config push`.

```bash
supabase start                      # API :55321, Mailpit :55324
supabase db reset                   # migracije uključujući 20261111130300
supabase test db                    # svi pgTAP testovi, uključujući 14_household_member_list_test.sql
flutter test                        # ceo suite
flutter build macos --debug
```

Dva naloga na jednom Mac-u: jedna instanca aplikacije (`flutter run -d macos --dart-define-from-file=secrets.json`) za nalog A, a za nalog B drugi korisnik macOS-a ili isti build posle odjave (podaci po nalogu ostaju na uređaju).

1. A: prijava (kod iz Mailpit-a), ime „Ana“, dodaj stavku u Nabavku.
2. A: Profil → Domaćinstvo → „Pozovi člana“ → kod se vidi kao `XXXX XXXX`, „Još 5 upotreba“, „Važi do …“ (+7 dana). „Kopiraj kod“.
3. B: prijava, ime „Marko“, Profil → Domaćinstvo → „Pridruži se kodom“ → nalepi kod malim slovima sa crticom → „Pridruži se“.
   - Očekivano: „Sada si član domaćinstva „Moje domaćinstvo“.“, traka „Preuzimam…“, Ananina stavka u Nabavci.
4. A i B: Domaćinstvo pokazuje „Ana — Vlasnik“ i „Marko — Član“, svako sa „Ti“ na svom redu; nigde imejl.
5. B: „Aktivno domaćinstvo“ → lično → „Prebaci“ → vidi svoje podatke; ponovo pokreni aplikaciju → i dalje lično.
6. A: „Prenesi vlasništvo“ na Marka → uloge zamenjene posle osvežavanja kod oba.
7. Marko (sada vlasnik) uklanja Anu → kod Ane posle povlačenja nadole: aktivno lično domaćinstvo, zajedničke stavke nestale sa uređaja.
8. Bez mreže (isključi Wi-Fi): Domaćinstvo pokazuje poslednju listu i „Prikazano je poslednje poznato stanje.“; „Pozovi člana“ → „Za ovo je potrebna internet veza.“
9. Pogrešan kod 5 puta, pa šesti pokušaj (bilo koji kod) → „Previše pokušaja. Pokušaj ponovo za 10 minuta.“
10. Široki prozor (≥ 1000 px) i tekst 2× (Podešavanja macOS-a → Pristupačnost): nema odsečenog teksta ni horizontalnog skrolovanja.
