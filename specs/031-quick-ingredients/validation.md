# Provera — 10. novembar 2026.

- Domen testovi napisani pre implementacije; početno su pali jer opcioni izbor još nije postojao.
- `scripts/check.sh`: format ispravan, `flutter analyze` bez problema.
- `flutter test`: svih 677 testova prolazi; 33 u ciljanoj proveri domena i ekrana predloga.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build macos --debug`: uspešno napravljen `tavli.app`. Prvi paralelni build se sudario sa testovima koji obnavljaju generisani Swift manifest; izdvojen build nakon završetka ostalih komandi prolazi bez izmena projekta.
- Brz izbor radi i bez Ostave: samo recepti sa izabranim namirnicama, više različitih pogodaka ima prednost. Isti broj pogodaka čuva prethodno rangiranje po rokovima.
- Potvrđeni sinonim češnjak/beli luk se poklapa; podstring, nulta potreba i dupli redovi/jedinice ne daju lažne dodatne pogotke.
- Račun: 600 g potrebe − (500 g zalihe − 100 g rezerve) = 200 g manjka; jedna porcija traži 300 g i postojeća zaliha je dovoljna. Izbor naziva ne povećava zalihu i istekla namirnica ne daje pokriće.
- Nepoznata količina izabranog naziva traži proveru i ne ulazi u „Mogu sada“ niti filter poznatih manjkova.
- Widget testovi: prazno, duplikati sinonima, ograničenje od tri izbora, uklanjanje, čišćenje, prazni rezultati, pretraga, porcije, filteri i otvaranje postojećeg recepta.
- Pregled ne menja Ostavu, nabavku, recepte ili outbox.
- Telefon 320 px i široki ekran 1200 px sa tekstom 2× i tamnom temom prolaze; postojeći rasporedi i živa Ostava takođe prolaze.
- Ručna provera na fizičkom uređaju nije izvedena; raspored i tok provereni su widget testovima.
