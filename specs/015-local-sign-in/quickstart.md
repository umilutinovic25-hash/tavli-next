# Lokalni pregled

Backend pokretati iz trajnog home worktree-a, npr.
`/Users/urosmilutinovic/tavli-login-fix`, jer Colima tamo vidi template fajlove.
Integraciona macOS aplikacija je u `/tmp/tavli-integration-014`.

```sh
colima start
cd /Users/urosmilutinovic/tavli-login-fix
supabase start --exclude studio,postgres-meta,logflare,vector,supavisor,imgproxy,edge-runtime,realtime
```

API je na `http://127.0.0.1:55321`, test sanduče na
`http://127.0.0.1:55324`. Ovo okruženje ne šalje prave poruke.
Za prikaz lokalnog naloga AI ključevi nisu potrebni.

Lokalni URL i lokalni anon/publishable ključ iz `supabase status` proslediti
kroz gitignored `build/local-preview.json` integracionog worktree-a. Vrednosti
ne ispisivati u chat, log ili repo. Nikad ne koristiti service-role ključ u aplikaciji.

```sh
cd /tmp/tavli-integration-014
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build macos --debug --dart-define-from-file=build/local-preview.json
open build/macos/Build/Products/Debug/tavli.app
```

U aplikaciji koristiti lokalnu probnu adresu `pregled@tavli.test`, kod iz
lokalnog sandučeta i naziv koji jasno pokazuje da je to probni nalog.
Stvarni nalog/hosted backend ovim nije konfigurisan ili promenjen.

Za sledeće pokretanje dovoljno je uključiti Colima, pokrenuti isti lokalni
Supabase stack i otvoriti već izgrađenu aplikaciju. `supabase stop` čuva bazu
u backup-u. Ne koristiti reset/no-backup za redovno zatvaranje pregleda.
