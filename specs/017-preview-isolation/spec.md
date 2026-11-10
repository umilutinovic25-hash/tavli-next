# 017 — Izolacija lokalnog probnog Keychain prostora
Lokalni pregled trenutno deli session/key storage sa običnim build-om. Novi
ad-hoc build može zato tražiti pristup ranije sačuvanim stavkama. Probni build
mora imati eksplicitno uključen TAVLI_LOCAL_PREVIEW i zasebne logičke ključeve
za auth sesiju i AI ključeve, u istom postojećem sigurnom skladištu.

Podrazumevani build čuva sve postojeće putanje/ključeve. Preview je dozvoljen
samo za loopback Supabase. Nema čitanja, kopiranja, brisanja ili promene prava
starih stavki. Nema preskakanja autentifikacije ili čuvanja tokena u običnom fajlu.
Prva probna prijava se ponavlja kroz postojeći OTP tok. Postojeći backend,
cache, household modeli i repozitorijumi ostaju isti.

Prihvatanje: fake-storage testovi dokazuju izolaciju session/key read/write/delete
uključujući legacy migraciju, nepromenjen default i odbijanje udaljenog backend-a.
Native preview treba da stigne do prijave i glavnog ekrana bez zahteva za stare
stavke. Ne rešava razvojno potpisivanje običnog build-a; stabilan potpis ostaje
pravi put za razvoj koji koristi postojeće korisničke credentials.

Nema novog korisničkog UI teksta. Tehnička greška konfiguracije: Lokalni pregled zahteva loopback Supabase.
