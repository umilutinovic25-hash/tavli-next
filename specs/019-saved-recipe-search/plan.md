# Plan

Postojeći RecipeRepository i ekran proširuju se pretragama. Drift v6 i lična serverska tabela sa RLS, grantovima i tombstone okidačima koriste postojeći sync registar. Filter je čist domen; bez novih zavisnosti. Prazan spisak sastojaka nije dokaz odsustva. Rečnik sinonima #02 je nezavisna, nespojena grana; integracija ostaje naknadna.

Constitution Check I–IX: srpski UI; lokalni cache/outbox i RLS; bez AI/ključeva; testovi domena, migracije, synca, RLS i UI; responzivan postojeći ekran; jedan spec i grana; generisana baza kroz build_runner. Nema izuzetaka.

Provera integracije: grana 018 je započeta sa istog main-a i pri pregledu još nema commit; u njenom radnom diff-u normalizacija se menja u domenu nabavke, dok ova grana koristi postojeću normalizaciju tekstualne pretrage recepata. Nakon spajanja 018 potrebno je zasebno povezati potvrđene sinonime sa pretragom, uz proveru značenja isključivanja. Paralelne grane koje dodaju Drift tabele moraće uskladiti verziju i generisanu šemu pri integraciji.

Provere: flutter analyze; 570 Flutter testova; posebni widget testovi offline na telefonu i širokom ekranu; lokalni pgTAP SQL testovi sa dva naloga izvršeni direktno kroz psql jer CLI nije pronašao datoteke; macOS debug build sa DEVELOPER_DIR na instalirani Xcode.
