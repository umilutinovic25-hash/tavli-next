import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/account_service.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/sync/downloader.dart';

import '../helpers/fake_backend.dart';

/// Posle pridruživanja zajednički podaci mogu biti stariji od pozicije
/// preuzimanja; osvežavanje naloga mora da vrati preuzimanje na početak.
void main() {
  late AppDatabase db;
  late FakeBackend backend;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Map<String, Object?> recipe(String id, String householdId) => {
    'id': id,
    'household_id': householdId,
    'title': id,
    'servings': 4,
    'prep_minutes': null,
    'source': 'manual',
    'ingredients': <Object>[],
    'steps': ['Kuvati.'],
    'image_path': null,
    'answered_by': null,
    'created_at': '2026-10-30T10:00:00.000Z',
  };

  Future<List<String>> localRecipes() async => [
    for (final r in await db.select(db.recipes).get()) r.id,
  ];

  test('pridruženi vidi zajednički recept stariji od svoje pozicije', () async {
    backend = FakeBackend();
    final ana = await backend.auth.verifyCode('ana@mail.com', FakeServer.code);
    final anaHome = backend.server.households[ana.userId]!;
    // Anin recept nastaje prvi (ranije vreme na serveru).
    backend.server.upsert('recipes', [recipe('anin', anaHome)], 'id');

    final marko = await backend.auth.verifyCode(
      'marko@mail.com',
      FakeServer.code,
    );
    final markoHome = backend.server.households[marko.userId]!;
    backend.server.upsert('recipes', [recipe('markov', markoHome)], 'id');

    final service = AccountService(db, backend.accounts);
    await service.loadOrFetch(marko);
    Downloader pull(String householdId) => Downloader(
      db: db,
      remote: backend.sync,
      scope: AccountScope(userId: marko.userId, householdId: householdId),
      // Na lažnom serveru upisi su sekundu jedan od drugog; u stvarnosti su
      // zajednički podaci stari danima, daleko van preklapanja od 60 s.
      overlap: Duration.zero,
    );
    await pull(markoHome).run();
    expect(await localRecipes(), ['markov']);

    // Marko se pridružuje Aninom domaćinstvu.
    backend.server.addMember(anaHome, marko.userId);

    // Bez osvežavanja naloga pozicija ostaje posle Aninog recepta.
    await pull(anaHome).run();
    expect(await localRecipes(), ['markov']);

    final fresh = await service.refresh();
    expect(fresh.householdId, anaHome);
    await pull(anaHome).run();
    expect((await localRecipes())..sort(), ['anin', 'markov']);
  });
}
