import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

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

/// Operacije nad članstvom (RPC funkcije u bazi). Baca [MembershipFailure].
class HouseholdMembershipRepository {
  HouseholdMembershipRepository(this._client);

  final SupabaseClient _client;

  /// Vlasnik uklanja člana. Uklonjena osoba dobija novo, prazno domaćinstvo.
  Future<void> removeMember(String userId) =>
      _call('remove_household_member', {'p_user': userId});

  /// Član napušta domaćinstvo; vlasnik prvo mora da prenese vlasništvo.
  Future<void> leave() => _call('leave_household', const {});

  /// Vlasnik prenosi vlasništvo članu istog domaćinstva; on postaje član.
  Future<void> transferOwnership(String userId) =>
      _call('transfer_household_ownership', {'p_user': userId});

  Future<void> _call(String function, Map<String, Object?> params) async {
    try {
      await _client.rpc<void>(function, params: params);
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
