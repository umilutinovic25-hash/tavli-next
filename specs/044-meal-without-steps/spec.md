# 044 — Obrok bez koraka pripreme

**Status**: Implementirano. Trello: „Obrok bez koraka pripreme“ (Dev 1).

Recept koji je samo spisak namirnica sa gramima (užina, obrok iz plana
nutricioniste) normalno prolazi kroz čuvanje i nabavku (već je radilo) i ne
prikazuje prazan deo „Priprema“.

- Ekran recepta i režim kuvanja sakrivaju „Priprema“ i tekst „Koraci pripreme
  nisu uneti.“ kad nema koraka; režim kuvanja tada prikazuje samo sastojke.
  Ekran obroka u planu je to već radio.
- Dodavanje koraka ostaje u formi za izmenu recepta.
- Van opsega: „vrednost po porciji“ iz iste kartice. Zavisi od kartice
  „Kalorije i makroi po porciji recepta“ (nema nutritivnih podataka u kodu).
