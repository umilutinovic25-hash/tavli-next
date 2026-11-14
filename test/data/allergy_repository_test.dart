import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/allergy_repository.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/preferences_repository.dart';
import 'package:tavli/domain/user_preferences.dart';
import 'package:tavli/sync/synced_writer.dart';

const scope = AccountScope(userId: 'u1', householdId: 'h1');

void main() {
  late AppDatabase db;
  late AllergyRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = AllergyRepository(
      db,
      scope: scope,
      writer: SyncedWriter(db, accountId: scope.userId),
    );
  });
  tearDown(() => db.close());

  Future<void> insert(String hh, String user, String codes, String custom) => db
      .into(db.memberAllergies)
      .insert(
        MemberAllergiesCompanion.insert(
          id: '$hh:$user',
          householdId: Value(hh),
          userId: user,
          codesJson: Value(codes),
          customJson: Value(custom),
        ),
      );

  test('bez reda: moje alergije su prazne, domaćinstvo bez alergija', () async {
    final mine = await repo.watchMine().first;
    expect(mine.isEmpty, isTrue);
    expect(mine.id, 'h1:u1');
    expect((await repo.current()).isEmpty, isTrue);
  });

  test(
    'saveMine čuva red osobe sa id domaćinstvo:osoba i ide u outbox',
    () async {
      await repo.saveMine(codes: {'peanuts'}, custom: [' Jagode ']);

      final mine = await repo.watchMine().first;
      expect(mine.codes, {'peanuts'});
      expect(mine.custom, ['jagode']);
      final row = (await db.select(db.memberAllergies).get()).single;
      expect((row.id, row.householdId, row.userId), ('h1:u1', 'h1', 'u1'));
      final outbox = await db.select(db.syncOutbox).get();
      expect(outbox.map((r) => '${r.entity}:${r.recordId}:${r.op}'), [
        'member_allergy:h1:u1:upsert',
      ]);
    },
  );

  test('domaćinstvo: unija svih članova aktivnog domaćinstva', () async {
    await insert('h1', 'u1', '["peanuts"]', '[]');
    await insert('h1', 'u2', '["gluten"]', '["kivi"]');
    await insert('h2', 'u3', '["fish"]', '["jagode"]');

    final hh = await repo.current();
    expect(hh.codes, {'peanuts', 'gluten'});
    expect(hh.custom, ['kivi']);
    expect((await repo.watchHousehold().first).labels, [
      'gluten',
      'kikiriki',
      'kivi',
    ]);
  });

  test('nepoznat kod sa servera se preskače, ne ruši čitanje', () async {
    await insert('h1', 'u2', '["peanuts","novi_kod"]', '[]');
    expect((await repo.current()).codes, {'peanuts'});
  });

  test('kasni legacy upis ulazi u zaštitu uz alergije članova', () async {
    await insert('h1', 'u2', '["milk"]', '["kivi"]');
    final prefs = PreferencesRepository(
      db,
      scope: scope,
      writer: SyncedWriter(db, accountId: scope.userId),
    );
    await prefs.save(
      UserPreferences(allergies: ['Kikiriki', 'jaja', 'jagode']),
    );
    await db
        .into(db.householdPreferences)
        .insert(
          HouseholdPreferencesCompanion.insert(
            id: 'h2',
            householdId: const Value('h2'),
            allergiesJson: const Value('["riba"]'),
          ),
        );

    final current = await repo.current();
    expect(current.codes, {'milk', 'peanuts', 'eggs'});
    expect(current.custom, ['kivi', 'jagode']);
    expect((await repo.watchHousehold().first).labels, current.labels);
    expect((await repo.watchMine().first).isEmpty, isTrue);
    expect((await prefs.current()).allergies, ['kikiriki', 'jaja', 'jagode']);
  });

  test('unija prati i kasne izmene legacy alergija', () async {
    final prefs = PreferencesRepository(
      db,
      scope: scope,
      writer: SyncedWriter(db, accountId: scope.userId),
    );
    final values = StreamIterator(repo.watchHousehold());
    addTearDown(values.cancel);
    expect(await values.moveNext(), isTrue);
    expect(values.current.isEmpty, isTrue);
    await prefs.save(UserPreferences(allergies: ['kikiriki']));
    expect(await values.moveNext(), isTrue);
    expect(values.current.codes, {'peanuts'});
    await prefs.save(UserPreferences());
    expect(await values.moveNext(), isTrue);
    expect(values.current.isEmpty, isTrue);
  });
}
