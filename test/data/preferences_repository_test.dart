import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/preferences_repository.dart';
import 'package:tavli/domain/user_preferences.dart';
import 'package:tavli/sync/synced_writer.dart';

const scope = AccountScope(userId: 'u1', householdId: 'h1');

void main() {
  late AppDatabase db;
  late PreferencesRepository prefs;

  PreferencesRepository repoFor(AccountScope s) => PreferencesRepository(
    db,
    scope: s,
    writer: SyncedWriter(db, accountId: s.userId),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    prefs = repoFor(scope);
  });
  tearDown(() => db.close());

  Future<List<String>> outbox() async => [
    for (final r in await db.select(db.syncOutbox).get())
      '${r.entity}:${r.recordId}:${r.op}',
  ];

  test('bez reda su podrazumevane preferencije', () async {
    expect(await prefs.watch().first, UserPreferences.defaults);
    expect(await prefs.current(), UserPreferences.defaults);
    expect(await outbox(), isEmpty);
  });

  test(
    'čuva ishranu, liste i porcije; id je domaćinstvo; ide u outbox',
    () async {
      final saved = UserPreferences(
        diet: const [FoodDiet.lactoseFree, FoodDiet.vegetarian],
        dislikes: const ['Pasulj', 'kupus'],
        allergies: const ['orasi'],
        servings: 4,
      );
      await prefs.save(saved);

      expect(await prefs.watch().first, saved);
      expect(await prefs.current(), saved);
      final row = await db.select(db.householdPreferences).getSingle();
      expect(row.id, 'h1');
      expect(row.householdId, 'h1');
      // Ishrana se čuva u stalnom redosledu enuma, ne po redosledu unosa.
      expect(row.dietJson, '["vegetarian","lactoseFree"]');
      expect(row.dislikesJson, '["pasulj","kupus"]');
      expect(await outbox(), ['household_preference:h1:upsert']);
    },
  );

  test('ponovno čuvanje menja red i ne dupla izmenu u outbox-u', () async {
    await prefs.save(UserPreferences(servings: 3));
    await prefs.save(UserPreferences(servings: 6));
    expect((await prefs.current()).servings, 6);
    expect(await db.select(db.householdPreferences).get(), hasLength(1));
    expect(await outbox(), ['household_preference:h1:upsert']);
  });

  test('preferencije su odvojene po domaćinstvu', () async {
    await prefs.save(UserPreferences(allergies: const ['orasi']));
    final theirs = repoFor(const AccountScope(userId: 'u2', householdId: 'h2'));
    expect(await theirs.current(), UserPreferences.defaults);
  });

  test('bez prijavljenog domaćinstva nema upisa', () async {
    final none = repoFor(noAccountScope);
    expect(() => none.save(UserPreferences.defaults), throwsStateError);
    expect(await db.select(db.householdPreferences).get(), isEmpty);
  });
}
