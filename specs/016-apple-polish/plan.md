# Plan
Grana iz origin/main, jedna vizuelna funkcija. Glavna izmena preko postojećih
app_theme, TavliPalette, HomeShell, TabAppBar i EmptyStateScreen; ostatak app-a
nasleđuje iste tokene. TavliBrand nastavlja isti API (compact) kao raniji 011.
Zajednički pregled 011–016 ostaje izolovan u /tmp/tavli-integration-014.

Veština: frontend-ui-engineering. Pročitana taste-skill ima ograničen opseg
landing/portfolio, zato se odluke o produktnim ekranima oslanjaju na prvu veštinu
i Apple HIG: typography, sidebars, motion i materials.

1. Pregledati postojeće teme, navigaciju, animacije i testove.
2. Menjati samo prezentacione tokene, navigacionu oblogu i prazna stanja.
3. Proveriti sve postojeće tokove; dodati vizuelne/responsive provere i captures.
4. Primena u integracionom worktree-u uz očuvanje 014 prečice/016 brenda.
5. Native build sa postojećom lokalnom konfiguracijom, pregled stvarnog rezultata.

Bez novih zavisnosti, šeme, mrežnih poziva ili font fajlova. Standardni Flutter
Cupertino font na Apple platformama. Postojeći animations/motion.dart je jedini
izvor vremena i Reduce Motion ponašanja.

Ustav: srpski Latin; account/cache/sync netaknut; bez AI; nema tajni; nema domenske
izmene; jedna spec/grana; provere obavezne. CI ostaje blokiran odloženom naplatom.
