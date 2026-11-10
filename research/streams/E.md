# Stream E — kuvanje, učenje i uređaji

Datum: 9. novembar 2026. Baseline: `anjahubac/tavli@1eca2c3d14fb5dd9b25a42958aa018c8d8dfbb94`.

Ovo je istražen plan za 15 predloga, ne implementacija. Istražen je lokalni Tavli kod i četiri javna repozitorijuma, pinovana na konkretne commit-e. Nije pokretan upstream kod, build, installer, AAR ili produkcijski API. Nisu čitani ključevi, `secrets.json` ili Keychain. Promene ovog streama ograničene su na ovaj izveštaj, `research/manifests/E.json` i `research/reference-code/E/`.

## Šta zaista postoji

- `lib/domain/recipe.dart`: `Ingredient` nema ID; `Recipe.steps` je `List<String>`, uz opcioni `prepMinutes` i jednu `imagePath`. `Recipe.fromAiJson`, `toAiJson` i `copyWith` su važni pri svakoj promeni formata.
- `lib/domain/shopping_source.dart`: `RecipeSnapshot.fromRecipe/fromJson/toJson` čuva odobreni sadržaj; izmena biblioteke ne menja već odobren obrok. Snapshot nema pun identitet bibliotečkog recepta i korake čita kao tekst. Njega treba nadograditi zajedno sa `Recipe`, bez paralelnog sistema recepata.
- `lib/features/recipes/recipe_view.dart`: `RecipeView.build` ispisuje sastojke i korake, bez checklist state-a. `ReadableScroll` već ograničava čitljivu širinu. `RecipeDetailScreen`/`_Detail` u `recipe_detail_screen.dart` koristi `KeepScreenOnScope`; `MealEntryDetail` u `lib/features/planning/meal_entry_detail.dart` prikazuje snapshot plana. Ingredient review u receptu služi nabavci, nije checklist kuvanja.
- `lib/features/recipes/keep_screen_on.dart`: `ScreenWakeLock`, `KeepScreenOn`, `KeepScreenOnScope` i dugme već postoje; izbor je u `AppSettings`, platform error ne ruši ekran, scope pušta lock na dispose. Sačuvati izbor, animaciju sunce/mesec i reduced motion. `test/features/recipes/keep_screen_on_test.dart` pokriva toggle, izlazak, trajno podešavanje, wide, reduced motion i odbijanje platforme. Testovi su pročitani, nisu izvršeni u ovom istraživanju.
- `lib/app/app.dart`: `_TavliAppState._onResume` obnavlja auth i sync; tajmeri i uređaji nemaju lifecycle hook. Novi hook mora dopuniti postojeći, nikad zameniti auth/sync ponašanje. `lib/app/animations/egg_timer.dart` je animacija, ne pouzdan tajmer.
- `lib/data/database.dart`: schemaVersion je 5. `Ratings` već ima datum kuvanja, komentar i ocenu, ali nema session/log snapshot. To nije dokaz da je dnevnik kuvanja završen. `RecipeVersions` beleži izmene sadržaja; `RecipeRepository.maxVersions=30` znači da se na istoriju izmena ne sme osloniti trajni log.
- `lib/data/meal_plan_repository.dart`: `setCooked` menja postojeći obrok kroz `_edit`. `lib/data/shopping_repository.dart`: `reconcilePlan` koristi cooked stanje da zatvori izvor potražnje, a `addManual` već piše ručnu stavku i outbox u transakciji. Novi cooking završetak mora pozvati ovaj ugovor samo posle eksplicitne potvrde. Ne uvoditi drugu nabavku i ne smatrati checklist potrošnjom zalihe.
- `lib/domain/shopping_demand.dart`: `normalizeUnit`, `toMicros`, `fromMicros` su postojeći obračun; masa, zapremina i nepoznate jedinice nisu ista grupa. BLE vaga nije način da se bez gustine pretvori l u g.
- `lib/data/recipe_repository.dart`, `lib/sync/entities.dart`, `lib/sync/synced_writer.dart`, `lib/sync/photo_sync.dart`: postojeći repository/outbox/registry/photo tok ostaje osnova. `RecipeRepository.delete` trenutno briše ocene i razvezuje plan: novi log zahteva eksplicitnu politiku zadržavanja, a ne slepo kopiranje delete ponašanja.
- `lib/ai/recipe_ai.dart`: `RecipeAI.refine` menja recept; pomoć tokom kuvanja traži drugi feature façade nad istim `AIRouter`, sa JSON parserom i Serbian error mapiranjem. `pubspec.yaml` već ima `wakelock_plus`, nema speech/BLE integraciju.

## Predloženi ugovori i redosled

Sve putanje u ovom odeljku su **predlog novih ili proširenih modula**, ne tvrdnja da postoje. Pure Dart modeli idu u `lib/domain/`; repository-i u `lib/data/`; cooking controller/UI u `lib/features/cooking/`; native SDK-ovi iza `lib/devices/` adaptera i platform kanala. Riverpod provider-i prate postojeće `lib/providers.dart`/feature provider obrasce; route proširuje postojeći `lib/app/router.dart`. Najpre jedan spec i mala vertikalna celina, provera, pa sledeća funkcija.

| Gate | Konkretan izlaz pre zavisnih funkcija |
|---|---|
| G-SYNC | UUID identiteti; repository transakcija red+outbox; registry parent order; lokalna drift migracija sa schema bump-om i novom server migracijom, authenticated grantovima i RLS. Fake backend i lokalni pgTAP sa dva naloga. UI čita drift. Nema server rada u ovom istraživanju. |
| G-STEP | Minimalni adapter za stabilne step/ingredient identitete u cooking snapshot-u, uz legacy tekst fallback. P1 checklist/timer može koristiti ID-jeve zamrznutog session snapshot-a; kompletni uređivač veza F028 dolazi kasnije. Nije dozvoljeno praviti nova slučajna ID-jeva pri svakom čitanju. |
| G-FORMAT-COORDINATION | Dogovor sa A/F oko verzionisanog Recipe/RecipeSnapshot/import-export/validator formata (F022/F084). Dogovoriti jedan serializer i stariji client write gate; F028 ne zavisi od završetka punog validatora. |
| G-LIFECYCLE | Jedan vlasnik lokalnog timer scheduler-a i cooking resource coordinator; auth/sync resume ostaju aktivni; cleanup odjava/route/account switch; checkpoint pre suspend-a. |
| G-SPEECH | Runtime probe ASR i TTS posebno; permission i jezik nisu isto; Serbian locale i engine se proveravaju na fizičkom uređaju. Dependencies samo uz opravdanje u spec plan-u. |
| G-DEVICE | Device adapter contract + mock/manual adapter + permission/transport/model/firmware probe + pilot matrica. Bez uspešnog pilot-a funkcija ostaje uslovna i ručna. |
| G-ACAIA-LICENSE | Potvrđeni aktuelni uslovi SDK distribucije/komercijalne upotrebe i odabrane platforme; custom licenca ne tretira se kao MIT. |
| G-OVEN-API | Zvaničan API, eligibility/OAuth, model/region/remote-enable i supported commands potvrđeni u zasebnom pilotu. Ne pristupati pravim tokenima ili rerni u ovoj fazi. |
| G-AI | Postojeći AIRouter, faked provider tests, strict JSON/FormatException i cancel/late-response pravilo. |
| G-CONTENT | Sopstveni/odobreni sadržaj sa urednikom, izvorom i pravima po reviziji; offline distribucija i provera referenci. |

`CookingSession` zamrzava postojeći snapshot i porcije pri početku. Čekiranje je stanje izvršavanja, ne promena recepta, ocene, potrošnje ili liste. Log predstavlja lični rezultat tačne sesije. Referenca na verziju nije dovoljna jer se stare verzije prune-uju: zadržati snapshot i canonical content fingerprint, bez privatnih imena u hash-u. U prvoj verziji sesija/log/progress su person-scoped; recept i plan ostaju household-scoped. Server mora proveriti i vlasništvo reference i aktivno članstvo, ne samo primljeni householdId. BLE identifikatori ostaju lokalni osim izričite potrebe; ne slati sirove stream-ove u opšti outbox.

### Tajmeri i native lifecycle

`remaining = max(0, checkpointRemaining - (continuousNow - checkpointElapsed))` važi za running timer u istoj boot sesiji; paused timer zadržava checkpointRemaining. UI tick samo osvežava prikaz. Koristiti kontinuirani monotoni izvor koji uključuje sleep: na Android-u [SystemClock.elapsedRealtime/elapsedRealtimeNanos](https://developer.android.com/reference/android/os/SystemClock), na Apple platformama wrapper nad kontinuiranim satom kao [mach_continuous_time](https://developer.apple.com/documentation/kernel/1646199-mach_continuous_time) uz odgovarajuću konverziju. Sam `DateTime.now`, decrement svake sekunde ili neproveren Dart Stopwatch nisu ugovor za zaključavanje/suspend.

Persistirati monotonic checkpoint, njegov boot identity, wall UTC checkpoint, očekivani UTC rok i scheduler generation. Pri restartu u istom boot-u rekonstruisati iz native sata; ako boot kontinuitet ne može pouzdano da se potvrdi, prikazati stanje Proveri tajmer. Wall deadline je pomoć za oporavak/korisničku procenu, ne dokaz tačnosti nakon reboot-a ili promene sata. Nije moguće obećati izvršavanje ugašenog telefona. OwnerDeviceId sprečava da sync automatski zakaže alarm na svim uređajima; drugi uređaj prikazuje stanje sa oznakom izvornog uređaja. Handoff je kasniji eksplicitni protokol.

Zakazivanje alarma odvojiti od računanja vremena. Proveriti [Android exact alarm capability](https://developer.android.com/develop/background-work/services/alarms) i notification dozvole; [Apple local notification request](https://developer.apple.com/documentation/UserNotifications/scheduling-a-notification-locally-from-your-app) može dostaviti sistem dok je aplikacija u pozadini, ali dozvola i uspešno zakazivanje moraju biti provereni. Foreground-only fallback mora biti jasno označen. Svaki pause/cancel povećava generation i uklanja stari zahtev; kasni callback ne može oživeti otkazan tajmer. Force stop, Doze i reboot su posebni test scenariji, ne sinonimi za obično zatvaranje ekrana.

`ScreenWakeLock` zadržati kao isti injektovani port. Cooking ekran traži lock samo dok je vidljiv i izbor uključen; background/exit pušta, resume proverava i ponovo traži ako treba. Ako su detail i cooking scope istovremeno montirani, uvesti jedan coordinator sa owner tokenima da dispose jednog ne ugasi zahtev drugog. Serijalizovati async enable/disable da kasni enable posle dispose-a ne ostavi ekran budnim. Ovo je predlog proširenja za novu funkciju, nije uzgredna izmena postojećeg koda. Ne uvoditi CPU wake lock da bi se održavao UI tick. Zadržati sve postojeće animacije i reduced-motion ponašanje.

### Govor i device capability probe

`probe()` vraća `available | permissionRequired | unavailable | degraded`, razlog i tačne mogućnosti. Za govor sačuvati requested/resolved locale, dostupnost engine-a i lokalnog modela; Serbian Latin transcript normalizovati samo za parser, original pokazati korisniku. Android [SpeechRecognizer.checkRecognitionSupport/isOnDeviceRecognitionAvailable](https://developer.android.com/reference/android/speech/SpeechRecognizer) i Apple [supportedLocales/isAvailable](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportedlocales%28%29) opravdavaju runtime proveru: podržan jezik ne garantuje trenutnu dostupnost ili offline rad. TTS glas proveriti odvojeno, ne prećutno zameniti engleskim. Ne obećavati srpski na svim platformama; ako nema odgovarajućeg engine-a ostaju kucanje i velika dugmad.

Device probe slojevi: platform adapter postoji → dozvola → Bluetooth uključen/servis spreman → transport scan sa ograničenim rokom → odabran model/firmware/protocol → karakteristike ili SDK handshake → podržane komande/jedinice → sveže validno očitavanje. Ime uređaja samo nije capability. `DeviceCapabilities` navodi readWeight/readCore/readAmbient/tare/setTemperature/setMode, unit/range, freshness policy i poslednji razlog neuspeha. `Reading` uvek ima jedinicu, device key, monotonic vreme prijema, optional sequence i quality; reset/reconnect ne sme izmešati sekvence različitih sondi. Stream se gasi na cleanup, reconnect je ograničen/backoff i nikad ne vraća staru write komandu.

Za vagu i termometar ručni unos radi bez naloga dobavljača/BLE i jasno je označen kao ručni. Očitavanje ne ažurira automatski ostavu i ne potvrđuje potrošnju ili bezbednost hrane. Za rernu se prvo prikazuju ručna uputstva; zvanični [capabilities](https://developer.smartthings.com/docs/devices/capabilities/capabilities-reference) i [device command API](https://developer.smartthings.com/docs/service-integrations/control-devices) su samo moguća integraciona osnova. Svaki write traži svež preview, potvrdu i proveren readback. Transport accepted nije dokaz dostignute temperature. Komande nisu offline outbox operacije; ne izvršavaju se po povratku mreže. Remote start/preheat nije u prvom pilotu.

## Plan po funkciji

Sledeći kriterijumi su **planirane provere**, nisu rezultati izvršenih testova. Detalji se podudaraju sa mašinski čitljivim manifestom. Putanje u postojećem stanju su pregledane u Tavli baseline-u.

### F008 — Režim kuvanja

**Faza:** P1. **Zavisnosti:** G-SYNC, G-STEP, G-LIFECYCLE.

**Postojeće stanje:** lib/features/recipes/recipe_view.dart: RecipeView.build samo ispisuje sastojke i numerisane string korake. lib/features/recipes/recipe_detail_screen.dart: RecipeDetailScreen koristi KeepScreenOnScope; lib/features/recipes/keep_screen_on.dart: KeepScreenOn čuva izbor u AppSettings. lib/features/planning/meal_entry_detail.dart: MealEntryDetail prikazuje odobreni snapshot; nema cooking session modela u lib/data/database.dart.

**Ugovor i predložena izmena:**

- CookingSession {id,userId,householdId,recipeId?,mealEntryId?,recipeSnapshot,servings,status,currentStepId,checkedIngredientIds,completedStepIds,startedAt,finishedAt?}; snapshot je nepromenljiv tokom sesije. Sesija je lična; referencirani recept ostaje kućni.
- Novi cooking controller koristi postojeće RecipeView/formatere, route i ScreenWakeLock interfejs; dugmad Dalje, Nazad, Završi kuvanje; završetak eksplicitno nudi setCooked, čekiranje ništa ne troši iz ostave.

**Male vertikalne celine:**

1. Legacy snapshot adapter i state machine sa testovima; jedna sesija iz recepta bez upisa u plan.
2. Persistirana lična sesija sa checklistom i nastavkom offline; ekran telefon/rail.
3. Ulaz iz MealEntryDetail i eksplicitni završetak kroz postojeći MealPlanRepository.setCooked; lifecycle i wakelock regresija.

**Merljivi kriterijumi prihvatanja:**

1. Čekiranje koraka/sastojka ne menja Recipe, PantryItems ni ShoppingContributions.
2. Izmena biblioteke tokom kuvanja ne menja snapshot sesije; ponovni start daje novu sesiju.
3. Izlazak/odjava oslobađaju wake lock; povratak ga traži samo ako je izbor uključen i cooking ekran vidljiv.

**Konkretna verifikacija:**

1. Widget test 390x844 i 1280x800: čekiraj, izađi, nastavi; uporedi recept i ostavu pre/posle.
2. Fake repository: dvostruki tap Završi pravi jedan završetak; plan nije skuvan pre potvrde.
3. Proširiti test/features/recipes/keep_screen_on_test.dart; uređaj: background/resume, OS odbijanje lock-a, navigacija i reduced motion.

### F009 — Više imenovanih tajmera

**Faza:** P1. **Zavisnosti:** F008, G-LIFECYCLE, G-SYNC.

**Postojeće stanje:** lib/app/animations/egg_timer.dart: EggTimer je vizuelna komponenta; demo odbrojavanje je u lib/features/settings/animations_gallery_screen.dart. Nema domena ni persistiranih kuhinjskih tajmera u lib/data/database.dart. lib/app/app.dart: _onResume obnavlja auth i sync, ne tajmere.

**Ugovor i predložena izmena:**

- CookingTimer {id,sessionId,stepId?,label,durationMs,remainingAtCheckpointMs,state,generation,ownerDeviceId}; operacije start/pause/resume/cancel/acknowledge su idempotentne i po ID-u.
- TimerClock vraća continuous monotonic elapsed + boot identity; TimerNotificationAdapter raspoređuje lokalni alarm sa timerId/generation. UTC checkpoint služi oporavku i prikazu, ne odbrojavanju u istoj boot sesiji.

**Male vertikalne celine:**

1. Dva nezavisna foreground tajmera i fake monotonic clock.
2. Checkpoint, pauza, nastavak posle process death u istoj boot sesiji; OS alarm adapter i provera dozvola.
3. Boot/clock-discontinuity stanje i prikaz ograničenja; real device zaključavanje, Doze, force stop i reboot matrica.

**Merljivi kriterijumi prihvatanja:**

1. Za A=60 s i B=90 s, posle 20 s A=40/B=70; otkazivanje A ostavlja B=70.
2. Promena zidnog sata +2 h u istoj boot sesiji ne menja preostalo vreme.
3. Ponovljen resume i zakašnjeli callback stare generation ne emituju dupli alarm; nijedan UI tick nije izvor istine.
4. Bez dozvole prikazati Obaveštenja nisu dostupna; nakon reboot-a bez pouzdanog kontinualnog vremena prikazati Proveri tajmer umesto izmišljene tačnosti.

**Konkretna verifikacija:**

1. Domain test sa fake continuous clock: sleep +30 s, wall jump, pause/resume, istovremeni rokovi, negativno vreme clamp na nulu.
2. Device test Android/iOS: lock, background, kill, force stop, reboot, ugašene notifikacije; izmeriti odstupanje i zabeležiti model/OS.
3. Dva naloga/uređaja: sync checkpoint ne zakazuje drugi lokalni alarm; odjava uklanja pending zahteve.

### F016 — Glasovni unos nabavke na srpskom

**Faza:** P2. **Zavisnosti:** G-SPEECH, G-SYNC.

**Postojeće stanje:** lib/features/shopping/shopping_list_view.dart je postojeći UI nabavke; lib/data/shopping_repository.dart: ShoppingRepository.addManual(listId,name,quantity,unit,category) već piše stavku i outbox atomarno. pubspec.yaml nema speech adapter.

**Ugovor i predložena izmena:**

- SpeechInput.probe(locale) -> SpeechCapability {requestedLocale,resolvedLocale,recognitionAvailable,onDeviceAvailable,permission,reason}; transcribe vraća transcript/final bez čuvanja audio snimka.
- ShoppingVoiceDraft {transcript,name,quantity?,unit?,unresolvedTokens}; deterministički parser srpskih brojeva/jedinica, pregled i izmena pre jednog poziva addManual. Nejasno ne pretvarati u potvrđenu količinu.
- F002 je opciona normalizacija potvrđenih sinonima; osnovni voice draft ne čeka taj rečnik.

**Male vertikalne celine:**

1. Parser tekstualnog transkripta i draft pregled koriste isti addManual kao kucanje.
2. Android capability + mikrofon + push-to-talk; fallback na tekst.
3. iOS/macOS probe i stvarni srpski corpus; objaviti samo platforme/locale kombinacije koje prođu.

**Merljivi kriterijumi prihvatanja:**

1. Dodaj dva litra mleka daje draft mleko,2,l; bez Potvrdi nema reda/outbox-a.
2. Isti final callback dva puta + jedan tap potvrde daju jednu stavku; partial rezultat ne upisuje.
3. Odbijena dozvola/nepodržan srpski/offline bez lokalnog modela ostavljaju kucanje upotrebljivim i pokazuju razlog.

**Konkretna verifikacija:**

1. Parser fixtures: dva litra, 1,5 kg, pola kilograma, bez količine i dvosmislene reči; porediti sa unapred navedenim draftom.
2. Fake speech stream partial/final/error/cancel + repository call count.
3. Fizički uređaji sr-RS/sr-Latn-RS kako ih platforma vrati, airplane mode i odbijene dozvole; ne pretpostaviti srpsku podršku.

### F028 — Veze sastojaka i koraka

**Faza:** P2; G-STEP minimalni adapter potreban u P1. **Zavisnosti:** G-SYNC, G-STEP, G-FORMAT-COORDINATION.

**Postojeće stanje:** lib/domain/recipe.dart: Ingredient nema id, Recipe.steps je List<String>. lib/domain/shopping_source.dart: RecipeSnapshot.fromJson takođe čita string korake. lib/data/recipe_repository.dart: _toCompanion/_fromRow serijalizuju JSON; lib/sync/entities.dart: RecipeEntity prenosi ingredients/steps. Pozicioni indeksi nisu bezbedni pri reorder-u.

**Ugovor i predložena izmena:**

- Proširiti postojeći Recipe/RecipeSnapshot sa verzionisanim RecipeStep {id,text,ingredientUses,timerSuggestions?,ovenSetting?}; Ingredient dobija stabilan lokalni UUID u receptu. IngredientUse {ingredientId,amount?,unit?,usageNote?} referencira postojeći sastojak.
- Legacy string liste čitati preko adaptera; ID-jeve jednom dodeliti i persistirati pri migraciji, nikad nasumično pri svakom renderu. Ne uvesti drugu biblioteku recepata. Nepovezan korak prikazuje pun spisak; automatske veze samo predlog za potvrdu.
- F022/F084 su partneri za koordinaciju formata i validatora, ne preduslovi koji blokiraju ručno povezivanje. Minimalni G-STEP adapter ne zahteva kompletnu F028 funkciju.

**Male vertikalne celine:**

1. Definisati v2 JSON i kompatibilan legacy reader za recipe/version/plan/preparation snapshot; round-trip fixture.
2. Editor ručnih veza i prikaz količine uz korak; reorder/delete/undo.
3. AI/import/export adapteri i rolling-client guard; potvrđeni snapshotovi ne menjaju se retroaktivno.

**Merljivi kriterijumi prihvatanja:**

1. Reorder sastojaka/koraka čuva veze po ID-u; uklanjanje daje vidljiv unresolved link i zahteva potvrdu.
2. Brašno 500 g podeljeno 300+200 g prikazuje obe upotrebe; 600 g ukupno se označava kao konflikt, ne menja tiho recept.
3. Recept v1 ostaje čitljiv sa identičnim tekstom i količinama; nepoznata raspodela ne izmišlja se.

**Konkretna verifikacija:**

1. Round-trip svi serializer-i: Recipe.toJson/fromJson, RecipeSnapshot, prethodne verzije, drift i SyncEntity.
2. Fixtures sa duplim nazivima, ponovljenim korakom, reorder, brisanjem i restore; veze ne prelaze na drugi sastojak.
3. Dva klijenta različitih schema: stariji ne sme upisom string liste obrisati v2 metapodatke; testirati zabranu pisanja ili server verzioni gate.

### F029 — Mediji uz korak

**Faza:** P3. **Zavisnosti:** F028, F023, F065, G-SYNC.

**Postojeće stanje:** Recipe.imagePath u lib/domain/recipe.dart predstavlja jednu sliku; lib/features/recipes/recipe_photo.dart: RecipePhoto i lib/data/recipe_photo_store.dart rade sa fotografijom recepta. lib/sync/photo_sync.dart i lib/sync/entities.dart: photoLocalPath koriste recipe_photos; nema per-step video ugovora.

**Ugovor i predložena izmena:**

- StepMedia {id,stepId,kind,storageKey?,externalUrl?,caption,altText,provenance,rights,contentHash,mime,byteLength,durationMs?}; odvojiti dish/document/step u media contract-u sa streamom F.
- Prvo sopstvena fotografija u privatnom storage-u i offline cache; potom kratak video uz vidljiv download/veličinu. Spoljni video je link sa izvorom, ne kopirani fajl; nema automatskog preuzimanja.

**Male vertikalne celine:**

1. Step photo upload + preview + lokalni thumbnail bez menjanja recipe image.
2. Privatne politike, retry/outbox i brisanje bez orphan fajlova.
3. Video capability/codec probe, ograničenje trajanja/veličine u spec-u i opcioni predownload.

**Merljivi kriterijumi prihvatanja:**

1. Offline korak ostaje čitljiv kada medij nije preuzet; objašnjenje Medij nije dostupan.
2. Drugi nalog van domaćinstva ne može preuzeti privatni fajl; promena recepta ne prevezuje medij na drugi step.
3. Nema autoplay zvuka; alt tekst i caption su dostupni; otkazivanje upload-a ne ostavlja referencu na nepostojeći fajl.

**Konkretna verifikacija:**

1. Fake PhotoRemote: prekid veze, dupli upload retry, uklanjanje i ponovni download.
2. Lokalni Supabase pgTAP/storage test sa dva naloga i pripadnošću; provera media ownership pri promeni step-a.
3. Widget slow/missing cache, video unsupported codec, telefon/wide; real device memorija i lifecycle player dispose.

### F047 — Dnevnik kuvanja

**Faza:** P1. **Zavisnosti:** G-SYNC, F008.

**Postojeće stanje:** lib/data/database.dart: Ratings ima recipeId,stars,isComfortFood,comment,cookedAt,userId, ali nema cooking snapshot/result/photo. RecipeVersion u lib/domain/recipe_version.dart je stanje pre izmene, ograničeno na 30 verzija u RecipeRepository.maxVersions; nije dnevnik.

**Ugovor i predložena izmena:**

- CookingLog {id,userId,householdId,sessionId?,recipeId?,mealEntryId?,recipeSnapshot,servings,cookedAt,result,note,photoRefs,timingSummary?}; lični vlasnik, read/write samo vlasniku u prvoj verziji.
- Ratings ne duplirati: dodati optional cookingLogId uz postojeće polje ocene i definisati jedan autoritativni rezultat. Stare ocene ostaju ocene; ne predstavljati ih kao potpuno dokumentovano kuvanje. Brisanje recepta ne briše lični log bez eksplicitne odluke korisnika.

**Male vertikalne celine:**

1. Ručni log bez sesije i slika: datum, rezultat, napomena, snapshot.
2. Završetak sesije pravi najviše jedan log; optional veza na postojeću ocenu i plan.
3. Privatna fotografija i uredan delete/export; legacy rating prikaz sa jasnim poreklom.

**Merljivi kriterijumi prihvatanja:**

1. Dva kuvanja istog recepta daju dva zapisa sa sopstvenim datumima; edit/restore recepta ne menja log.
2. Offline save plus retry čuva jedan ID; novi uređaj preuzima isti zapis.
3. Lična beleška nije vidljiva drugom članu po default-u; ne troši se ostava prilikom save-a.

**Konkretna verifikacija:**

1. Repository fake clock i outbox rollback; dupli completion, stara ocena bez sessionId, obrisan recept.
2. Dva naloga + household peer RLS test: privatnost i grantovi.
3. UI ručni unos/prošlost, photo failure, offline restart; regression RecipeRepository.delete i setCooked.

### F051 — Temperature i režim rerne

**Faza:** P2. **Zavisnosti:** G-STEP.

**Postojeće stanje:** lib/domain/recipe.dart: Recipe.steps je tekst; nema strukturisanog oven mode ili jedinice temperature. RecipeView prikazuje tekst bez konverzije. lib/domain/shopping_demand.dart normalizuje mere sastojaka, nije temperaturni model.

**Ugovor i predložena izmena:**

- OvenSetting {sourceValue,sourceUnit,celsius,mode:static|fan|grill|unknown,confirmedByUser}; izvorna vrednost ostaje očuvana. Čista funkcija temperature conversion; režim nije isto što i jedinica.
- UI prikazuje izvor i opcionu konverziju; ventilator/statički režim se ne preračunava bez eksplicitnog izbora i prikaza promene. Parsiranje teksta daje samo draft.

**Male vertikalne celine:**

1. Pure conversion + value validation i prikaz uz tekst legacy koraka.
2. Ručno strukturisanje oven setting-a i source provenance.
3. Predlog iz parsera uz potvrdu i ugovor za F078.

**Merljivi kriterijumi prihvatanja:**

1. 180 °C prikazuje 356 °F; 350 °F = 176.666… °C, prikaz 177 °C uz očuvan original.
2. Prelaz °C/°F ne menja fan/static; nepoznat režim ostaje Nije naveden.
3. Negativna/ne-finite temperatura ili van opsega izabranog uređaja ne može se poslati.

**Konkretna verifikacija:**

1. Unit test 0/32,100/212,180/356 i round-trip tolerancija 1e-9; zaokružiti samo UI.
2. Parser fixtures 180°C ventilator, 350 F, broj bez jedinice i grill bez temperature.
3. Widget potvrda izmene, očuvan original u snapshot-u i export round-trip.

### F053 — Glasovno vođenje kuvanja

**Faza:** P2. **Zavisnosti:** F008, F009, F016, G-SPEECH.

**Postojeće stanje:** RecipeView nema aktivni korak ni govor. pubspec.yaml nema speech/TTS zavisnost. lib/features/recipes/keep_screen_on.dart je postojeći screen-only wake lock; ne održava mikrofon ili background izvršavanje.

**Ugovor i predložena izmena:**

- CookingSpeechController koristi isti SpeechInput kao F016, ali zasebnu gramatiku Command {next,previous,repeat,startTimer,pauseListening}; SpeechOutput.probe(sr) proverava TTS voice odvojeno od ASR.
- Push-to-talk, vidljiv indikator slušanja i ručna dugmad; TTS pauzira ASR da sopstveni glas ne postane komanda. Start timer bez jasnog trajanja/koraka otvara potvrdu; glas nikad ne šalje komande rerni.

**Male vertikalne celine:**

1. Tekstualne command fixtures i controller nad cooking state machine.
2. Srpski TTS capability + ponovi; nezavisni fallback bez TTS.
3. Push-to-talk ASR, echo suppression, dupli callback i lifecycle otkazivanje.

**Merljivi kriterijumi prihvatanja:**

1. Sledeći korak pomera tačno jedan korak; ponovi ne menja stanje.
2. Pokreni tajmer uz dve moguće vrednosti pita koju; final callback replay ne pravi dva tajmera.
3. Odlazak u background zaustavlja snimanje; ručna navigacija radi bez dozvola i bez mreže.

**Konkretna verifikacija:**

1. Fake speech/TTS loopback: dok se čita nema prijema komandi; generation/session token odbacuje stari rezultat.
2. Corpus komandi: dijakritici, buka, prekid, nepoznata komanda, poslednji korak i nedostajući timer duration.
3. Android/iOS/macOS probe na uređaju: locale/voice, audio interruption i hands busy; bez tvrdnje o stalnom slušanju u pozadini.

### F054 — Lično stvarno vreme pripreme

**Faza:** P2. **Zavisnosti:** F008, F047, F009.

**Postojeće stanje:** Recipe.prepMinutes u lib/domain/recipe.dart je jedan opcioni broj; RecipeSnapshot ga kopira. Nema aktivnih intervala ili ličnih agregata u lib/data/database.dart. Ratings.cookedAt je datum, ne trajanje rada.

**Ugovor i predložena izmena:**

- CookingActivityInterval {id,sessionId,startElapsed,endElapsed?,kind:active|paused|unclassified,bootId}; zbir aktivnih intervala odvojiti od ukupnog trajanja i vremena čekanja.
- PersonalTimingSummary grupisati po userId + recipe fingerprint + servings band + equipment; tek od 3 potvrđene uporedive sesije prikazati min/max i N. Background interval je unclassified dok ga korisnik ne razvrsta.

**Male vertikalne celine:**

1. Ručno Počni rad/Pauza i monotonic interval tests.
2. Resume review neklasifikovanih intervala i čuvanje uz log.
3. Agregat 3+ potvrđene sesije, raspon i izuzimanje nepotpunih.

**Merljivi kriterijumi prihvatanja:**

1. Rad 10 min, pauza 5, rad 7 daje aktivno 17 i ukupno 22 min.
2. Potvrđene sesije 17,20,25 min prikazuju 17–25 min (3 kuvanja); sa 2 nema ličnog raspona.
3. Reboot/neklasifikovan background ne ulazi u aktivno vreme; promenjene porcije/oprema ostaju zasebna grupa.

**Konkretna verifikacija:**

1. Fake continuous clock sa wall-clock skokom i preklapanjem intervala; nijedan interval se ne broji dvaput.
2. Query fixtures različitih users/fingerprints/servings i delete log invalidation.
3. Device background/resume/process death + ekran za potvrdu intervala; ne porediti vreme UI tick-ova.

### F055 — Pomoć o tekućem koraku

**Faza:** P3. **Zavisnosti:** F008, F028, G-AI.

**Postojeće stanje:** lib/ai/recipe_ai.dart: RecipeAI.refine pravi novi Recipe; lib/features/recipes/recipe_chat_screen.dart je uređivanje recepta, ne privremena cooking pomoć. lib/ai/ai_router.dart: AIRouter.run već obezbeđuje fallback i JSON parse/retry.

**Ugovor i predložena izmena:**

- CookingHelpAI.ask({snapshot,currentStepId,confirmedConstraints,question}) -> StepHelp {answerSr,clarification?,limits}; koristiti AIRouter i strict JSON parser koji baca FormatException.
- Odgovor ostaje u sesiji; nema RecipeRepository.update, promene ograničenja ili device komandi. Budući trajni izmeni tok mora zasebno kroz postojeći preview/refine. Šalju se samo potrebni podaci, bez BLE identifikatora/audio/log fotografija.

**Male vertikalne celine:**

1. Context builder + JSON parsing tests i fake router.
2. Pitanje/odgovor u cooking ekranu bez trajne izmene.
3. Error/retry/cancel kada se promeni sesija ili korak; prikaz originalnog koraka uz odgovor.

**Merljivi kriterijumi prihvatanja:**

1. Prompt sadrži tačan snapshot i tekući korak, ne kasnije izmenjen recept biblioteke.
2. Nijedan uspeh/greška help-a ne pravi recipe version, outbox izmenu ili device write.
3. Offline/pružalac nedostupan prikazuje Pomoć trenutno nije dostupna; cooking navigation/timers nastavljaju.

**Konkretna verifikacija:**

1. Fake ChatClient hvata kontekst; malformiran JSON, fallback exhaustion i format retry.
2. Spy RecipeRepository/oven adapter potvrđuje nula write poziva.
3. Late response za korak A posle prelaska u B označiti odgovor za A ili odbaciti; odjava briše transient context.

### F076 — Kompatibilna Bluetooth vaga

**Faza:** P3 conditional. **Zavisnosti:** G-DEVICE, G-ACAIA-LICENSE, F028, F074.

**Postojeće stanje:** pubspec.yaml nema BLE/scale zavisnost; lib/domain/shopping_demand.dart ima normalizeUnit/toMicros i kompatibilne grupe količina. Nema device adapters u lib/. Acaia MainActivity.onWeightEvent pokazuje masu i jedinicu, a pravi SDK je app/libs/acaiaSDKAndroid-release.aar sa custom licencom.

**Ugovor i predložena izmena:**

- ScaleAdapter.probe/connect/read/disconnect -> DeviceCapabilities i WeightReading {value,unit,receivedElapsed,deviceKey,stable:bool?,sequence?}; preciznost/stabilnost mogu biti unknown. Normalizovati samo potvrđenu masu u grams/micros.
- Manuelni target/reading rade bez BLE; potvrda koristi reading tek kada je fresh. Tare je zasebna dostupna komanda sa potvrdom; nije automatski subtraction iz F074. Acaia implementacija je pravni/SDK gate, bez dekodiranja AAR-a.

**Male vertikalne celine:**

1. Fake/manual adapter i poređenje target-a sa masom sastojka.
2. Proveriti aktuelnu SDK licencu, dozvole i test uređaj/model/firmware; Android bridge samo nakon gate-a.
3. Fizička validacija, disconnect/stale/reconnect i iOS/macOS feasibility posebno.

**Merljivi kriterijumi prihvatanja:**

1. Target 500 g, reading 0.4 kg daje nedostaje 100 g; 1 oz = 28.349523125 g; zapremina l ne poredi se sa masom bez potvrđene gustine.
2. Nepoznat unit, disconnected ili staro očitavanje ne dobija status dostignut cilj.
3. Nepodržan model i odbijena dozvola otvaraju ručni unos; nijedna vaga nije podržana samo zato što BLE scan vidi ime.

**Konkretna verifikacija:**

1. Adapter contract fixtures: g/kg/oz, negativna masa, overload, NaN, out-of-order i stable unknown; freshness fake clock.
2. Fizički model/firmware i poznati tegovi; meriti odstupanje i zakasnela očitavanja bez opšteg obećanja tačnosti.
3. Lifecycle scan timeout, reconnect, Bluetooth off, odjava i dispose release; testirati moderni Android permission flow nezavisno od starog primera.

### F077 — Kompatibilni termometar

**Faza:** P3 conditional. **Zavisnosti:** G-DEVICE, F009, F051.

**Postojeće stanje:** Nema BLE thermometer ili temperature reading modela u Tavli. Combustion Android DeviceManager.probeFlow/connect i ProbeTemperatures.coreTemperatureCelsius razlikuju fizičke/virtuelne senzore; iOS Device.updateDeviceStale koristi 15 s timeout. To nije dokaz podrške Flutter/macOS aplikacije.

**Ugovor i predložena izmena:**

- ThermometerAdapter -> TemperatureReading {celsius,sensorRole,probeKey,receivedElapsed,sequence?,quality}; DeviceCapabilities navodi readCore/readAmbient/stream, model i firmware. Biranje sonde i role pre alarma.
- TemperatureTarget {id,sessionId,probeKey,role,thresholdC,direction,hysteresisC,armed}; alarm na prelasku svežih uzoraka, dedupe; prekid očitavanja prikazati kao Veza prekinuta, ne kao nastavak merenja.
- Prvi adapter samo očitavanje potvrđenog Combustion modela; nema automatskog kuvanja, procene bezbednosti hrane ili upravljanja drugim uređajem.

**Male vertikalne celine:**

1. Manual/fake očitavanje + target crossing i stale state.
2. Android native SDK bridge sa lifecycle ownership i senzor role mapping.
3. iOS bridge i fizički background alarm test; macOS ostaje unavailable dok se posebno ne potvrdi.

**Merljivi kriterijumi prihvatanja:**

1. Target 75 °C; 74,75,76 emituje jedan alarm; ponovljena sekvenca i 75.1 ne stvaraju nove.
2. Staro očitavanje i pogrešna sonda/ambient senzor ne aktiviraju core target.
3. Nestanak novih uzoraka prelazi u stale najkasnije 15 s + jedan UI tick u prvoj politici; manual entry je jasno označen.

**Konkretna verifikacija:**

1. Fake streams: 8 senzora i promena virtualCoreSensor, nevalidni paketi, out-of-order, disconnect/reconnect, reset alarm.
2. Known temperature reference/test probe simulator bez pokretanja upstream app-a u ovoj fazi; implementacija kasnije potvrđuje real hardware.
3. Real Android/iOS lock/background/permission revoked/Bluetooth off; u stanju bez background stream-a ne obećavati obaveštenje.

### F078 — Slanje postavki pametnoj rerni

**Faza:** P3 conditional. **Zavisnosti:** G-DEVICE, G-OVEN-API, F050, F051.

**Postojeće stanje:** Tavli nema oven network adapter, autorizaciju proizvođača ili strukturisane oven settings; steps su tekst. SmartThings javni capability API opisuje komande, ali dostupnost konkretne rerne/regiona i remote-enable nije utvrđena.

**Ugovor i predložena izmena:**

- OvenAdapter.probe(deviceId) -> capabilities {setTemperature,setMode,temperatureUnit,range,supportedModes,remoteEnabled,reachable,reason}; prepare(setting) -> CommandPreview; send(preview,userConfirmation) -> CommandReceipt {requestId,acceptedAt,observedState?,status}.
- Ručno podešavanje ostaje osnovni tok. Samo aktuelna potvrda uređaja/režima/temperature šalje komandu; timeout je unknown, ne uspeh. Bez auto-retry van online sesije; nijedna komanda kroz Supabase outbox, voice ili AI. Prva verzija ne uključuje remote start/preheat.

**Male vertikalne celine:**

1. Manual preview koji prikazuje uređaj, režim, temperaturu i source; fake adapter.
2. Sandbox zvaničnog API-ja i eligibility/OAuth/token isolation provera bez pravih ključeva u istraživanju.
3. Jedan potvrđeni model/region sa command/readback i eksplicitnim klikom; ostalo unsupported.

**Merljivi kriterijumi prihvatanja:**

1. Bez supportedModes ili temperature range nema slanja; fan nije tiho mapiran na static.
2. Otkazivanje potvrde daje nula komandi; retry posle timeout-a zahteva novu proveru stanja i novi klik.
3. API accepted nije isto što i uređaj postavljen: prikaz Poslato / Potvrđeno / Ishod nepoznat odvojeno.
4. Offline/revoked/remote-disabled prikazuje ručna uputstva; reconnect ne izvršava staru komandu.

**Konkretna verifikacija:**

1. Fake API: 401,403,429,timeout, accepted bez readback-a, različit unit, zastareo preview, dupli tap.
2. Contract test official capabilities + allowed modes/ranges; lokalna fiktivna OAuth stanja, bez produkcije.
3. Fizička rerna samo u implementacionom pilotu sa potvrdom; zabeležiti model/firmware/region i remote-enable ponašanje.

### F081 — Put učenja kuvanja

**Faza:** P3. **Zavisnosti:** F047, F082, G-SYNC.

**Postojeće stanje:** lib/domain/recipe.dart sadrži Recipe/Ingredient, lib/data/database.dart nema skill/curriculum/progress tabelu. RecipeView i budući cooking log daju moguću osnovu praktičnog zadatka; nema dokaza o isporučenom učenju.

**Ugovor i predložena izmena:**

- Curated Skill {id,revision,titleSr,prerequisiteIds,lessonSr,taskSr,rubric,glossaryIds,recipeSuggestions}; SkillAttempt {id,userId,skillId,skillRevision,cookingLogId?,evidenceNote,criterionChecks,result,completedAt?}.
- Sopstveni urednički sadržaj; napredak znači korisnik potvrđene kriterijume, ne sertifikat ili dokaz stručnosti. Kurikulum radi offline; reference na spoljne škole samo link, bez kopiranja njihovog sadržaja.

**Male vertikalne celine:**

1. Jedna sopstvena lekcija + proverljiv zadatak/rubrika i ručni pokušaj.
2. Verzionisano lokalno izdanje sadržaja i lični progress/outbox.
3. Preduslovi i povezivanje sa cooking log-om; opcione recipe suggestions bez preusmeravanja aktivne sesije.

**Merljivi kriterijumi prihvatanja:**

1. Za zadatak ravnomerno iseckati 10 komada korisnik proverava objavljenu rubriku; samo završavanje recepta ne označava veštinu kao stečenu.
2. Promena revizije lekcije čuva pokušaj stare revizije; reset pokušaja ne briše cooking log.
3. Drugi nalog ne vidi lični napredak; offline završetak jednom se sinhronizuje.

**Konkretna verifikacija:**

1. DAG fixtures: ciklus se odbija; nedostajući prerequisite ne otključava naredni nivo.
2. Repository migration, user-scope RLS i dva naloga; idempotentni completion.
3. Widget offline lekcija, dostupnost teksta/tastature i rubrika; urednička provera originalnog srpskog sadržaja.

### F082 — Kulinarski rečnik

**Faza:** P2. **Zavisnosti:** G-CONTENT.

**Postojeće stanje:** RecipeView u lib/features/recipes/recipe_view.dart koristi Text(step), nema definicije/linkove pojmova. Postojeći ingredientKey/normalizeUnit u lib/domain/shopping_demand.dart rešavaju identitet namirnice i mere, ne stručne kulinarske pojmove.

**Ugovor i predložena izmena:**

- GlossaryEntry {id,revision,termSr,aliases,definitionSr,exampleSr,relatedIds,provenance,rights}; kuriran verzionisan lokalni asset, ne AI odgovor.
- Deterministički matcher Unicode/case/word-boundary + najduža fraza; označava poznate pojmove u koraku i otvara accessible sheet bez izmene teksta. Ručna pretraga uvek dostupna; višeznačne termine izabrati, ne nagađati.

**Male vertikalne celine:**

1. Sopstvene definicije za deglazirati/blanširati i offline search.
2. Text span matcher i sheet u RecipeView/cooking ekranu uz accessibility.
3. Verzionisanje/urednička kontrola aliases i povezivanje sa F081.

**Merljivi kriterijumi prihvatanja:**

1. Deglazirati otvara tačan srpski opis i primer bez mreže; close vraća isti korak/scroll/timer.
2. Termini ne hvataju podniz unutar druge reči; duža fraza ima prednost i nema preklapajućih linkova.
3. Izvor/rights postoje za svaki unos; nema kopiranja školskog/proprietary teksta.

**Konkretna verifikacija:**

1. Matcher fixtures dijakritici, različito veliko slovo, interpunkcija, duža fraza, višeznačni alias i nepodudaranje.
2. Widget semantics/tastatura/screen reader, 200% text scale, narrow/wide i active timer bez reset-a.
3. Urednički pregled definicija i sadržaja; integritet glossary ID veza i revizija offline asset-a.

## Upstream dokazi i odluke o preuzimanju

Navedene putanje i simboli pregledani su u lokalnim read-only clone-ovima u `/Users/urosmilutinovic/.cache/tavli-next-sources/E/`. Licenca je pročitana iz fajla; README nije korišćen kao jedini dokaz. Sledeći rezimei su opažanja izvora; Tavli ugovori iznad su naši predlozi.

### kitshn

Repo: [https://github.com/kitshn-app/kitshn](https://github.com/kitshn-app/kitshn); commit `e971bb1e00eaa593b570e9512dee08968b6f70a3`; licenca: **GPLv3 tekst potvrđen; SPDX only/or-later ostaje unknown**.

- [LICENSE](https://github.com/kitshn-app/kitshn/blob/e971bb1e00eaa593b570e9512dee08968b6f70a3/LICENSE) — `GNU GENERAL PUBLIC LICENSE Version 3`: Copyleft; no source copied in this pass.
- [shared/src/commonMain/kotlin/de/kitshn/api/tandoor/model/TandoorStep.kt](https://github.com/kitshn-app/kitshn/blob/e971bb1e00eaa593b570e9512dee08968b6f70a3/shared/src/commonMain/kotlin/de/kitshn/api/tandoor/model/TandoorStep.kt) — `TandoorStep; instructionsWithTemplating; getRawIngredientById`: Step carries ingredient list, time and optional file; templating scales quantities but addresses ingredients by index.
- [shared/src/commonMain/kotlin/de/kitshn/api/tandoor/model/TandoorIngredient.kt](https://github.com/kitshn-app/kitshn/blob/e971bb1e00eaa593b570e9512dee08968b6f70a3/shared/src/commonMain/kotlin/de/kitshn/api/tandoor/model/TandoorIngredient.kt) — `TandoorIngredient; toString; tickedOff`: Ingredient has ID and transient UI check state; scale parameter affects formatted amount.
- [shared/src/commonMain/kotlin/de/kitshn/ui/route/recipe/cook/page/RecipeStep.kt](https://github.com/kitshn-app/kitshn/blob/e971bb1e00eaa593b570e9512dee08968b6f70a3/shared/src/commonMain/kotlin/de/kitshn/ui/route/recipe/cook/page/RecipeStep.kt) — `RouteRecipeCookPageStep; StepBody`: Step screen combines IngredientsList, rich text with timer detection and capability check before launching timer.

**Odluka:** Study behavior only. Independent Dart contracts and implementation; no GPL source, snippets or assets copied.

### acaia_sdk_android

Repo: [https://github.com/acaia/acaia_sdk_android](https://github.com/acaia/acaia_sdk_android); commit `8dc977e8123eb5e13b5370b3f357e6af082c79e0`; licenca: **LicenseRef-Acaia-Custom**.

- [LICENSE](https://github.com/acaia/acaia_sdk_android/blob/8dc977e8123eb5e13b5370b3f357e6af082c79e0/LICENSE) — `permission text`: Binary unmodified use only; reverse engineering forbidden; examples reusable with restrictions; no sublicensing/selling files and paid/subscription attribution/notification conditions.
- [app/src/main/java/co/acaia/android/acaiasdksampleapp/MainActivity.java](https://github.com/acaia/acaia_sdk_android/blob/8dc977e8123eb5e13b5370b3f357e6af082c79e0/app/src/main/java/co/acaia/android/acaiasdksampleapp/MainActivity.java) — `scanDevice; connectDevice; onWeightEvent; btn_tare onClick`: Scan/service readiness gate; explicit device selection; WeightEvent value + unit; SEND_TARE command. Name-based PEARLS capacity branch is sample behavior, not robust capability proof.
- [app/src/main/java/co/acaia/android/acaiasdksampleapp/AcaiaSDKSampleApp.java](https://github.com/acaia/acaia_sdk_android/blob/8dc977e8123eb5e13b5370b3f357e6af082c79e0/app/src/main/java/co/acaia/android/acaiasdksampleapp/AcaiaSDKSampleApp.java) — `initAcaiaBt; registerUpdateReceiver; updateReceiver.onReceive`: Service initialization and broadcasts mapped to WeightEvent; source itself flags missing unregister.
- [app/libs/acaiaSDKAndroid-release.aar](https://github.com/acaia/acaia_sdk_android/blob/8dc977e8123eb5e13b5370b3f357e6af082c79e0/app/libs/acaiaSDKAndroid-release.aar) — `binary presence only`: Implementation is binary. Not executed, unpacked, decompiled or copied.

**Odluka:** No code or binary copied. Custom license is a release gate; Android sample is architecture evidence only and modern permission/lifecycle behavior requires fresh implementation validation.

### combustion-android-ble

Repo: [https://github.com/combustion-inc/combustion-android-ble](https://github.com/combustion-inc/combustion-android-ble); commit `3ad9b5a8b698e8177c3f9d9ee9026f860784b3a2`; licenca: **MIT**.

- [LICENSE](https://github.com/combustion-inc/combustion-android-ble/blob/3ad9b5a8b698e8177c3f9d9ee9026f860784b3a2/LICENSE) — `MIT grant`: 2021 Combustion copyright; per-file notices also present.
- [combustion-android-ble/src/main/java/inc/combustion/framework/service/DeviceManager.kt](https://github.com/combustion-inc/combustion-android-ble/blob/3ad9b5a8b698e8177c3f9d9ee9026f860784b3a2/combustion-android-ble/src/main/java/inc/combustion/framework/service/DeviceManager.kt) — `initialize; startCombustionService; bindCombustionService; unbindCombustionService; startScanningForDevices; probeFlow; connect; disconnect`: Service-bound lifecycle and flows; ownership/release explicit; not a Flutter adapter.
- [combustion-android-ble/src/main/java/inc/combustion/framework/service/ProbeTemperatures.kt](https://github.com/combustion-inc/combustion-android-ble/blob/3ad9b5a8b698e8177c3f9d9ee9026f860784b3a2/combustion-android-ble/src/main/java/inc/combustion/framework/service/ProbeTemperatures.kt) — `coreTemperatureCelsius; ambientTemperatureCelsius; fromRawData`: 8 Celsius readings; sensor-role selection separate from packet conversion. Guard packet length before decoding in adapter.
- [combustion-android-ble/src/main/java/inc/combustion/framework/service/SensorTemperature.kt](https://github.com/combustion-inc/combustion-android-ble/blob/3ad9b5a8b698e8177c3f9d9ee9026f860784b3a2/combustion-android-ble/src/main/java/inc/combustion/framework/service/SensorTemperature.kt) — `fromRawDataStart; fromRawDataEnd; toRawDataStart; toRawDataEnd`: 13-bit sensor encoding uses 0.1 scale and -20 offset; distinct from multi-sensor 0.05 encoding; do not conflate.
- [combustion-android-ble/src/main/java/inc/combustion/framework/service/DeviceTemperature.kt](https://github.com/combustion-inc/combustion-android-ble/blob/3ad9b5a8b698e8177c3f9d9ee9026f860784b3a2/combustion-android-ble/src/main/java/inc/combustion/framework/service/DeviceTemperature.kt) — `DeviceTemperature`: Marker interface shared by reading types.

**Odluka:** MIT eligible but no Android source copied: bridge/dependencies need separate review; use SDK through explicit adapter after pilot. Conversion model informed by inspected symbols.

### combustion-ios-ble

Repo: [https://github.com/combustion-inc/combustion-ios-ble](https://github.com/combustion-inc/combustion-ios-ble); commit `797416a7944b8f652c7a602981c004703b29c620`; licenca: **MIT**.

- [LICENSE](https://github.com/combustion-inc/combustion-ios-ble/blob/797416a7944b8f652c7a602981c004703b29c620/LICENSE) — `MIT grant`: Full notice retained next to copied complete utility.
- [Sources/CombustionBLE/TemperatureUtilities.swift](https://github.com/combustion-inc/combustion-ios-ble/blob/797416a7944b8f652c7a602981c004703b29c620/Sources/CombustionBLE/TemperatureUtilities.swift) — `fahrenheit(celsius:); celsius(fahrenheit:)`: Small complete utility, Foundation-only import; useful F051 conversion reference.
- [Sources/CombustionBLE/DeviceManager.swift](https://github.com/combustion-inc/combustion-ios-ble/blob/797416a7944b8f652c7a602981c004703b29c620/Sources/CombustionBLE/DeviceManager.swift) — `initBluetooth; connectToDevice; disconnectFromDevice`: Manager controls connection and recurring stale checks.
- [Sources/CombustionBLE/Devices/Device.swift](https://github.com/combustion-inc/combustion-ios-ble/blob/797416a7944b8f652c7a602981c004703b29c620/Sources/CombustionBLE/Devices/Device.swift) — `updateDeviceStale; Constants.STALE_TIMEOUT`: Date-based stale check at 15 seconds; Tavli proposes continuous monotonic freshness instead.
- [Package.swift](https://github.com/combustion-inc/combustion-ios-ble/blob/797416a7944b8f652c7a602981c004703b29c620/Package.swift) — `Package platforms/dependencies`: Declares iOS 13 only; Swift Collections and Nordic DFU dependencies. macOS support is not established.

**Odluka:** Copied TemperatureUtilities.swift and LICENSE verbatim; no whole SDK vendoring, runtime linking, build or execution. Other device behavior is evidence only.

### Stvarno prikupljeni kompletni fajlovi

Samo `TemperatureUtilities.swift` predstavlja preuzet upstream kod: kompletan fajl, bez izmena i sa originalnim MIT zaglavljem/copyright-om. `LICENSE` je takođe kopiran bajt-za-bajt. `PROVENANCE.json` je naš metapodatak sa pinom, svrhom i hash-evima. Nema upstream NOTICE fajla u pregledanom iOS repo-u; to je eksplicitno zabeleženo, umesto izmišljenog NOTICE-a. Utility koristi samo Foundation; nije kopiran ostatak SDK-a ili njegove zavisnosti. Nije povezan sa runtime-om niti izvršen. Naš budući Dart conversion model može imati sopstvenu implementaciju uz potrebnu atribuciju ako adaptira kod.

| Lokalni fajl | SHA-256 |
|---|---|
| `research/reference-code/E/combustion-ios/LICENSE` | `a84ccd0d957a5c48c966a7a5638ca517cdd31a14a56a295f6fec8287396b166e` |
| `research/reference-code/E/combustion-ios/TemperatureUtilities.swift` | `ce069c8441c383fe12becf6df4669f5720d714f48dae104408ad7ef11d610df2` |

Kitshn GPL i Acaia custom izvori nisu kopirani, uključujući snippets, binarne fajlove i assets. Za njih je rezultat obrazac za sopstvenu implementaciju. Posebno: Acaia README javna dostupnost ne znači permissive licencu; uzorak sadrži ograničenja i nije osnov za obećanje komercijalne distribucije. Combustion ceo SDK takođe nije automatski odobren samim kopiranjem jedne MIT alatke: pri integraciji proveriti sve tranzitivne zavisnosti i platform capabilities.

## Migracije, kompatibilnost i integracioni rizici

1. **Recept/snapshot format:** `Recipe`, `RecipeSnapshot`, `RecipeRepository`, `RecipeEntity`, AI prompts/parser, editor i verzije moraju koristiti isti v2 ugovor. Stari `steps.toString()` reader može uništiti structured object; nova verzija mora eksplicitno prepoznati oba formata. Očuvati stare string tekstove i postojeće količine. ID mapiranje jednom i trajno; duplikati naziva nisu isti sastojak. F022 export i F065 backup treba da obuhvate nove veze/medije/log-ove, uz novi format version. Stariji klijent ne sme bez upozorenja pregaziti v2 sadržaj.
2. **Istorija:** potvrđeni planovi/samostalne pripreme ostaju zamrznuti. V1 session-local ID-jevi mogu se povezati sa budućim recipe ID-jevima samo eksplicitnom mapom; ne premeštati stari check state na isti indeks novog recepta. Log snapshot preživljava recipe version pruning. Dogovoriti ponašanje eksplicitnog brisanja recepta i log-a; account deletion mora ukloniti oba.
3. **Skladištenje:** novi user entiteti zahtevaju RLS i eksplicitne grantove, lokalni migration test iz v5 i outbox atomarnost. Photo path mapper sada pretpostavlja `recipe_photos`; step/log mediji zahtevaju dogovoren media ugovor i parent ordering, ne ručno spajanje putanja u widget-u. Privatni URL nije trajni javni link. Proveriti cleanup orphan fajlova.
4. **Lifecycle:** postojeći auth/sync resume ostaje očuvan. Timer alarm, speech microphone, BLE scan/connection i video player imaju zaseban resource owner i cleanup. Screen lock ne obezbeđuje CPU/network/BLE održavanje. Async pozivi se serijalizuju i svaki callback proverava account/session generation.
5. **Govor:** minimalni voice shopping parser ne zavisi od AI-ja niti punog rečnika F002; potvrđeni sinonimi su kasnija opcija. Prepoznavanje jezika, zapis Latin/Cyrillic, broj i jedinica nisu jedan confidence broj. Nejasan tekst ostaje pregledljiv draft. Ako engine šalje audio mrežno, UI mora to znati pre snimanja; ne čuvati audio/transkript u opšte logove.
6. **Uređaji:** Android/iOS imaju različite SDK-je i dozvole; Combustion iOS `Package.swift` navodi samo iOS, pa macOS nije automatski podržan. Acaia primeri nisu dokaz da stare permission/receiver postavke rade na novom Android-u. Za svaku podržanu kombinaciju objaviti vendor/model/firmware/OS/adapter revision, mogućnosti i rezultat probe-a; ostalo je unavailable/manual.
7. **Bezbedan pilot rerne:** command preview sa kratkim rokom, tačnim uređajem i mode/unit/range validacijom; timeout je unknown i nema automatskog ponavljanja. Odobrenje mode/temperature ne uključuje start. Nijedan AI/voice/timer callback ne može proizvesti appliance write.
8. **Sadržaj:** F081/F082 koriste sopstvene uređene definicije/rubrike; linkovanje King Arthur/SideChef nije dozvola za kopiranje lekcija ili videa. Napredak je korisnički self-check, ne obećanje proverene stručnosti. Temperature i procene senzora ne daju automatsku tvrdnju da je hrana bezbedna.

## Otvorena pitanja

- Serbian ASR/TTS availability and offline behavior by actual Android/iOS/macOS model/OS/installed engine are unmeasured; probe and corpus testing required.
- Acaia current commercial eligibility, updated platform SDK terms, supported firmware/model list and iOS/macOS feasibility are unresolved; no binary inspection performed.
- Combustion Flutter bridge, current firmware compatibility, background delivery, battery behavior and macOS support are not verified on devices.
- SmartThings or another oven provider: app registration, OAuth eligibility, regional/model capability exposure and remote-enable restrictions need a separate authorized pilot; no production API used.
- Cross-device timer control policy: proposal is owner-device alarms only; handoff requires explicit transfer and cancellation acknowledgment before enabling another alarm owner.
- Shared schema v2 ownership with streams A/F must be agreed before implementation; old-client write gate needed to prevent silent metadata loss.
- Media upload limits/codec matrix, recipe deletion log retention UX, curriculum content authorship and release acceptance for timing accuracy require feature specs.

## Završna provera istraživanja

- Manifest je parsiran kao JSON; pokrivenost je poređena sa `research/streams.json`, tačno svih 15 E ID-jeva bez duplikata ili tuđih ID-jeva.
- Za četiri repo-a provereni su pinovani commit-i i postojanje svih navedenih putanja/simbola. Za kopirani kod i licencu proverene su SHA-256 vrednosti i bajt-po-bajt jednakost sa pinovanim upstream sadržajem; originalni copyright je ostao očuvan.
- Nisu izvršeni Flutter testovi/analyze/build, upstream programi ili hardware testovi: nema runtime promene za testiranje. Navedeni scenariji su plan verifikacije za implementacione specifikacije, ne tvrdnja o prolasku.
- Završeni artefakti: ovaj izveštaj, manifest i jedan kompletan MIT referentni source uz punu licencu/provenance. Nijedna od 15 funkcija nije ovim radom implementirana. Nema commit-a, push-a ili promene git stanja u ovom streamu.
