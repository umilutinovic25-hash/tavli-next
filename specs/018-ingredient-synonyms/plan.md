# Plan

Proširiti postojeći obračun potražnje potvrđenim statičkim rečnikom verzije 1. Verzija se čuva u postojećem JSON snimku pri potvrdi, bez promene šeme ili novih korisničkih podataka. Stari snimak bez verzije ostaje na verziji 0. Za nove izvore verzionisati identitet i koristiti odvojenu proveru fizičke grupe; pri raspodeli jedna zaliha podržava oba identiteta uz jednu zajedničku količinu. Rečnici objavljenih verzija ostaju nepromenjeni; novi unosi idu u novu verziju. Nema novih zavisnosti.

## Ustav I–IX
I: nema novog UI teksta. II: postojeći sinhronizovani snimak, offline. III–IV: bez AI i tajni. V: testovi prvo, bez mreže. VI: nema novog ekrana. VII–VIII: jedna grana i specifikacija. IX: bez šeme i novih zavisnosti; postojeći repozitorijum i outbox.

## Zavisnosti
Grane 012 i 014 nisu spojene; 014 koristi postojeće `ingredientKey`, `normalizeUnit` i `allocateSupply`. Njihovi postojeći pozivi ostaju kompatibilni, ali 014 samostalno koristi stara pravila pa predlozi Potroši prvo ne prepoznaju nove sinonime; posle integracije treba povezati isti verzionisani obračun i proveriti zajedničku zalihu. Starije verzije aplikacije ignorišu polje verzije u snimku i mogu drugačije obračunati nove planove: mešovite verzije klijenata zahtevaju koordinisano ažuriranje pre objavljivanja.
