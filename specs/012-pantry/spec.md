# 012 — Funkcionalna Ostava

## Dizajn ugovor
Ostava pokazuje stvarnu zalihu prijavljenog domaćinstva iz postojeće Drift
tabele. Glavna akcija je „Dodaj namirnicu“. Pregled je čitljiva grupisana
lista, pretraga i filteri roka, sa jednom kolonom na telefonu i ograničenom
širinom na desktopu. Forma skroluje i radi pri tekstu 2×. Koristi postojeću
paletu, tipografiju, animaciju praznog frižidera i četiri taba.
Reference su postojeći Tavli Nabavka, forma recepta i docs/product-design.md.

## Prihvatanje
- Prikaz, pretraga, dodavanje, izmena i potvrđeno uklanjanje namirnice.
- Naziv obavezan; količina opciona, konačna i veća od nule; decimalni zarez.
- Kategorija, jedinica i opcioni rok; isteklo i rok u narednih sedam dana
  imaju tekstualnu oznaku i filter. Izabrani datum važi do kraja tog dana.
- Nepoznata količina ne umanjuje brojčanu nabavku. Izmena zalihe ponovo
  preračunava postojeću nabavku u istoj transakciji.
- Prenos iz Nabavke se odmah vidi; ponavljanje ne duplira zalihu čak ni
  posle uklanjanja. Za primljene stavke čuva se nulta evidencija prijema,
  sakrivena iz Ostave; kupovina ostaje istorija, ne nova zaliha.
- Samo aktivno domaćinstvo, svaka izmena kroz repozitorijum i outbox.
- Greška čuva unos i nudi ponovni pokušaj. Loading/error/empty/no-results.
- 320/390/768/1024/1440 px i tekst 2×; svetle i tamne postojeće teme.

## Novi tekstovi
Ostava; Namirnice koje imaš kod kuće.; Dodaj namirnicu; Pretraži ostavu;
Sve; Uskoro ističe; Isteklo; Nema namirnica za ovaj izbor; Promeni pretragu
ili filter.; Naziv; Količina; Jedinica; Kategorija; Rok trajanja;
Količina nije potvrđena; Iz nabavke;
Izmeni namirnicu; Sačuvaj; Čuvam…; Namirnica je sačuvana.; Obriši;
Ukloni namirnicu?; Ukloni; Odustani; Istorija kupovine ostaje sačuvana.;
Namirnica je uklonjena.; Unesi naziv.; Unesi broj veći od nule.;
Ostava trenutno ne može da se prikaže.; Pokušaj ponovo;
Izmena nije sačuvana. Pokušaj ponovo.; Namirnica nije pronađena.;
Uklanjanje nije uspelo. Pokušaj ponovo.; Rok: <datum>.
Prazno ako količina nije potvrđena.; Prazno ako rok nije naveden.;
Unesi datum u obliku d.m.gggg.; 31.12.2026.; kg, g, l, ml, kom;
Obriši pretragu. Rok se unosi kao lokalni kalendarski datum.
Postojeći tekst praznog prikaza i animacija ostaju.

## Granice
Bez nove šeme, tabela, zavisnosti, AI poziva ili izmišljenih zaliha. Bez
automatske potrošnje pri kuvanju i bez procene bezbednosti hrane.
