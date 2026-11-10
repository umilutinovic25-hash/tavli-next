# Veze sastojaka i koraka

U formi recepta, ispod koraka, odeljak „Sastojci po koracima“ za svaki korak nudi „Poveži“: osoba bira sastojke koji se koriste u tom koraku i, po želji, količinu baš za taj korak (npr. brašno 500 g: 300 g u prvom i 200 g u trećem koraku). U detaljima recepta ispod koraka stoji „↳ 300 g brašno“; upotreba bez količine pokazuje samo naziv, jer se nepoznata raspodela ne izmišlja. Ako upotrebe zajedno prelaze količinu u receptu (600 g od 500 g), prikazuje se upozorenje, a recept se ne menja.

Veze prate sastojak po stalnom id-ju i korak po tekstu: premeštanje sastojaka ili koraka ih čuva, izmenjen tekst koraka gubi samo svoje veze, ponovljen tekst se poravnava redom. Uklanjanje sastojka koji se koristi traži potvrdu, a veza ostaje vidljiva kao „Sastojak više nije u receptu“ dok je osoba ne isključi. AI izmena recepta zadržava veze sastojaka istog naziva i nepromenjenih koraka. Veze idu u prethodne verzije recepta i u snimak recepta u planu. Recept bez veza (svi postojeći) ostaje isti, sa istim tekstom, količinama i zapisom.

Tekst: „Sastojci po koracima“, „Poveži sastojke sa korakom u kome se koriste.“, „Poveži“, „Sastojci u koraku“, „Količina u ovom koraku (nije obavezno)“, „Sačuvaj“, „Otkaži“, „↳ …“, „Sastojak više nije u receptu“, „„…“: koraci koriste X, a recept ima Y.“, „Ukloniti „…“?“, „Koristi se u N koraka. Te veze ostaju označene kao „Sastojak više nije u receptu“ dok ih ne izmeniš.“, „Ukloni“.

Prikaz veza u obroku plana i režimu kuvanja, automatski predlog veza i vremena/temperature uz korak nisu deo ove funkcije.
