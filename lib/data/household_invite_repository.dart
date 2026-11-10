import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

import '../domain/household_invite.dart';

/// Zašto pozivnica nije uspela. Greške sa servera se mapiraju ovde, pa UI
/// ne gleda Postgres kodove.
sealed class HouseholdInviteFailure implements Exception {
  const HouseholdInviteFailure();

  @override
  String toString() => runtimeType.toString();
}

/// Kod ne postoji, istekao je ili je poništen. Namerno jedna greška: ne
/// otkriva se zašto kod ne prolazi.
class InviteUnusable extends HouseholdInviteFailure {
  const InviteUnusable();
}

/// Previše neuspešnih pokušaja u kratkom roku.
class InviteTooManyAttempts extends HouseholdInviteFailure {
  const InviteTooManyAttempts();
}

/// Nalog nema pravo (nije vlasnik domaćinstva).
class InviteForbidden extends HouseholdInviteFailure {
  const InviteForbidden();
}

class InviteOffline extends HouseholdInviteFailure {
  const InviteOffline();
}

class InviteServerError extends HouseholdInviteFailure {
  const InviteServerError();
}

/// Udaljeni sloj za pozivnice (RPC i tabela). Baca [HouseholdInviteFailure].
abstract interface class HouseholdInviteRemote {
  /// Server pravi pozivnicu i vraća njen kod (create_household_invite).
  Future<String> create(String householdId);

  Future<List<HouseholdInvite>> listForHousehold(String householdId);

  Future<void> revoke(String id);

  /// id domaćinstva, ili null kad kod ne prolazi.
  Future<String?> redeem(String code);
}

/// Pozivnice kroz PostgREST i RPC `create_household_invite` /
/// `redeem_household_invite`.
class SupabaseHouseholdInviteRemote implements HouseholdInviteRemote {
  SupabaseHouseholdInviteRemote(this._client);

  final SupabaseClient _client;

  static const _table = 'household_invites';

  @override
  Future<String> create(String householdId) => _guard(() async {
    final code = await _client.rpc<dynamic>(
      'create_household_invite',
      params: {'p_household_id': householdId},
    );
    return code as String;
  });

  @override
  Future<List<HouseholdInvite>> listForHousehold(String householdId) =>
      _guard(() async {
        final rows = await _client.rest
            .from(_table)
            .select()
            .eq('household_id', householdId)
            .order('created_at', ascending: false);
        return [for (final r in rows) _fromRow(r)];
      });

  @override
  Future<void> revoke(String id) => _guard(() async {
    await _client.rest
        .from(_table)
        .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  });

  @override
  Future<String?> redeem(String code) => _guard(() async {
    final result = await _client.rpc<dynamic>(
      'redeem_household_invite',
      params: {'p_code': code},
    );
    return result as String?;
  });

  static HouseholdInvite _fromRow(Map<String, dynamic> r) => HouseholdInvite(
    id: r['id'] as String,
    householdId: r['household_id'] as String,
    code: r['code'] as String,
    createdAt: DateTime.parse(r['created_at'] as String),
    expiresAt: DateTime.parse(r['expires_at'] as String),
    revokedAt: r['revoked_at'] == null
        ? null
        : DateTime.parse(r['revoked_at'] as String),
    uses: r['uses'] as int,
  );

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw switch (e.code) {
        'P0429' => const InviteTooManyAttempts(),
        '42501' => const InviteForbidden(),
        _ => const InviteServerError(),
      };
    } on SocketException {
      throw const InviteOffline();
    } on TimeoutException {
      throw const InviteOffline();
    } on http.ClientException {
      throw const InviteOffline();
    }
  }
}

/// Pozivnice za domaćinstvo: pravljenje (kod pravi server), pregled,
/// poništavanje i unos koda.
class HouseholdInviteRepository {
  HouseholdInviteRepository(this._remote);

  final HouseholdInviteRemote _remote;

  /// Pravi pozivnicu i vraća njen kod za deljenje.
  Future<String> create(String householdId) => _remote.create(householdId);

  Future<List<HouseholdInvite>> listForHousehold(String householdId) =>
      _remote.listForHousehold(householdId);

  Future<void> revoke(HouseholdInvite invite) => _remote.revoke(invite.id);

  /// Unos koda: vraća id domaćinstva u koje je osoba ušla kao član.
  Future<String> redeem(String input) async {
    final householdId = await _remote.redeem(normalizeInviteCode(input));
    if (householdId == null) throw const InviteUnusable();
    return householdId;
  }
}
