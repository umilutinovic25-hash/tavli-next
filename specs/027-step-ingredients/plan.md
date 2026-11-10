# Plan

Koraci ostaju `List<String>` u svim zapisima (drift `steps_json`, server `steps`, `Recipe.toJson`, `RecipeSnapshot`), pa ih starije verzije čitaju i pišu kao ranije. `Ingredient` dobija opcioni `id` (u postojećem JSON-u sastojaka; dodeljuje se jednom, pri dodavanju u formi ili pri prvom povezivanju, nikad pri prikazu). Veze su zaseban zapis `[{text, uses: [{ingredientId, quantity?, unit?}]}]`: ključ `stepLinks` u JSON-u recepta, verzije i snimka, kolona `step_links_json` (drift v12) i `step_links jsonb` na serveru (nova migracija 20261110120600, provera da je lista). `readStepLinks` poravnava po tekstu koraka, pa ni stariji klijent koji prepiše korake ne može da prebaci vezu na drugi korak; upis bez `step_links` kolonu ne dira (pgTAP to proverava), a sastojci bez id-ja ostavljaju vidljivu nerazrešenu vezu. Domenski kod je u `lib/domain/step_links.dart` (čitanje/pisanje, preuzimanje id-jeva po nazivu za AI izmenu, sukob količina). Bez novih zavisnosti.

schemaVersion: grane 019–026 zauzimaju v6–v11, pa ova uzima v12; korak je idempotentan. Serverska migracija dolazi posle 026 (20261110120500).

## Constitution Check

I: srpski Latin; II: keš i outbox, postojeći RLS recepata, pgTAP; III: AI izmena ide kroz postojeći `AIRouter`, veze se samo prenose; IV: bez tajni; V: domen sa unapred poznatim rezultatima (300 + 200 g, sukob 600 g, v1 identičan, ponovljen tekst, stariji klijent), round-trip Recipe/verzija/snimak/drift/SyncEntity, widget testovi forme, detalja i AI izmene; VI: dugmad sa opisom za čitač ekrana, dijalozi tastaturom; VII: jedan commit; VIII: jedan spec i grana iz main; IX: nova migracija, generisan drift kod, hook i provere.
