# 040 — Poređenje cena korpe

Iz otvorenih stavki nedeljne, receptne ili celokupne liste korisnik bira proizvod po nazivu ili barkodu i potvrđuje količinu u pakovanju. Po formatu trgovca prikazuju se zbir punih pakovanja, broj pokrivenih stavki i datumi cena. Isti barkod i ista jedinica dele već uračunato pakovanje. Stavke bez količine, potvrđenog proizvoda, pakovanja ili nedvosmislene cene su nepokrivene.

Cenovnici: Delhaize i Europrom; prikazuju se datum preuzimanja, adrese izvora i neuspešni izvori. Čitaju se samo redovi VAZECI_CENOVNIK, sniženja samo u navedenom periodu. Korpa se ne šalje trgovcima. Podaci su informativni i nisu potvrda cene u konkretnoj prodavnici.

Tekst interfejsa je na srpskom latinicom. Cenovnici se čuvaju na uređaju odvojeno po izvoru i koriste kada osvežavanje ne uspe; prikazuju se neuspešni izvori i najstariji datum korišćenog preuzimanja. Izabrani proizvod i pakovanje čuvaju se uz stavku domaćinstva kroz lokalnu bazu i outbox, pa preživljavaju ponovno otvaranje i sinhronizuju se. Promena proizvoda briše prethodno uneto pakovanje.
