# Plan
Grana 015-local-sign-in iz najnovijeg origin/main, jedna popravka toka prve
prijave. Pregledani SupabaseConfig, authGatewayProvider, CodeStep, postojeći
confirmation i magic_link HTML, mrežni macOS entitlements i lokalni config.

Najmanja izmena je confirmation HTML: isti jednokratni token koji Flutter već
proverava umesto linka i nepostojećeg koraka. Bez izmene Dart domena ili auth
kontrolera; regresija se proverava stvarnim lokalnim GoTrue → Mailpit → macOS
prijava tokom, umesto testa koji samo ponavlja sadržaj HTML fajla.

Lokalno okruženje: postojeći Colima profil, Supabase CLI iz zvaničnog Homebrew
tap-a, postojeće migracije i portovi 5532x. Backend se pokreće iz home worktree-a
koji Colima deli sa VM-om; /private/tmp nije montiran, pa mount HTML fajlova iz
privremenog integracionog worktree-a ne radi. Integracioni Flutter build dobija
samo lokalni URL/anon konfiguraciju u gitignored build/local-preview.json.
Ne čitaju se produkcioni ključevi niti se menja hosted projekat.

Ustav: srpski Latin, obavezan nalog, postojeći backend/cache/sync, bez AI, bez
tajni u gitu i bez promena šeme. Nema novih aplikacionih zavisnosti.
