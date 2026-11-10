import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:tavli/account/supabase_client.dart';
import 'package:tavli/account/supabase_config.dart';
import 'package:tavli/data/household_membership_repository.dart';
import 'package:tavli/domain/household_role.dart';

import '../helpers/fake_supabase.dart';

void main() {
  group('HouseholdMembershipRepository', () {
    late SupabaseClient client;
    late List<http.Request> requests;
    late http.Response Function(http.Request) handler;

    setUp(() async {
      requests = [];
      client = createSupabaseClient(
        const SupabaseConfig(url: fakeUrl, anonKey: fakeAnonKey),
        httpClient: mockHttp((r) {
          requests.add(r);
          return handler(r);
        }),
      );
      // Važeća sesija se vraća bez mreže.
      handler = (_) => throw StateError('nema mreže u testu');
      await client.auth.recoverSession(jsonEncode(sessionBody()));
      handler = (_) => http.Response('', 200);
    });
    tearDown(() => client.dispose());

    HouseholdMembershipRepository repo() => HouseholdMembershipRepository(
      SupabaseHouseholdMembershipRemote(client),
    );

    http.Response dbError(String message, String code) => jsonResponse({
      'code': code,
      'message': message,
      'details': null,
      'hint': null,
    }, 400);

    test(
      'removeMember zove remove_household_member sa p_household_id i p_user',
      () async {
        await repo().removeMember('h1', 'u2');

        expect(requests, hasLength(1));
        final r = requests.single;
        expect(r.method, 'POST');
        expect(r.url.path, endsWith('/rest/v1/rpc/remove_household_member'));
        expect(jsonDecode(r.body), {'p_household_id': 'h1', 'p_user': 'u2'});
      },
    );

    test('leave zove leave_household sa p_household_id', () async {
      await repo().leave('h1');

      final r = requests.single;
      expect(r.url.path, endsWith('/rest/v1/rpc/leave_household'));
      expect(jsonDecode(r.body), {'p_household_id': 'h1'});
    });

    test('transferOwnership zove transfer_household_ownership sa p_household_id i p_user', () async {
      await repo().transferOwnership('h1', 'u3');

      final r = requests.single;
      expect(r.url.path, endsWith('/rest/v1/rpc/transfer_household_ownership'));
      expect(jsonDecode(r.body), {'p_household_id': 'h1', 'p_user': 'u3'});
    });

    test('mapira kodove grešaka iz baze na tipizovane izuzetke', () async {
      final cases = <String, Matcher>{
        'owner_must_transfer': isA<OwnerMustTransfer>(),
        'not_owner': isA<NotHouseholdOwner>(),
        'not_household_member': isA<NotHouseholdMember>(),
        'cannot_remove_self': isA<CannotRemoveSelf>(),
        'cannot_transfer_to_self': isA<CannotTransferToSelf>(),
        'not_authenticated': isA<MembershipUnauthorized>(),
      };
      for (final entry in cases.entries) {
        handler = (_) => dbError(entry.key, 'P0001');
        await expectLater(
          repo().leave('h1'),
          throwsA(entry.value),
          reason: entry.key,
        );
      }
    });

    test(
      'nepoznata poruka sa 42501 je sesija, ostalo je greška servera',
      () async {
        handler = (_) => dbError('permission denied', '42501');
        await expectLater(
          repo().removeMember('h1', 'u2'),
          throwsA(isA<MembershipUnauthorized>()),
        );

        handler = (_) => dbError('something broke', 'XX000');
        await expectLater(
          repo().removeMember('h1', 'u2'),
          throwsA(isA<MembershipServerError>()),
        );
      },
    );

    test('nema mreže je MembershipOffline', () async {
      handler = (_) => throw const SocketException('offline');
      await expectLater(
        repo().transferOwnership('h1', 'u2'),
        throwsA(isA<MembershipOffline>()),
      );
    });

    test('listMembers zove household_member_list i vraća članove', () async {
      handler = (_) => jsonResponse([
        {
          'user_id': 'u1',
          'display_name': 'Ana',
          'role': 'owner',
          'joined_at': '2026-11-01T10:00:00Z',
        },
        {
          'user_id': 'u2',
          'display_name': null,
          'role': 'member',
          'joined_at': '2026-11-10T10:00:00Z',
        },
      ]);

      final members = await repo().listMembers('h1');

      final r = requests.single;
      expect(r.url.path, endsWith('/rest/v1/rpc/household_member_list'));
      expect(jsonDecode(r.body), {'p_household_id': 'h1'});
      expect(members, hasLength(2));
      expect(members[0].userId, 'u1');
      expect(members[0].displayName, 'Ana');
      expect(members[0].role, HouseholdRole.owner);
      expect(members[1].displayName, isNull);
      expect(members[1].role, HouseholdRole.member);
      expect(members[1].joinedAt, DateTime.utc(2026, 11, 10, 10));
    });

    test('listMembers za ne-člana baca NotHouseholdMember', () async {
      handler = (_) => dbError('not_household_member', '42501');
      await expectLater(
        repo().listMembers('h1'),
        throwsA(isA<NotHouseholdMember>()),
      );
    });

    test('listMembers sa nepoznatom ulogom je greška servera', () async {
      handler = (_) => jsonResponse([
        {
          'user_id': 'u1',
          'display_name': 'Ana',
          'role': 'admin',
          'joined_at': '2026-11-01T10:00:00Z',
        },
      ]);
      await expectLater(
        repo().listMembers('h1'),
        throwsA(isA<MembershipServerError>()),
      );
    });
  });
}
