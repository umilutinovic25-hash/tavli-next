# Lokalni pregled sa izdvojenim sigurnim skladištem

U gitignored build konfiguraciji lokalnog pregleda postaviti
`TAVLI_LOCAL_PREVIEW` na string `true`, uz lokalni SUPABASE_URL i lokalni anon
ključ. Preview dozvoljava samo http/https loopback (localhost, 127.0.0.1, ::1).
Podrazumevani build zadržava dosadašnje skladište i ponašanje.

Adapter samo prefiksira sve logičke ključeve sa `tavli.local-preview.v1/`;
postojeći Keychain/Keystore i njegovo OS šifrovanje/zaštita ostaju u upotrebi.
Stare stavke se ne čitaju, kopiraju ili brišu. Nema promene ACL-a ili zaobilaženja
SecurityAgent dijaloga. Prethodni OS zahtev je korisnik ručno odbio nakon što
je Tavli zaustavljen.

```sh
cd /tmp/tavli-integration-014
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build macos --debug --dart-define-from-file=build/local-preview.json
open build/macos/Build/Products/Debug/tavli.app
```

Prva prijava ovog odvojenog pregleda ide uobičajenim kodom iz lokalnog test
sandučeta `http://127.0.0.1:55324/`. Lozinka Mac-a nije zamena za taj kod.
Backend ostaje postojeći lokalni stack iz `tavli-login-fix`; podaci i modeli
računa/household-a koriste isti postojeći tok. Sesija se pamti u novom sigurnom
prostoru, što je provereno ponovnim pokretanjem.

AI ključevi za ovaj pregled dodaju se u Profil → AI ključevi. Nisu automatski
preuzeti iz običnog build-a. Ugrađena konfiguracija ovog lokalnog pregleda nema
AI ključeve. Kodovi, sesije i vrednosti ključeva ne unose se u repo ili dokumentaciju.

Ovo odvaja test okruženje od ranijih credentials. Za razvoj/release običnog
build-a sa ranijim korisničkim ključevima i dalje je potreban odgovarajući stabilan
code-signing identitet i korisničke OS dozvole. Promena ne isključuje normalnu
Keychain zaštitu pri budućim promenama potpisa ili zaključanom Keychain-u.
