import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

import '../domain/household.dart';
import '../domain/household_role.dart';

/// Zašto promena članstva nije uspela. Tada se ništa ne menja.
sealed class MembershipFailure implements Exception {
  const MembershipFailure();

  @override
  String toString() => runtimeType.toString();
}

/// Nema mreže ili je istekao rok. Promena se radi samo online.
class MembershipOffline extends MembershipFailure {
  const MembershipOffline();
}

/// Radnju može da uradi samo vlasnik domaćinstva.
class NotHouseholdOwner extends MembershipFailure {
  const NotHouseholdOwner();
}

/// Osoba nije član tvog domaćinstva.
class NotHouseholdMember extends MembershipFailure {
  const NotHouseholdMember();
}

/// Vlasnik mora prvo da prenese vlasništvo pre napuštanja.
class OwnerMustTransfer extends MembershipFailure {
  const OwnerMustTransfer();
}

/// Ne može sebe da ukloni.
class CannotRemoveSelf extends MembershipFailure {
  const CannotRemoveSelf();
}

/// Ne može vlasništvo da prenese sebi.
class CannotTransferToSelf extends MembershipFailure {
  const CannotTransferToSelf();
}

/// Sesija nije važeća; treba se ponovo prijaviti.
class MembershipUnauthorized extends MembershipFailure {
  const MembershipUnauthorized();
}

/// Neočekivana greška na serveru.
class MembershipServerError extends MembershipFailure {
  const MembershipServerError();
}

/// Server za članstvo (RPC funkcije u bazi); u testovima se lažira.
/// Baca [MembershipFailure].
abstract interface class HouseholdMembershipRemote {
  Future<void> removeMember(String householdId, String userId);

  Future<void> leave(String householdId);

  Future<void> transferOwnership(String householdId, String userId);

  /// Članovi domaćinstva sa imenima (bez imejla).
  Future<List<HouseholdMember>> listMembers(String householdId);
}

/// Operacije nad članstvom kroz Supabase RPC.
class SupabaseHouseholdMembershipRemote implements HouseholdMembershipRemote {
  SupabaseHouseholdMembershipRemote(this._client);

  final SupabaseClient _client;

  @override
  Future<void> removeMember(String householdId, String userId) => _call(
    'remove_household_member',
    {'p_household_id': householdId, 'p_user': userId},
  );

  @override
  Future<void> leave(String householdId) =>
      _call('leave_household', {'p_household_id': householdId});

  @override
  Future<void> transferOwnership(String householdId, String userId) => _call(
    'transfer_household_ownership',
    {'p_household_id': householdId, 'p_user': userId},
  );

  @override
  Future<List<HouseholdMember>> listMembers(String householdId) async {
    final rows = await _guard(
      () => _client.rpc<List<dynamic>>(
        'household_member_list',
        params: {'p_household_id': householdId},
      ),
    );
    return [for (final r in rows) _memberFromRow(r)];
  }

  /// Red neočekivanog oblika ili nepoznata uloga je greška servera.
  static HouseholdMember _memberFromRow(Object? row) {
    if (row case {
      'user_id': final String userId,
      'role': final String role,
      'joined_at': final String joinedAt,
    }) {
      final name = row['display_name'];
      try {
        return HouseholdMember(
          userId: userId,
          displayName: name is String ? name : null,
          role: HouseholdRole.parse(role),
          joinedAt: DateTime.parse(joinedAt),
        );
      } on FormatException {
        throw const MembershipServerError();
      }
    }
    throw const MembershipServerError();
  }

  Future<void> _call(String function, Map<String, Object?> params) =>
      _guard(() => _client.rpc<void>(function, params: params));

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw _classify(e);
    } on SocketException {
      throw const MembershipOffline();
    } on TimeoutException {
      throw const MembershipOffline();
    } on http.ClientException {
      throw const MembershipOffline();
    }
  }

  /// Poruka greške iz baze je mašinski kod (vidi migraciju). Ono što nije
  /// prepoznato ide kao greška na serveru ili kao sesija (42501, 401, PGRST3xx).
  static MembershipFailure _classify(PostgrestException e) {
    final failure = switch (e.message) {
      'owner_must_transfer' => const OwnerMustTransfer(),
      'not_owner' => const NotHouseholdOwner(),
      'not_household_member' => const NotHouseholdMember(),
      'cannot_remove_self' => const CannotRemoveSelf(),
      'cannot_transfer_to_self' => const CannotTransferToSelf(),
      'not_authenticated' => const MembershipUnauthorized(),
      _ => null,
    };
    if (failure != null) return failure;
    final code = e.code ?? '';
    if (code == '42501' || code == '401' || code.startsWith('PGRST3')) {
      return const MembershipUnauthorized();
    }
    return const MembershipServerError();
  }
}

/// Build bez Supabase podešavanja: članstvo nije dostupno (kao bez mreže).
class UnconfiguredHouseholdMembershipRemote
    implements HouseholdMembershipRemote {
  const UnconfiguredHouseholdMembershipRemote();

  @override
  Future<void> removeMember(String householdId, String userId) async =>
      throw const MembershipOffline();

  @override
  Future<void> leave(String householdId) async =>
      throw const MembershipOffline();

  @override
  Future<void> transferOwnership(String householdId, String userId) async =>
      throw const MembershipOffline();

  @override
  Future<List<HouseholdMember>> listMembers(String householdId) async =>
      throw const MembershipOffline();
}

/// Operacije nad članstvom. Baca [MembershipFailure].
class HouseholdMembershipRepository {
  HouseholdMembershipRepository(this._remote);

  final HouseholdMembershipRemote _remote;

  /// Vlasnik [householdId] uklanja člana. Uklonjena osoba dobija novo, prazno
  /// domaćinstvo, ako nema nijedno drugo.
  Future<void> removeMember(String householdId, String userId) =>
      _remote.removeMember(householdId, userId);

  /// Član napušta [householdId]; vlasnik prvo mora da prenese vlasništvo.
  Future<void> leave(String householdId) => _remote.leave(householdId);

  /// Vlasnik [householdId] prenosi vlasništvo članu; on postaje član.
  Future<void> transferOwnership(String householdId, String userId) =>
      _remote.transferOwnership(householdId, userId);

  /// Članovi domaćinstva sa imenima, vlasnik prvi.
  Future<List<HouseholdMember>> listMembers(String householdId) =>
      _remote.listMembers(householdId);
}
