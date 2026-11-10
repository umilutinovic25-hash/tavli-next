# Feature Specification: Domaćinstvo — pozivanje, pridruživanje i članovi

**Feature Branch**: `034-household-members` (created from latest `main`)

**Created**: 2026-11-10

**Status**: Draft

**Input**: User description: "UI za domaćinstvo: pozovi, pridruži se, članovi, uloge, napusti i prenos vlasništva, na osnovu postojećih repozitorijuma." (Ovo je funkcija koju `docs/product-design.md` §9 vodi kao 008.)

## Kontekst

Server i klijentski sloj već postoje: pozivnice (pravljenje koda na serveru, lista, poništavanje, iskorišćavanje sa limitom pokušaja), članstvo (uklanjanje člana, napuštanje, prenos vlasništva) i izbor aktivnog domaćinstva po poslednjem pridruživanju (PR #31). Ova specifikacija dodaje ekrane i ono što nedostaje da bi oni radili: čitanje članova sa imenima i osvežavanje naloga posle promene članstva. Ne menja se koji podaci se dele u domaćinstvu.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Vlasnik poziva člana kodom (Priority: P1)

Vlasnik otvori Profil → Domaćinstvo i dodirne „Pozovi člana“. Aplikacija napravi kod i prikaže ga krupno, podeljen u dve grupe od po četiri znaka, sa rokom važenja i brojem preostalih upotreba. Vlasnik kod kopira ili ga deli kroz sistemski meni za deljenje (poruka sa kodom i kratkim uputstvom). Ispod je lista aktivnih pozivnica, a svaku može da poništi.

**Why this priority**: Bez pozivnice niko ne može da se pridruži. To je prvi korak celog deljenja.

**Independent Test**: Vlasnik napravi kod, kod se pojavi u listi aktivnih pozivnica, a posle poništavanja nestaje i više ne može da se iskoristi.

**Acceptance Scenarios**:

1. **Given** vlasnik je na mreži, **When** dodirne „Pozovi člana“, **Then** vidi novi kod od 8 znakova, „Važi do d.m.gggg.“ i „Još 5 upotreba“, a kod je u listi aktivnih pozivnica.
2. **Given** prikazan je kod, **When** dodirne „Kopiraj kod“, **Then** kod (bez razmaka) je u privremenoj memoriji i vidi „Kod je kopiran.“
3. **Given** prikazan je kod, **When** dodirne „Podeli“, **Then** otvara se sistemski meni za deljenje sa porukom koja sadrži kod i uputstvo „Otvori Tavli → Profil → Domaćinstvo → Pridruži se kodom“.
4. **Given** aktivna pozivnica, **When** vlasnik dodirne „Poništi“ i potvrdi, **Then** pozivnica nestaje iz liste, a pokušaj da se iskoristi daje „Kod nije važeći ili je istekao.“
5. **Given** nema mreže, **When** vlasnik dodirne „Pozovi člana“, **Then** vidi „Za ovo je potrebna internet veza.“ i ništa se ne menja.
6. **Given** korisnik je član (nije vlasnik), **When** otvori Domaćinstvo, **Then** ne vidi „Pozovi člana“ ni listu pozivnica.

---

### User Story 2 — Pridruživanje tuđem domaćinstvu kodom (Priority: P1)

Korisnik koji je dobio kod otvori Profil → Domaćinstvo → „Pridruži se kodom“ i unese kod. Pre potvrde vidi kratko objašnjenje: posle pridruživanja aplikacija prikazuje plan, nabavku i ostalo iz zajedničkog domaćinstva, a njegovi dosadašnji podaci ostaju sačuvani u njegovom ličnom domaćinstvu. Posle uspeha aktivno postaje novo domaćinstvo i aplikacija preuzima njegove podatke.

**Why this priority**: To je druga polovina poziva; tek sa njom domaćinstvo zaista postaje zajedničko.

**Independent Test**: Sa važećim kodom korisnik postaje član, ime aktivnog domaćinstva u Profilu se menja i zajednički podaci se pojavljuju posle sinhronizacije, bez ponovnog prijavljivanja.

**Acceptance Scenarios**:

1. **Given** važeći kod, **When** korisnik unese kod i potvrdi, **Then** vidi „Sada si član domaćinstva „{naziv}“.“, „Sada si član domaćinstva.“ (kad naziv još nije poznat jer osvežavanje posle pridruživanja nije uspelo), aktivno domaćinstvo je novo, a podaci zajedničkog domaćinstva se preuzimaju bez ponovne prijave.
2. **Given** kod unet malim slovima, sa razmakom ili crticom, **When** potvrdi, **Then** kod se prihvata kao da je unet tačno.
3. **Given** nevažeći, istekao, poništen ili potrošen kod, **When** potvrdi, **Then** vidi „Kod nije važeći ili je istekao.“ i ostaje u svom domaćinstvu.
4. **Given** previše neuspelih pokušaja, **When** potvrdi, **Then** vidi „Previše pokušaja. Pokušaj ponovo za 10 minuta.“
5. **Given** nema mreže, **When** potvrdi, **Then** vidi „Za ovo je potrebna internet veza.“ i unet kod ostaje u polju.
6. **Given** korisnik je već član tog domaćinstva, **When** iskoristi njegov kod, **Then** ostaje član (bez dupliranja), a to domaćinstvo postaje aktivno.
7. **Given** prazno polje ili kod kraći od 8 znakova, **When** pogleda dugme, **Then** „Pridruži se“ je onemogućeno.

---

### User Story 3 — Pregled članova i uklanjanje člana (Priority: P2)

Na ekranu Domaćinstvo svi članovi vide naziv domaćinstva i listu članova: ime i uloga („Vlasnik“ ili „Član“), a sopstveni red ima oznaku „Ti“. Vlasnik može da ukloni člana uz potvrdu. Imejl adrese drugih članova se ne prikazuju.

**Why this priority**: Korisnik mora da vidi s kim deli podatke i da vlasnik može da ispravi grešku. Ovo nije preduslov za samo pridruživanje.

**Independent Test**: U domaćinstvu sa dva člana oba vide oba imena i uloge. Kad vlasnik ukloni člana, član nestaje iz liste, a uklonjeni korisnik se posle sledećeg osvežavanja vraća u svoje lično domaćinstvo.

**Acceptance Scenarios**:

1. **Given** domaćinstvo sa vlasnikom i članom, **When** bilo ko od njih otvori Domaćinstvo, **Then** vidi oba člana sa imenom i ulogom, a svoj red sa „Ti“.
2. **Given** član nije upisao ime, **When** se prikaže lista, **Then** njegov red glasi „Član bez imena“.
3. **Given** vlasnik, **When** izabere „Ukloni iz domaćinstva“ kod člana i potvrdi, **Then** član nestaje iz liste i vidi „Član je uklonjen.“
4. **Given** uklonjen korisnik, **When** njegova aplikacija sledeći put osveži nalog, **Then** aktivno mu je lično domaćinstvo i ne vidi podatke domaćinstva iz kog je uklonjen.
5. **Given** nema mreže, **When** se otvori Domaćinstvo, **Then** vidi se poslednja poznata lista članova i napomena „Prikazano je poslednje poznato stanje.“; radnje koje menjaju članstvo javljaju „Za ovo je potrebna internet veza.“
6. **Given** korisnik koji nije vlasnik, **When** gleda listu, **Then** nema radnju „Ukloni iz domaćinstva“.

---

### User Story 4 — Napuštanje domaćinstva i prenos vlasništva (Priority: P2)

Član može da napusti domaćinstvo uz potvrdu i tada mu aktivno postaje lično domaćinstvo. Vlasnik ne može da napusti domaćinstvo dok u njemu ima drugih članova; može da prenese vlasništvo izabranom članu i tada sam postaje član.

**Why this priority**: Bez izlaza pridruživanje je jednosmerno; prenos je potreban da vlasnik ne zaključa ostale.

**Independent Test**: Član napusti domaćinstvo i vidi svoje lične podatke. Vlasnik prenese vlasništvo i uloge se zamene kod oba korisnika.

**Acceptance Scenarios**:

1. **Given** član, **When** dodirne „Napusti domaćinstvo“ i potvrdi, **Then** aktivno mu je lično domaćinstvo, vidi svoje podatke i poruku „Domaćinstvo je napušteno.“.
2. **Given** vlasnik u domaćinstvu sa drugim članovima, **When** pogleda radnje, **Then** umesto „Napusti domaćinstvo“ vidi objašnjenje „Pre napuštanja prenesi vlasništvo drugom članu.“
3. **Given** vlasnik, **When** izabere „Prenesi vlasništvo“ kod člana i potvrdi, **Then** taj član postaje „Vlasnik“, a on „Član“, i vidi „Vlasništvo je preneto.“
4. **Given** vlasnik svog jedinog (ličnog) domaćinstva, **When** otvori Domaćinstvo, **Then** nema ni „Napusti domaćinstvo“ ni „Prenesi vlasništvo“.
5. **Given** server odbije radnju (npr. uloga se u međuvremenu promenila), **When** se vrati greška, **Then** korisnik vidi srpsku poruku iz tabele tekstova, lista se osvežava, a stanje u aplikaciji ostaje usklađeno sa serverom.

---

### User Story 5 — Prebacivanje između domaćinstava (Priority: P3)

Korisnik koji je član više domaćinstava (npr. lično i zajedničko) bira koje je aktivno. Podrazumevano je aktivno ono kome se poslednje pridružio. Izbor se pamti na uređaju za taj nalog.

**Why this priority**: Pridruživanje skriva lične podatke iza zajedničkog domaćinstva; bez prebacivanja korisnik do njih dolazi samo napuštanjem. Prve dve priče rade i bez ovoga.

**Independent Test**: Korisnik sa dva članstva izabere lično domaćinstvo, vidi svoje podatke, zatvori i ponovo otvori aplikaciju, i lično domaćinstvo je i dalje aktivno.

**Acceptance Scenarios**:

1. **Given** dva članstva, **When** otvori Domaćinstvo, **Then** vidi „Aktivno domaćinstvo“ sa izborom između njih; uz jedno članstvo izbor se ne prikazuje.
2. **Given** izabrano drugo domaćinstvo, **When** potvrdi, **Then** Plan, Nabavka, Recepti i Ostava prikazuju podatke izabranog domaćinstva posle sinhronizacije.
3. **Given** izabrano domaćinstvo, **When** se aplikacija ponovo pokrene, **Then** ostaje izabrano domaćinstvo.
4. **Given** izabrano domaćinstvo iz kog je korisnik u međuvremenu uklonjen, **When** se nalog osveži, **Then** aktivno postaje poslednje pridruženo od preostalih.
5. **Given** nema mreže, **When** pokuša da prebaci domaćinstvo, **Then** vidi „Za ovo je potrebna internet veza.“

### Edge Cases

- Kod istekne dok ga vlasnik gleda na ekranu: lista ga posle osvežavanja ne prikazuje kao aktivan; pokušaj pridruživanja daje „Kod nije važeći ili je istekao.“
- Korisnik pokuša da iskoristi kod sopstvenog domaćinstva: ništa se ne duplira, ostaje član sa istom ulogom.
- Neusklađene izmene u outbox-u u trenutku promene aktivnog domaćinstva: ostaju vezane za domaćinstvo u kome su napravljene i šalju se tamo; ne prelaze u novo domaćinstvo.
- Dva vlasnikova uređaja istovremeno: posle radnje na jednom, drugi vidi novo stanje pri sledećem otvaranju ekrana ili osvežavanju (bez realtime-a, to je 009).
- Prenos vlasništva korisniku koji je u međuvremenu napustio domaćinstvo: server odbija, korisnik vidi „Taj korisnik više nije član domaćinstva.“ i lista se osvežava.
- Istekla sesija tokom radnje: važi postojeće ponašanje aplikacije za opozvanu sesiju (povratak na prijavu).
- Telefon, široki ekran (rail) i tekst 2×: kod, lista i radnje ostaju čitljivi i dostupni bez horizontalnog skrolovanja.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Profil MUST imati stavku „Domaćinstvo“ sa nazivom aktivnog domaćinstva kao podnaslovom; otvara ekran Domaćinstvo.
- **FR-002**: Ekran Domaćinstvo MUST prikazati naziv aktivnog domaćinstva, sopstvenu ulogu i listu članova (ime ili „Član bez imena“, uloga, oznaka „Ti“).
- **FR-003**: Lista članova MUST biti vidljiva bez mreže kao poslednje poznato stanje, sa napomenom kad nije osvežena sa servera.
- **FR-004**: Drugi članovi MUST videti samo ime i ulogu jedni drugih; imejl i ostali podaci profila MUST ostati vidljivi samo vlasniku profila.
- **FR-005**: Samo vlasnik MUST moći da napravi pozivnicu, vidi listu aktivnih pozivnica (kod, rok, preostale upotrebe) i poništi pozivnicu.
- **FR-006**: Prikazan kod MUST biti grupisan 4 + 4 radi čitanja, a kopiranje i deljenje MUST koristiti kod bez razmaka.
- **FR-007**: Deljenje MUST otvoriti sistemski meni za deljenje sa porukom koja sadrži kod i uputstvo za unos.
- **FR-008**: Svaki prijavljen korisnik MUST moći da unese kod; unos MUST prihvatiti mala slova, razmake i crtice.
- **FR-009**: Pre pridruživanja korisnik MUST videti objašnjenje da se prikazuju podaci zajedničkog domaćinstva, a da lični podaci ostaju sačuvani.
- **FR-010**: Posle uspešnog pridruživanja, napuštanja, uklanjanja ili prenosa aplikacija MUST ponovo povući nalog sa servera (ne sme se osloniti na nalog sačuvan na uređaju) i pokrenuti sinhronizaciju za aktivno domaćinstvo.
- **FR-011**: Vlasnik MUST moći da ukloni drugog člana uz potvrdu; ne može ukloniti sebe.
- **FR-012**: Član MUST moći da napusti domaćinstvo uz potvrdu; vlasnik MUST dobiti objašnjenje da prvo prenese vlasništvo kad ima drugih članova.
- **FR-013**: Vlasnik MUST moći da prenese vlasništvo izabranom članu uz potvrdu.
- **FR-014**: Radnje i stavke koje korisnik po ulozi ne sme da koristi MUST biti skrivene, a server MUST ostati konačni čuvar (svako odbijanje se prikazuje porukom).
- **FR-015**: Sve radnje koje menjaju članstvo ili pozivnice MUST zahtevati mrežu i bez nje prikazati „Za ovo je potrebna internet veza.“ bez delimičnih izmena.
- **FR-016**: Svaka greška MUST biti prikazana na srpskom iz tabele tekstova; tehnički kodovi, ID-jevi i imejlovi drugih se ne prikazuju.
- **FR-017**: Korisnik sa više članstava MUST moći da izabere aktivno domaćinstvo; izbor se pamti na uređaju za taj nalog; bez izbora važi poslednje pridruženo.
- **FR-018**: Ako izabrano domaćinstvo više nije dostupno, aplikacija MUST preći na poslednje pridruženo od preostalih.
- **FR-019**: Izmene napravljene u jednom domaćinstvu MUST ostati vezane za to domaćinstvo i kad se aktivno domaćinstvo promeni pre slanja.
- **FR-020**: Sav novi tekst MUST biti na srpskoj latinici i naveden u odeljku Tekstovi.
- **FR-021**: Ekrani MUST raditi na širini telefona, na širokom rasporedu i sa tekstom 2×.

### Key Entities

- **Domaćinstvo**: naziv i skup članova; jedan vlasnik.
- **Član domaćinstva**: korisnik, uloga (vlasnik ili član), vreme pridruživanja; ime koje drugi vide dolazi iz njegovog profila.
- **Pozivnica**: kod od 8 znakova, rok važenja (7 dana), najviše upotreba (5), broj iskorišćenih, poništena ili ne; vidi je samo vlasnik.
- **Aktivno domaćinstvo**: domaćinstvo čije podatke aplikacija trenutno prikazuje; određuje ga izbor na uređaju ili, bez izbora, poslednje pridruživanje.

## Tekstovi

„Domaćinstvo“, „Članovi“, „Vlasnik“, „Član“, „Ti“, „Član bez imena“, „Pozovi člana“, „Kod za pozivanje“, „Važi do {d.m.gggg.}“, „Još 1 upotreba“ / „Još {2–4} upotrebe“ / „Još {n} upotreba“ (5 i više, kao i 0 se ne prikazuje jer pozivnica tada nije aktivna), „Kopiraj kod“, „Kod je kopiran.“, „Podeli“, „Pridruži se mom domaćinstvu u aplikaciji Tavli. Kod: {kod}. Otvori Tavli → Profil → Domaćinstvo → Pridruži se kodom.“, „Aktivne pozivnice“, „Nema aktivnih pozivnica.“, „Poništi“, „Poništiti pozivnicu?“, „Kod više neće moći da se iskoristi.“, „Pozivnica je poništena.“, „Pridruži se kodom“, „Unesi kod od 8 znakova“, „Pridruži se“, „Posle pridruživanja vidiš plan, nabavku, recepte i ostavu ovog domaćinstva. Tvoji dosadašnji podaci ostaju sačuvani u tvom domaćinstvu.“, „Sada si član domaćinstva „{naziv}“.“, „Kod nije važeći ili je istekao.“, „Previše pokušaja. Pokušaj ponovo za 10 minuta.“, „Ukloni iz domaćinstva“, „Ukloniti {ime} iz domaćinstva?“, „Više neće videti podatke ovog domaćinstva.“, „Član je uklonjen.“, „Napusti domaćinstvo“, „Napustiti domaćinstvo?“, „Vratićeš se u svoje domaćinstvo i više nećeš videti ove podatke.“, „Domaćinstvo je napušteno.“, „Pre napuštanja prenesi vlasništvo drugom članu.“, „Prenesi vlasništvo“, „Preneti vlasništvo na {ime}?“, „Ti postaješ član i više ne možeš da pozivaš ni uklanjaš članove.“, „Vlasništvo je preneto.“, „Aktivno domaćinstvo“, „Prebaci“, „Prikazano je poslednje poznato stanje.“, „Za ovo je potrebna internet veza.“, „Samo vlasnik može to da uradi.“, „Taj korisnik više nije član domaćinstva.“, „Nešto nije uspelo. Pokušaj ponovo.“, „Otkaži“.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Dvoje ljudi, svako na svom uređaju, od „Pozovi člana“ do toga da novi član vidi zajedničku nabavku završe za manje od 2 minuta, bez ponovne prijave.
- **SC-002**: Svaki scenario prihvatanja iz ove specifikacije ima automatski test (widget ili integracioni sa lažnim backendom), a nova serverska funkcija ima pgTAP test sa dva naloga.
- **SC-003**: Ni u jednom scenariju korisnik ne vidi imejl drugog člana ni tehnički kod greške.
- **SC-004**: Posle pridruživanja, napuštanja ili uklanjanja aktivno domaćinstvo i prikazani podaci odgovaraju serveru najkasnije posle jednog osvežavanja naloga, bez ponovnog pokretanja aplikacije.
- **SC-005**: Svi ekrani prolaze proveru na širini telefona, na širokom rasporedu i sa tekstom 2× (bez odsečenog teksta i horizontalnog skrolovanja).

## Assumptions

- **Moja odluka:** aktivno domaćinstvo bez ručnog izbora je poslednje pridruženo (već u PR #31); ručni izbor (priča 5) se pamti samo na uređaju, ne na serveru.
- **Moja odluka:** QR kod i link za pozivanje su van ove specifikacije (QR traži nove zavisnosti za prikaz i kameru, link traži domen i univerzalne linkove). Kod i deljenje teksta pokrivaju poziv uživo i na daljinu.
- **Moja odluka:** dužina koda ostaje 8 znakova kako ga server pravi; da li prelazimo na 6 i dodajemo IP limit odlučuje Uroš odvojeno (bezbednost pozivnica).
- Imena drugih članova nisu dostupna kroz postojeća pravila pristupa (profil čita samo vlasnik profila); potreban je serverski pristup koji vraća samo ime i ulogu članova zajedničkog domaćinstva. Detalj je za plan.
- Koji podaci se dele u domaćinstvu se ne menja ovom specifikacijom; lične ocene ostaju lične (product-design).
- Brisanje naloga vlasnika i šta se tada dešava sa zajedničkim domaćinstvom je van opsega (otvoreno pravno pitanje u politici privatnosti).
- Realtime osvežavanje liste članova je van opsega (009); lista se osvežava pri otvaranju ekrana, povlačenju nadole i posle svake radnje.
- Prijava na produkciji (OTP 8 cifara i šabloni) ne utiče na ovu specifikaciju; sve se proverava na lokalnom Supabase-u.
