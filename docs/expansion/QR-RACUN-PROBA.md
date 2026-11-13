# Proba: QR kod sa fiskalnog računa (izveštaj)

Datum: 2026-11-13. Trello: „Proba: QR kod sa računa“ (Dev 1). Kratak izveštaj sa
preporukom, ne funkcija.

**Šta je rađeno:** pregled zvanične TaxCore/SUF dokumentacije Poreske uprave i
javnih integracija. **Šta NIJE rađeno:** nijedan pravi račun nije skeniran, pa
stopa poklapanja sa katalogom nije izmerena (vidi „Šta još treba izmeriti“).

## Šta QR kod daje
- QR kod štampan na računu je **verifikacioni URL** oblika
  `https://suf.purs.gov.rs/v/?vl=…` (nije sam sadržaj računa).
- Isti URL sa zaglavljem `Accept: application/json` vraća JSON sa zahtevom
  računa, rezultatom, žurnalom i statusom važenja. Žurnal je dostupan tek kad su
  podaci stigli do Poreske uprave.
- Stavke računa: naziv, količina, jedinična cena sa PDV, ukupna cena, osnovica,
  PDV i oznaka stope. Uz to: PIB prodavca, lokacija i adresa, vreme, brojači.
- Stavka ima i **opciono polje `gtin` (barkod); može biti prazno** (dokumentacija
  kaže „Can be null“).
- Račun se može proveriti i bez QR koda ručnim unosom elemenata računa na sajtu
  Poreske uprave (korisno kad je QR oštećen).

Izvori: TaxCore Help (Invoice Verification Service, Create Invoice, Public
Portal), `suf.purs.gov.rs`.

## Šta to znači za povezivanje sa katalogom
- **Naziv stavke je slobodan tekst koji kasa prodavca ispisuje** (npr.
  „Mleko 2.8% 1L (A)“). Nema kategorije ni jedinice mere osim u samom nazivu.
- Katalog (036) poklapa **samo tačne aliase**, pa će sirov naziv sa računa
  retko pogoditi namirnicu bez potvrde osobe.
- **Barkod (kad postoji) je najbolji ključ:** javni cenovnici koje već uvozimo
  (041) imaju barkod, naziv i pakovanje, pa se stavka može povezati
  barkod → proizvod → namirnica. Bez barkoda ostaje tekstualno poklapanje uz
  potvrdu.
- Mere: robe na meru dolaze kao decimalna količina (kg), pakovana roba kao broj
  komada; pakovanje (npr. 1 L) je samo u nazivu.

## Rizici i ograničenja
- **Verifikacija šalje račun Poreskoj upravi.** Dokumentacija kaže da se
  provera računa (skeniranje ili klik na URL) automatski prijavljuje bazi
  Poreske uprave. Programski zahtev na isti URL je ista provera. Zato ga
  aplikacija sme da šalje samo za račun koji korisnik sam skenira i uz jasnu
  napomenu; nije sporedan zahtev u pozadini.
- Podaci o kupovini su lični; čuvati ih u nalogu po pravilima 034/038 (izvoz,
  brisanje), ne logovati URL ni žurnal.
- Žurnal ne mora odmah da postoji (offline račun): predvideti ponovni pokušaj.
- Nisam našao objavljeno ograničenje broja zahteva; do potvrde tretirati kao
  nepoznato.

## Preporuka
Raditi **malu funkciju sa potvrdom, ne automatsko povezivanje**:
1. Skeniranje QR koda (ili unos elemenata računa) → lista stavki sa cenom i
   prodavcem.
2. Poklapanje redom: barkod preko uvezenih cenovnika, pa tačan alias, pa ostaje
   „proveri“ (isti dijalog potvrde kao za sastojke). Ništa se ne upisuje bez
   potvrde.
3. Korist odmah: **istorija cena** (prodavac, datum, dokaz iz računa) i
   **prijem u Ostavu** iz kupljenih stavki. Poređenje korpe po prodavnici već
   postoji (040/041).
4. Odluka o obimu tek posle merenja ispod.

## Šta još treba izmeriti (pre odluke)
Uzeti 10–15 stvarnih računa (različiti lanci), za svaki otvoriti JSON i
izbrojati: koliko stavki ima `gtin`, koliko se poklopi preko barkoda sa
cenovnicima, koliko preko tačnog aliasa, koliko ostaje za ručnu potvrdu. Ova
brojka odlučuje da li se funkcija isplati. Za to treba da neko donese račune
(URL-ovi sadrže podatke o kupovini).
