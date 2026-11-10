# 014 — Potroši prvo

## Ugovor
Predlozi se računaju iz postojeće zbirke recepata i Ostave prijavljenog
domaćinstva. Glavna akcija „Potroši prvo“ dostupna je iz zaglavlja tabova.
Ekran ima izbor porcija (1–20, početno 2), pretragu i filter „Mogu sada“.
Filter „Nedostaju 1–2 sastojka“ prikazuje zasebno recepte sa jednim ili dva
različita potvrđena manjka; nepoznata potrebna količina ostaje za proveru i
isključuje recept iz tog filtera. Pretraga i porcije važe i za ovaj filter.
Otvaranje recepta vodi u postojeći recept/tok sastojaka; predlog ne menja
Ostavu, ne rezerviše zalihu i ne piše Nabavku.

## Računanje
- Koristiti postojeće ingredientKey, demandFor i normalizaciju jedinica.
- Samo potvrđena, pozitivna, konačna i neistekla količina pokriva potrebu.
  Nepoznata količina u receptu ostaje na proveri. kg↔g, l↔ml su podržani;
  bez pretpostavke o gustini ili sinonimima koji ne postoje u podacima.
- Oduzeti postojeće supply_allocations; prijem kupovine i njegova zaliha
  imaju isti kanonski identitet. Kandidati se procenjuju odvojeno.
- Isti sastojak/jedinica u receptu prvo se sabira. Partije se koriste po
  najbližem roku. Ne računati jednu fizičku partiju dvaput.
- Grocy Due Score je adaptiran: u narednih 7 kalendarskih dana, 8−broj dana
  daje težinu 8…1, samo ako se ta zaliha stvarno koristi. Isteklo se isključuje.
- Red: najbliži iskorišćeni rok u tih 7 dana, zbir hitnosti, veći udeo potpuno
  pokrivenih sastojaka, naziv i id. Deterministički, bez AI ili mrežnih poziva.
- Prikazati samo recepte sa bar jednim brojčano pokrivenim delom sastojka.
- „Mogu sada“ znači sve količine poznate i pokrivene slobodnim količinama iz Ostave za
  izabrane porcije; nije potvrda bezbednosti ili kvaliteta same namirnice.

## Prihvatanje
1. 1 kg potrebe − 250 g slobodne zalihe = 750 g nedostaje.
2. Skala porcija i rezervacije menjaju rezultat odmah.
3. Namirnica koja uskoro ističe daje prednost samo receptima koji je koriste.
4. Istekle/nepotvrđene/nepoznate zalihe, druga jedinica i drugo domaćinstvo
   ne stvaraju lažno „Mogu sada“.
5. Više partija, ponovljeni sastojak, datum na granici i stabilan redosled.
6. Loading/error/retry, prazna zbirka, prazna Ostava, bez pogodaka; unos/pretraga
   ostaju pri promeni podataka. Telefon/desktop, tekst 2× i postojeće teme.
7. Svaka promena postojećih podataka osvežava rezultat; vreme se osvežava na
   povratku u aplikaciju i najkasnije jednom u minutu dok je ekran otvoren.
8. Bez promene baza, outbox-a, rezervacija ili količina samim gledanjem.

## UI tekst
Potroši prvo; Od onoga što već imaš; Porcije; Predlozi; Mogu sada;
Svi predlozi; Nedostaju 1–2 sastojka; Pretraži predloge; Manje porcija; Više porcija;
Prednost imaju namirnice kojima rok ističe u narednih 7 dana. Računamo potvrđene, slobodne količine iz Ostave.;
Potroši prvo: {namirnice} · rok {datum}; Sve poznate količine su dostupne;
{pokriveno}/{ukupno} sastojaka potpuno pokriveno; Nedostaje: {naziv} · {količina};
Proveri količinu: {naziv}; Otvori recept;
Sačuvaj recepte da bismo ih povezali sa Ostavom.; Otvori recepte;
Nema recepata sa raspoloživim sastojcima. Proveri količine, potvrdu i rokove u Ostavi.; Otvori Ostavu;
Nema predloga za izabranu pretragu i filter.;
Svaki predlog računa se zasebno. Pregled ne rezerviše i ne troši namirnice.;
Predlozi trenutno nisu dostupni.; Pokušaj ponovo.
