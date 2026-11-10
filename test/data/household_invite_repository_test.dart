import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:tavli/account/supabase_client.dart';
import 'package:tavli/account/supabase_config.dart';
import 'package:tavli/data/household_invite_repository.dart';
import 'package:tavli/domain/household_invite.dart';

import '../helpers/fake_supabase.dart';

/// Udaljeni sloj u memoriji: beleži pozive i vraća unapred zadate odgovore.
class FakeInviteRemote implements HouseholdInviteRemote {
  /// Kodovi koji već postoje (sudar pri pravljenju).
  final takenCodes = <String>{};

  /// Ako nije null, svaki unos baca ovu grešku.
  HouseholdInviteFailure? insertFails;

  final insertedCodes = <String>[];
  final rows = <HouseholdInvite>[];
  final revokedIds = <String>[];
  final redeemedCodes = <String>[];

  /// Rezultat unosa koda: id domaćinstva ili null.
  String? redeemResult;

  @override
  Future<HouseholdInvite> insert(String householdId, String code) async {
    insertedCodes.add(code);
    if (insertFails case final f?) throw f;
    if (takenCodes.contains(code)) throw const InviteCodeTaken();
    final invite = HouseholdInvite(
      id: 'inv-${rows.length + 1}',
      householdId: householdId,
      code: code,
      createdAt: DateTime.utc(2026, 11, 10),
      expiresAt: DateTime.utc(2026, 11, 17),
      uses: 0,
    );
    rows.add(invite);
    return invite;
  }

  @override
  Future<List<HouseholdInvite>> listForHousehold(String householdId) async => [
    for (final r in rows)
      if (r.householdId == householdId) r,
  ];

  @override
  Future<void> revoke(String id) async => revokedIds.add(id);

  @override
  Future<String?> redeem(String code) async {
    redeemedCodes.add(code);
    return redeemResult;
  }
}

void main() {
  group('HouseholdInviteRepository', () {
    late FakeInviteRemote remote;

    setUp(() => remote = FakeInviteRemote());

    test('pravi pozivnicu sa generisanim kodom', () async {
      final repo = HouseholdInviteRepository(remote, random: Random(3));
      final invite = await repo.create('home-1');
      expect(invite.householdId, 'home-1');
      expect(invite.code, remote.insertedCodes.single);
      expect(remote.insertedCodes.single.length, 6);
    });

    test('kod sudara se preskače i pravi se novi', () async {
      final first = generateInviteCode(random: Random(3));
      remote.takenCodes.add(first);
      final repo = HouseholdInviteRepository(remote, random: Random(3));

      final invite = await repo.create('home-1');

      expect(remote.insertedCodes.length, 2);
      expect(remote.insertedCodes.first, first);
      expect(invite.code, isNot(first));
    });

    test('posle tri sudara odustaje', () async {
      remote.insertFails = const InviteCodeTaken();
      final repo = HouseholdInviteRepository(remote, random: Random(3));

      await expectLater(repo.create('home-1'), throwsA(isA<InviteCodeTaken>()));
      expect(remote.insertedCodes.length, 3);
    });

    test('ostale greške se ne ponavljaju', () async {
      remote.insertFails = const InviteForbidden();
      final repo = HouseholdInviteRepository(remote, random: Random(3));

      await expectLater(repo.create('home-1'), throwsA(isA<InviteForbidden>()));
      expect(remote.insertedCodes.length, 1);
    });

    test('unos normalizuje kod pre slanja', () async {
      remote.redeemResult = 'home-1';
      final repo = HouseholdInviteRepository(remote);

      expect(await repo.redeem('  k7p2md '), 'home-1');
      expect(remote.redeemedCodes, ['K7P2MD']);
    });

    test('neupotrebljiv kod daje jednu grešku bez razloga', () async {
      remote.redeemResult = null;
      final repo = HouseholdInviteRepository(remote);

      await expectLater(repo.redeem('ZZZZZZ'), throwsA(isA<InviteUnusable>()));
    });

    test('poništavanje šalje id pozivnice', () async {
      final repo = HouseholdInviteRepository(remote, random: Random(3));
      final invite = await repo.create('home-1');

      await repo.revoke(invite);

      expect(remote.revokedIds, [invite.id]);
    });

    test('pregled vraća pozivnice domaćinstva', () async {
      final repo = HouseholdInviteRepository(remote, random: Random(3));
      await repo.create('home-1');
      await repo.create('home-2');

      final mine = await repo.listForHousehold('home-1');

      expect(mine.map((i) => i.householdId), ['home-1']);
    });
  });

  group('SupabaseHouseholdInviteRemote (mapiranje grešaka)', () {
    late SupabaseClient client;
    late List<http.Request> requests;
    late FutureOr<http.Response> Function(http.Request) handler;
    late SupabaseHouseholdInviteRemote remote;

    setUp(() {
      requests = [];
      handler = (_) => jsonResponse(null);
      client = createSupabaseClient(
        const SupabaseConfig(url: fakeUrl, anonKey: fakeAnonKey),
        httpClient: mockHttp((r) {
          requests.add(r);
          return handler(r);
        }),
      );
      remote = SupabaseHouseholdInviteRemote(client);
    });
    tearDown(() => client.dispose());

    Map<String, Object?> pgError(String code, String message) => {
      'code': code,
      'message': message,
      'details': null,
      'hint': null,
    };

    test('redeem šalje p_code i vraća id domaćinstva', () async {
      handler = (_) => jsonResponse('home-1');

      expect(await remote.redeem('K7P2MD'), 'home-1');

      final r = requests.single;
      expect(r.method, 'POST');
      expect(r.url.path, '/rest/v1/rpc/redeem_household_invite');
      expect(jsonDecode(r.body), {'p_code': 'K7P2MD'});
    });

    test('redeem bez pogodka vraća null', () async {
      handler = (_) => jsonResponse(null);
      expect(await remote.redeem('ZZZZZZ'), isNull);
    });

    test('P0429 je previše pokušaja', () async {
      handler = (_) => jsonResponse(pgError('P0429', 'too_many_attempts'), 400);
      await expectLater(
        remote.redeem('K7P2MD'),
        throwsA(isA<InviteTooManyAttempts>()),
      );
    });

    test('42501 je zabranjeno', () async {
      handler = (_) => jsonResponse(
        pgError('42501', 'new row violates row-level security policy'),
        403,
      );
      await expectLater(
        remote.insert('home-1', 'K7P2MD'),
        throwsA(isA<InviteForbidden>()),
      );
    });

    test('23505 je zauzet kod', () async {
      handler = (_) => jsonResponse(
        pgError('23505', 'duplicate key value violates unique constraint'),
        409,
      );
      await expectLater(
        remote.insert('home-1', 'K7P2MD'),
        throwsA(isA<InviteCodeTaken>()),
      );
    });

    test('nepoznata greška je greška servera', () async {
      handler = (_) => jsonResponse(pgError('XX000', 'boom'), 500);
      await expectLater(
        remote.listForHousehold('home-1'),
        throwsA(isA<InviteServerError>()),
      );
    });

    test('nema mreže je offline', () async {
      handler = (_) => throw const SocketException('offline');
      await expectLater(remote.redeem('K7P2MD'), throwsA(isA<InviteOffline>()));
    });

    test('insert šalje household_id i kod, vraća pozivnicu', () async {
      handler = (_) => jsonResponse({
        'id': 'inv-9',
        'household_id': 'home-1',
        'code': 'K7P2MD',
        'created_at': '2026-11-10T12:00:00+00:00',
        'expires_at': '2026-11-17T12:00:00+00:00',
        'revoked_at': null,
        'uses': 0,
      }, 201);

      final invite = await remote.insert('home-1', 'K7P2MD');

      expect(jsonDecode(requests.single.body), {
        'household_id': 'home-1',
        'code': 'K7P2MD',
      });
      expect(invite.id, 'inv-9');
      expect(invite.expiresAt.toUtc(), DateTime.utc(2026, 11, 17, 12));
      expect(invite.revokedAt, isNull);
    });
  });
}
