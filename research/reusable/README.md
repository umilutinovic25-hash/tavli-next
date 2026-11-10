# Preuzeti referentni kod

Tri puna izvorna fajla i tri originalne licence, preuzeti direktno sa tačno
navedenih upstream commit-a. Manifest [sources.lock.json](sources.lock.json)
beleži URL, commit, putanju, veličinu i SHA-256 svakog fajla.

| Projekat / fajl | Zašto je koristan | Stanje u Tavliju |
|---|---|---|
| [Grocy](https://github.com/grocy/grocy), `migrations/0225.sql` | SQL primer skaliranja, pokrića recepta i Due Score po stanju roka. | Referenca za buduće „Potroši prvo“. Nije primenjena migracija. Tavli ima drugu šemu i postojeće pravilo o isteklim zalihama. |
| [CookCLI](https://github.com/cooklang/cookcli), `crates/core/src/fs_atomic.rs` | Privremeni fajl, flush i atomic rename pri čuvanju izvoza. | Referenca za budući izvoz; trenutni upisi ostaju Drift/outbox transakcije. |
| [recipe-scrapers](https://github.com/hhursev/recipe-scrapers), `recipe_scrapers/_schemaorg.py` | Obrada schema.org Recipe i JSON-LD/microdata strukture. | Referenca za budući URL uvoz. Python fajl sam ne predstavlja ceo paket ili izvršivu integraciju. |

Sva tri projekta za izabrane fajlove isporučuju MIT licencu; puni tekstovi
sa attribution notice-ima su sačuvani uz kod. Nijedan preuzeti fajl nije
importovan iz `lib/`, izvršavan ili dodat kao zavisnost. Runtime mreža/lista
je nova Flutter implementacija opštih dizajn-obrazaca, ne prekopiran zatvoren
Crouton/Paprika/Umami izvor.

Ne prenositi ove SQL/Rust/Python fajlove direktno u Tavli backend ili bazu.
Svaka buduća adaptacija zahteva postojeće modele, testove, outbox i zasebnu
specifikaciju. Celoviti paketi i njihove zavisnosti nisu ovde preuzimani.
