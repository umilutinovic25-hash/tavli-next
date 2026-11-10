# 016 — Apple-inspired visual polish

## Cilj
Jedna dosledna vizuelna izmena aplikacije: mirnija tipografija, funkcionalna
bočna navigacija, bolje grupisani elementi, prozračnija prazna stanja i suptilan
ulazak sadržaja. Korisnik je tražio izgled na nivou Apple aplikacija.

## Ugovor dizajna
- Posao ekrana i postojeće primarne akcije ostaju isti: Plan → obroci,
  Nabavka → kupovina, Recepti → zbirka, Ostava → zalihe, Potroši prvo → predlozi.
- Na Apple platformama koristiti sistemsku Cupertino tipografiju iz Fluttera;
  ostale platforme čuvaju ugrađeni Plus Jakarta Sans. Naslovi su čitljivi,
  kontrolisane veličine i težine, body ostaje pristupačnih 16/1.5.
- Svetla neutralna podloga, jasne površine i postojeći zeleni/šafran/borovnica
  akcenti. Sve tri teme i svetli/tamni režim moraju ostati funkcionalni.
- Od 720 px prikazivati bočnu navigaciju sa punim nazivima, na telefonu četiri
  tab-a. Izbor, povratak, avatar i status sinhronizacije moraju biti očuvani.
- Za sadržaj koristiti mirne standardne površine; vizuelnu dubinu ograničiti
  na navigacioni sloj. Bez kopiranja Apple logotipa, grafike ili font fajlova.
- Sačuvati postojeće animacije, dodati mali reveal preko postojećeg MotionBuilder;
  Reduce Motion odmah prikazuje završno stanje. Kontrole ostaju dostupne tastaturi.
- Funkcije i podaci su stabilni pre ovog polish koraka; ne menjati bazu, modele,
  auth, sync, rezervacije ili proračune i ne uvoditi novi state sistem.

## Prihvatanje
Pregled 320/390/768/1024/1440 px, tekst 2×, sve tri tamne teme, popunjena i prazna
stanja. Proveriti navigaciju, formu recepta, Ostavu i Potroši prvo u zajedničkom
pregledu. Testovi, analiza, stvarni Flutter render i native macOS build pre PR-a.

Novi UI tekst: „Tvoja kuhinja“. Postojeći tekstovi i akcije ostaju isti.
