# Grocy Due Score adaptacija
Izvor: https://github.com/grocy/grocy/blob/41206cb90154e0d17d3e108cc1f182b94fdb465d/migrations/0225.sql

Izvorni blok current_due_status → due_score (oko redova 156–161) je uzor za
prioritet recepata koji koriste zalihe pred istekom. Tavli implementacija
u lib/domain/use_first.dart je prilagođena postojećim količinama, rezervacijama
i kalendaru. Ne izvršava Grocy migraciju i isključuje istekle namirnice,
umesto davanja višeg skora za overdue/expired. Puna MIT licenca je uz ovaj fajl.
