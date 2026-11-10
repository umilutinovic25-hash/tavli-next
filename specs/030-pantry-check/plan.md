# Plan

Grana iz najnovijeg origin/main. Nadograditi PantryRepository metodom checkQuantity: pozitivan broj, nula (nestalo) ili null (nepoznato), uz postojeći confirmedAt i sat. Čuvati sve ostale kolone i uraditi reconcileInventory u istoj transakciji. confirmedAt beleži trenutak provere; null quantity i dalje isključuje zalihu iz obračuna. Bez nove šeme, migracije, backend pravila i zavisnosti: kolone i sinhronizacija već postoje.

PantryItemTile dobija meni provere i datum. PantryScreen upravlja upisom i greškom; mali dijalog za potvrdu količine/jedinice čuva unos pri grešci. Upis čita postojeći red u repozitorijumu, bez slanja zastarelog naziva/roka iz UI-ja.

## Constitution Check I–IX
Srpski Latin; postojeći keš/outbox i izolacija domaćinstva; nema AI ni ključeva; testovi repozitorijuma prvo (preračun, izolacija, rollback, prijem), widget tokovi i postojeći susedni testovi; telefon/širok ekran/2×; jedna funkcija i spec na svojoj grani; standardni hook, ceo skup testova i macOS build.
