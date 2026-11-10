import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:tavli/account/supabase_client.dart';
import 'package:tavli/account/supabase_config.dart';
import 'package:tavli/data/household_invite_repository.dart';
import 'package:tavli/domain/household_invite.dart';

import '../helpers/fake_supabase.dart';

/// Udaljeni sloj u memoriji: server pravi kod, beleži pozive i vraća unapred
/// zadate odgovore.
class FakeInviteRemote implements HouseholdInviteRemote {
  /// Ako nije null, svaki zahtev za kod baca ovu grešku.
  HouseholdInviteFailure? createFails;

  final createdFor = <String>[];
  final rows = <HouseholdInvite>[];
  final revokedIds = <String>[];
  final redeemedCodes = <String>[];

  /// Rezultat unosa koda: id domaćinstva ili null.
  String? redeemResult;

  @override
  Future<String> create(String householdId) async {
    createdFor.add(householdId);
    if (createFails case final f?) throw f;
    final code = 'CODE${(rows.length + 1).toString().padLeft(4, '0')}';
    rows.add(
      HouseholdInvite(
        id: 'inv-${rows.length + 1}',
        householdId: householdId,
        code: code,
        createdAt: DateTime.utc(2026, 11, 10),
        expiresAt: DateTime.utc(2026, 11, 17),
        uses: 0,
      ),
    );
    return code;
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

    test('pravi pozivnicu kroz server i vraća njen kod', () async {
      final repo = HouseholdInviteRepository(remote);

      final code = await repo.create('home-1');

      expect(remote.createdFor, ['home-1']);
      expect(code, 'CODE0001');
      expect(remote.rows.single.code, code);
    });

    test('greška servera se prosleđuje bez ponavljanja', () async {
      remote.createFails = const InviteForbidden();
      final repo = HouseholdInviteRepository(remote);

      await expectLater(repo.create('home-1'), throwsA(isA<InviteForbidden>()));
      expect(remote.createdFor.length, 1);
    });

    test('unos normalizuje kod pre slanja', () async {
      remote.redeemResult = 'home-1';
      final repo = HouseholdInviteRepository(remote);

      expect(await repo.redeem('  k7p2mdxn '), 'home-1');
      expect(remote.redeemedCodes, ['K7P2MDXN']);
    });

    test('neupotrebljiv kod daje jednu grešku bez razloga', () async {
      remote.redeemResult = null;
      final repo = HouseholdInviteRepository(remote);

      await expectLater(
        repo.redeem('ZZZZZZZZ'),
        throwsA(isA<InviteUnusable>()),
      );
    });

    test('poništavanje šalje id pozivnice', () async {
      final repo = HouseholdInviteRepository(remote);
      await repo.create('home-1');
      final invite = remote.rows.single;

      await repo.revoke(invite);

      expect(remote.revokedIds, [invite.id]);
    });

    test('pregled vraća pozivnice domaćinstva', () async {
      final repo = HouseholdInviteRepository(remote);
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

      expect(await remote.redeem('K7P2MDXN'), 'home-1');

      final r = requests.single;
      expect(r.method, 'POST');
      expect(r.url.path, '/rest/v1/rpc/redeem_household_invite');
      expect(jsonDecode(r.body), {'p_code': 'K7P2MDXN'});
    });

    test('redeem bez pogodka vraća null', () async {
      handler = (_) => jsonResponse(null);
      expect(await remote.redeem('ZZZZZZZZ'), isNull);
    });

    test('P0429 je previše pokušaja', () async {
      handler = (_) => jsonResponse(pgError('P0429', 'too_many_attempts'), 400);
      await expectLater(
        remote.redeem('K7P2MDXN'),
        throwsA(isA<InviteTooManyAttempts>()),
      );
    });

    test('42501 je zabranjeno', () async {
      handler = (_) => jsonResponse(pgError('42501', 'not_owner'), 403);
      await expectLater(
        remote.create('home-1'),
        throwsA(isA<InviteForbidden>()),
      );
    });

    test('istekla sesija (401 / PGRST301) je opozvana sesija', () async {
      handler = (_) => jsonResponse(pgError('PGRST301', 'JWT expired'), 401);
      await expectLater(
        remote.redeem('K7P2MDXN'),
        throwsA(isA<InviteUnauthorized>()),
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
      await expectLater(
        remote.redeem('K7P2MDXN'),
        throwsA(isA<InviteOffline>()),
      );
    });

    test('create šalje household_id na RPC i vraća kod iz servera', () async {
      handler = (_) => jsonResponse('K7P2MDXN');

      final code = await remote.create('home-1');

      final r = requests.single;
      expect(r.method, 'POST');
      expect(r.url.path, '/rest/v1/rpc/create_household_invite');
      expect(jsonDecode(r.body), {'p_household_id': 'home-1'});
      expect(code, 'K7P2MDXN');
    });

    Map<String, Object?> inviteRow({int? maxUses, int uses = 0}) => {
      'id': 'inv-1',
      'household_id': 'home-1',
      'code': 'K7P2MDXN',
      'created_at': '2026-11-10T12:00:00Z',
      'expires_at': '2026-11-17T12:00:00Z',
      'revoked_at': null,
      'uses': uses,
      'max_uses': ?maxUses,
    };

    test('pregled čita max_uses i preostale upotrebe', () async {
      handler = (_) => jsonResponse([inviteRow(maxUses: 3, uses: 1)]);

      final invite = (await remote.listForHousehold('home-1')).single;

      expect(invite.maxUses, 3);
      expect(invite.usesLeft, 2);
    });

    test('red bez max_uses daje podrazumevanih 5', () async {
      handler = (_) => jsonResponse([inviteRow()]);

      expect((await remote.listForHousehold('home-1')).single.maxUses, 5);
    });
  });
}
