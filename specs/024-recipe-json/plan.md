# Plan

Čista Dart konverzija u `lib/domain/recipe_schema_org.dart` (izvoz, uvoz, izveštaj) nad postojećim `Recipe`/`Ingredient`, bez promene šeme baze i servera. Fajlovi idu kroz `RecipeFiles` interfejs (lažan u testovima); uvezeni recepti kroz `RecipeRepository.create` (keš + outbox). Meni detalja dobija „Izvezi kao JSON“, „Dodaj recept“ stavku „Iz JSON fajla“ (sheet sada skroluje da četiri stavke stanu na telefon). macOS entitlement `files.user-selected` prelazi sa read-only na read-write zbog čuvanja izvoza.

Nove zavisnosti:
- `file_selector` — izbor JSON fajla za uvoz i mesto čuvanja izvoza na macOS-u (zvanični flutter.dev paket; `file_selector_macos` je već tranzitivno prisutan).
- `share_plus` — sistemsko deljenje izvezenog fajla na Android/iOS, gde ne postoji dijalog za čuvanje.

## Constitution Check

I: srpski Latin; II: uvoz kroz repozitorijum i outbox, bez nove tabele; III: nema AI; IV: bez tajni; V: testovi domena sa unapred poznatim rezultatima i widget testovi; VI: dijalog i sheet rade na telefonu i širokom ekranu; VII: jedan commit; VIII: jedan spec i grana iz main; IX: bez migracija, obrazložene zavisnosti, hook i provere.
