# 031 — Potroši ove 3 namirnice (predlog 30)

Na postojećem ekranu „Potroši prvo“ korisnik brzo bira jedan do tri naziva namirnica i dobija recepte iz svoje zbirke koji koriste bar jednu od njih. Nije potrebno popuniti Ostavu. Ovo je drugi ulaz u isti obračun predloga, ne novi preporučivač.

## Prihvatanje
- Proširiva sekcija „Potroši ove 3 namirnice“ dostupna je i kada je Ostava prazna. Omogućava unos, uklanjanje i čišćenje izbora; najviše tri jedinstvena naziva, 1–80 znakova po nazivu.
- Poklapanje koristi postojeći potvrđeni rečnik v1 (npr. češnjak/beli luk), bez proizvoljnog približnog ili podstring poklapanja.
- Prikazuju se samo recepti koji koriste bar jednu izabranu namirnicu. Više jedinstvenih pogodaka ima prednost, a postojeći redosled po rokovima/pokriću razrešava isti broj pogodaka. Duplirani redovi ili jedinice istog sastojka ne povećavaju broj pogodaka.
- Svaki predlog pokazuje „Koristi X/Y izabranih namirnica“. Ne mora koristiti sve izabrane namirnice.
- Izbor naziva ne potvrđuje količinu niti pravi zalihu. Postojeće slobodne, potvrđene količine iz Ostave koriste se kao i ranije. Bez poznate količine za izabranu namirnicu prikazuje se „Proveri količinu“, uz poznatu potrebu recepta, nikad „Mogu sada“ samo zbog izbora naziva. Izabrani naziv bez brojčanog pokrića ne ulazi ni u filter poznatih manjkova „Nedostaju 1–2 sastojka“.
- Preračun porcija, pretraga, filteri i otvaranje recepta ostaju. Promena izbora vraća filter „Svi predlozi“ da prethodno „Mogu sada“ ne sakrije neproverene predloge.
- Bez izbora ekran i rangiranje rade kao ranije. Ako nema pogodaka, to je jasno naznačeno i izbor ostaje dostupan.
- Pregled radi offline i ništa ne upisuje u bazu, outbox, plan, nabavku ili recept. Izbor važi dok je ekran otvoren.
- Telefon, široki ekran, tamni režim i tekst 2× su podržani.

## Tekstovi
„Potroši ove 3 namirnice“, „Izaberi do 3 namirnice. Naziv ne potvrđuje količinu; računamo samo potvrđenu zalihu iz Ostave.“, „Namirnica“, „Dodaj u izbor“, „Najviše 3 namirnice“, „Unesi naziv namirnice.“, „Naziv može imati najviše 80 znakova.“, „Ova namirnica je već izabrana.“, „Obriši izbor“, „Ukloni …“, „Prednost imaju recepti koji koriste više izabranih namirnica. Računamo samo potvrđene, slobodne količine iz Ostave.“, „Koristi X/Y izabranih namirnica“, „Nema recepata sa izabranim namirnicama. Promeni izbor ili dodaj recept u zbirku.“, „Proveri količinu: … · za recept …“.
