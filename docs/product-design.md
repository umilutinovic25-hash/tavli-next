# Tavli: od plana obroka do nabavke i kuvanja

**Dogovoreni pravac:** 02.11.2026.
**Status:** cilj proizvoda; nije opis već završenih ekrana.
**Spec Kit:** [010 — Plan i nabavka](../specs/010-plan-and-shopping/spec.md),
[plan implementacije](../specs/010-plan-and-shopping/plan.md).

Tavli pomaže domaćinstvu da napravi nedeljni ili mesečni plan obroka, dobije
predloge recepata i pripremi nabavku. Korisnik može i direktno iz jednog
recepta da proveri sastojke i pripremi nabavku, bez pravljenja plana. Ostava, ukus i potrebe domaćinstva utiču
na predloge. Recepti ostaju kuvarska zbirka i osnova za planiranje i pripremu.

**Napravi plan → prilagodi obroke → proveri šta imaš → pripremi nabavku →
kupi → kuvaj → oceni.**

## 1. Navigacija

Glavni tabovi su **Plan, Nabavka, Recepti, Ostava**, tim redom. Plan je početni
ekran posle prijave i obaveznog koraka sa imenom. Profil, podešavanja i
domaćinstvo otvaraju se preko avatara gore desno, na telefonu i računaru.
„Danas“ je prečica unutar plana, sa današnjim obrocima i ulaskom u kuvanje.

Postojeće prijavljivanje, odjavljivanje, brisanje naloga, AI podešavanja i
stanje čuvanja podataka ostaju dostupni. Adrese recepata i Profila ostaju
važeće; naziv „Nabavka“ ne zahteva promenu postojeće adrese `/shopping`.

## 2. Pravljenje plana

Pri vrhu su period, izbor **Nedelja / Mesec**, prečica **Danas** i izbor
sačuvanog plana. Bez plana, glavna akcija je **Napravi plan**. Kada plan
postoji, istaknuta akcija je **Otvori nabavku**.

1. Izaberi nedelju ili kalendarski mesec.
2. Izaberi doručak, ručak i/ili večeru i broj porcija.
3. Pregledaj sopstvene preference i posebne zahteve za ovaj plan.
4. Odluči da li da se koriste potvrđene namirnice iz ostave.
5. Pregledaj predloge raspoređene po danima, zameni šta ti ne odgovara i sačuvaj.

Početni izbori su tekuća nedelja, ručak i dve porcije; sve je izmenjivo.
Porcije iz poslednjeg izabranog plana mogu da se ponude umesto dve. Model
domaćinstva još nema broj članova; aplikacija ga ne prikazuje kao poznat podatak.

AI predlog je nacrt. Pre potvrde ne menja sačuvan plan, recepte ili nabavku.
Mesečni predlog nastaje u manjim celinama uz vidljiv napredak. Ako generisanje
stane, dobijeni deo ostaje u otvorenom pregledu i može da se nastavi. Prazna
mesta su označena; nepotpun nacrt se čuva samo izričitom akcijom.

## 3. Pregled i promene

Telefon prikazuje nedelju kao listu dana sa izabranim vrstama obroka. Za mesec
prikazuje mali kalendar i detalje izabrane nedelje ispod njega. Široki prozor
koristi kalendar i bočni pregled recepta. Telefon ne dobija sedam uskih kolona.

Obrok prikazuje naziv, poznato vreme, porcije i oznake **Zaključano** i
**Skuvano**. Može da se otvori recept, zameni jelo AI predlogom ili sačuvanim
receptom, promene porcije, zaključa obrok i označi kao skuvan. Ponavljanje
istog recepta različitih dana je dozvoljeno i računa se prema svakom unosu.

Ponovno generisanje čuva zaključane, skuvane i prošle obroke. Promene imaju
pregled pre prihvatanja. Plan čuva odobrenu verziju recepta: kasnija izmena
recepta u zbirci ne menja tiho plan i potrebne količine.

Nedelje traju od ponedeljka do nedelje. Mesečni plan obuhvata kalendarski
mesec; nabavke se grupišu u delove tih nedelja unutar meseca. Mesec može da
zahvati **šest** nedelja. Prikazuju se datumi, bez pretpostavke o četiri ili pet.

## 4. Nabavka

Uvek se vidi plan i period za koji kupujemo. Za mesec postoje zbirni pregled
i pojedinačne nedelje. Mesečni pregled sabira iste nedeljne stavke; ne pravi
drugu kopiju liste koja bi se posebno kupovala.

- Isti sastojci se objedinjuju; količine se sabiraju kada su jedinice uporedive.
  Nepoznate količine ostaju za proveru.
- Uz stavku se vide obroci iz kojih potiče. Dve pojave istog recepta imaju
  odvojene potrebe prema svojim porcijama.
- „Imam“ znači da sastojak postoji kod kuće. Osoba potvrđuje količinu ili da
  ima celu stavku. To nije oznaka „kupljeno“.
- Potvrđena količina iz ostave koristi se jednom kroz ceo plan, umesto da se
  ponovo oduzima u svakoj nedelji.
- Ponovno dodavanje i izmena plana usklađuju samo razliku. Ručno dodate i
  kupljene stavke ostaju. Izmena ne vraća kupljenu stavku u nekupljenu.
- Stavke su grupisane po odeljenjima prodavnice, sa velikim površinama za
  štikliranje i brzim ručnim dodavanjem. Kupljeno je u odvojenoj grupi i može
  da se vrati.

Posle kupovine se nudi **Dodaj kupljeno u ostavu**, uz potvrdu količina.
Ponovljena potvrda ne uvećava ostavu dvaput. Kupljena namirnica i njen zapis
u ostavi predstavljaju istu zalihu i ne daju dvostruko pokriće plana.

Primer: obroci traže 300 g, imamo 100 g i kupimo 200 g. Prenos kupljenog u
ostavu ne daje još 200 g pokrića. Ako potreba poraste na 400 g, ostaje
**100 g za nabavku**.

### Nabavka samo za recept

Nabavka ima dva jasna polazišta: **Po planu** i **Po receptu**. Iz sačuvanog,
pronađenog, uvezenog ili upravo generisanog recepta može da se otvori
**Proveri sastojke**, izaberu porcije, označi šta osoba ima i dodaju samo
nedostajući sastojci. Nije potrebno napraviti plan.

Pregled sastojaka ništa ne upisuje. Izričito dodavanje u nabavku čuva potreban
snimak recepta kao poreklo stavki, čak i ako generisani recept nije sačuvan u
zbirci. Kasnije odbacivanje tog recepta iz pregleda ne briše već potvrđenu nabavku.

Ponovni klik za istu pripremu ažurira samo razliku. **Ponovi nabavku** znači
novu namernu pripremu istog jela i ima zasebno poreklo. Ako je recept već u
planu, prvo su jasno ponuđeni **Prikaži nabavku plana** i **Dodaj zasebnu
pripremu**. Pregled recepta sam po sebi ne duplira potrebe plana. Potvrđena
zaliha ne daje dvostruko pokriće ni kada se koriste oba načina nabavke.

## 5. Ostava i preference

Ostava ima pretragu, dodavanje i uređivanje količine, jedinice i roka. Izdvaja
namirnice kojima rok ističe u narednih sedam dana i nudi **Iskoristi u planu**.
Nepoznato ili zastarelo stanje traži potvrdu pre smanjenja nabavke. Kuvanje
ne umanjuje stvarnu zalihu bez potvrde osobe. Oznaka „Skuvano“ zatvara
nekupljene potrebe tog obroka; zaliha ostaje rezervisana do provere potrošnje,
pa se ne nudi ponovo za drugi obrok kao da sigurno nije potrošena.

Profil ukusa obuhvata način ishrane, sastojke koje osoba ne voli i alergije.
Ocene i omiljena jela utiču na buduće predloge. Generisanje koristi sopstveni
profil osobe koja pravi plan i izričite zahteve tog plana. Tuđi lični profili
i ocene se ne čitaju niti objavljuju drugim članovima domaćinstva.

## 6. Recepti i kuvanje

Zbirka zadržava pretragu, dodavanje iz fotografije, po nazivu i ručno, AI
izmene uz pregled i istoriju verzija. **Dodaj u plan** nudi datum i obrok,
sa potvrdom kada se menja postojeći unos.

Fotografija napisanog recepta čuva se kao original koji može da se otvori.
Fotografija gotovog jela ima zasebnu ulogu. Slika teksta se ne rasteže kao
fotografija hrane, niti se izmišlja fotografija jela. Razdvajanje više
foto-datoteka je zasebna buduća dorada; 010 otvara postojeći original i koristi
neutralan prikaz kada fotografija hrane nije potvrđena.

Režim kuvanja prikazuje istaknut korak, **Prethodni**, **Sledeći**, dostupne
sastojke i mogućnost zadržavanja uključenog ekrana. Na širokom prozoru sastojci
su levo, priprema desno. Recept bez koraka nudi dopunjavanje i pregled pre
kuvanja. Sačuvani koraci rade offline.

Kuvanje iz plana radi i kada je izvorni recept obrisan, preko sačuvane verzije
obroka. Za ocenu takvog recepta prvo se izričito sačuva novi recept u zbirku.

Posle pripreme može da se označi **Skuvano**, oceni jelo i označi
**Omiljeno jelo**. Ocena je lična i opciona.

## 7. Vizuelni pravac

Topla bela pozadina, tamnozelene glavne akcije i malo terakote. Fotografije
imaju najviše prostora pri izboru i pregledu jela. Plan je miran raspored,
a nabavka čitljiv spisak.

- Osnovni tekst je najmanje 16 logičkih piksela, koraci imaju prozračan prored.
- Umereno zaobljenje i manje okvira, uz jasne naslove i razmake.
- Boja nije jedina oznaka: zaključano, skuvano i kupljeno imaju i tekst ili
  ikonu sa pristupačnim nazivom.
- Telefon, široki prozor i tekst 2× imaju ravnopravne tokove.
- Tamni režim razdvaja pozadinu i površine. Animacije potvrđuju radnju,
  poštuju smanjeno kretanje i ne dodaju namerna čekanja.

## 8. UI/UX je uslov prihvatanja

Prvi koristan plan mora da bude moguć bez prethodnog popunjavanja ostave ili
profila ukusa. Osnovni izbori — period, obroci, porcije — staju na jedan ekran.
Dodatna podešavanja se otvaraju po potrebi. Tok ima najviše tri celine:
podešavanje → napredak i pregled → potvrda. Jedna glavna akcija vodi dalje.

Od otvorenog plana do nabavke za tekuću nedelju potrebna su najviše dva
dodira; od današnjeg obroka sa sačuvanim koracima do kuvanja takođe najviše dva.
Ako koraci nedostaju, u dva dodira se stiže do dopunjavanja; generisanje i
potvrda su jasno prikazani dodatni koraci. Štikliranje u
prodavnici odmah daje vidljiv odgovor, bez dijaloga za svaku stavku. Greške
čuvaju unos i nude ponovni pokušaj. Tehnički pojmovi ostaju u podešavanjima.

Dizajn i zatim aplikacija proveravaju se sa pet ljudi koji ih koriste prvi
put. Cilj je da najmanje četvoro završi tok plan → nabavka → kuvanje i
samostalnu nabavku za recept bez objašnjavanja kontrola. Beleže se pogrešni
koraci i zastajkivanja, problemi se
ispravljaju i ponovo proveravaju. Ovo je budući kriterijum, ne već ostvaren
rezultat. Vizuelni pregled i automatski testovi ne zamenjuju ovu proveru.

## 9. Granice i redosled

010 je povezana funkcionalnost **plan → nabavka**, sa osnovnim radnjama nad
ostavom, preferencama, receptima i kuvanjem. Pozivanje članova (008) je
isporučeno kao 034: kod pozivnice, članovi i uloge, napuštanje, prenos
vlasništva i izbor aktivnog domaćinstva; link i QR za pozivanje još nisu
urađeni. Realtime i napredno rešavanje istovremenih izmena ostaju 009. Planiranje počinje na
postojećem ličnom domaćinstvu, sa istim modelom deljenih podataka.

Obavezni nalog, čuvanje na serveru i offline keš ostaju pravilo. Istorijske
specifikacije opisuju ranije isporučene funkcije; ovaj dokument i 010 određuju
novi pravac. Ova dokumentaciona izmena ne menja aplikaciju, šemu ili podatke.

Drugi ravnopravan zadatak je: pronađi ili generiši recept → proveri sastojke →
dodaj nedostajuće → kupi, bez otvaranja plana.

Prvi povezani prototip proverava: mesečni plan → zamena i zaključavanje →
nabavka za nedelju → potvrda ostave → kupovina → današnje kuvanje. Prototip
ne označava buduće zadatke implementacije završenim.
