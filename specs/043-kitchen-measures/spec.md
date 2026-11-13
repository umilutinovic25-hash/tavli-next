# 043 — Kuhinjske mere u sabiranju nabavke

**Status**: Implementirano (čeka PR). **Grana**: `043-kitchen-measures`. Trello: „Kuhinjske mere u sabiranju nabavke“ (Dev 1).

Čaša (200 ml), šolja (250 ml), kašika (15 ml), kašičica (5 ml), dl (100 ml) i
dkg (10 g) se pretvaraju u ml i g, pa se iste namirnice u nabavci sabiraju u
jednu stavku. Zbir nosi `~` samo ako je u njemu učestvovala približna mera
(čaša, šolja, kašika, kašičica); dl i dkg su tačni.

## Odluke
- **Novi rečnik v3** (v0, v1 i v2 su zamrznuti i ne menjaju se). Snimci
  potvrđenih planova od sada nose `dictionaryVersion: 3`; stari planovi i
  zalihe ostaju nepromenjeni (Urošev izbor: samo nove potvrde).
- v3 se ponaša kao v2 (identitet namirnice, zamrznute konverzije) plus tabela
  mera. Zamrznuta konverzija namirnice ima prednost nad opštom merom i nije `~`.
- `~` se čuva po doprinosu (`approximate` na `shopping_contributions`, drift
  v20 + server kolona), da prikaz ne zavisi od ponovnog računanja.
- Komadi (kom) i nepoznate količine se ne menjaju.

## Prihvatanje
- „Jogurt 1 čaša“ + „jogurt 150 ml“ → jedna stavka „~350 ml“.
- „1 kg“ + „500 g“ → „1,5 kg“ bez `~`.
- Plan potvrđen pod v2 ostaje nesabran za čašu (nema `~`, nema spajanja).
