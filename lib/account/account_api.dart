import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

import '../domain/household.dart';
import '../domain/household_role.dart';
import 'auth_gateway.dart';

/// Profil i domaćinstvo prijavljene osobe kako ih vidi server.
class RemoteAccount {
  const RemoteAccount({
    required this.userId,
    required this.email,
    required this.householdId,
    required this.householdName,
    required this.role,
    this.displayName,
    this.memberships = const [],
  });

  final String userId;
  final String email;
  final String? displayName;
  final String householdId;
  final String householdName;
  final String role;

  /// Sva članstva, od poslednjeg pridruživanja ka najstarijem. Polja iznad
  /// opisuju prvo (poslednje pridruženo) članstvo.
  final List<Membership> memberships;
}

/// Zašto brisanje naloga nije uspelo; na uređaju se tada ništa ne briše.
sealed class DeleteFailure implements Exception {
  const DeleteFailure();

  @override
  String toString() => runtimeType.toString();
}

class DeleteOffline extends DeleteFailure {
  const DeleteOffline();
}

class DeleteServerError extends DeleteFailure {
  const DeleteServerError();
}

class DeleteUnauthorized extends DeleteFailure {
  const DeleteUnauthorized();
}

abstract interface class AccountApi {
  /// Svoj profil, članstvo i domaćinstvo. Baca `AuthFailure`.
  Future<RemoteAccount> fetch();

  /// Edge Function `delete-account`. Baca [DeleteFailure].
  Future<void> deleteAccount();
}

/// Profil i domaćinstvo iz Supabase-a (RLS: samo svoje).
class SupabaseAccountApi implements AccountApi {
  SupabaseAccountApi(
    this._client, {
    this.retryDelay = const Duration(milliseconds: 500),
  });

  final SupabaseClient _client;

  /// Pauza između pokušaja dok okidač na serveru ne napravi domaćinstvo.
  final Duration retryDelay;

  static const _attempts = 3;

  @override
  Future<RemoteAccount> fetch() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const SessionRevoked();
    for (var attempt = 1; ; attempt++) {
      final (profiles, members) = await _guard(
        () async => (
          await _client.rest
              .from('profiles')
              .select('id, email, display_name')
              .eq('id', uid)
              .limit(1),
          await _client.rest
              .from('household_members')
              .select('household_id, role, joined_at, households(name)')
              .eq('user_id', uid)
              // Posle pozivnice korisnik ima i lično i pridruženo
              // domaćinstvo; prvo je ono kome se poslednje pridružio.
              .order('joined_at', ascending: false),
        ),
      );
      if (profiles.isNotEmpty && members.isNotEmpty) {
        final p = profiles.first;
        final m = members.first;
        final household = m['households'] as Map<String, dynamic>?;
        return RemoteAccount(
          userId: uid,
          email: p['email'] as String? ?? '',
          displayName: p['display_name'] as String?,
          householdId: m['household_id'] as String,
          householdName: household?['name'] as String? ?? 'Moje domaćinstvo',
          role: m['role'] as String? ?? 'owner',
          memberships: [for (final row in members) _membership(row)],
        );
      }
      if (attempt == _attempts) throw const Unavailable();
      await Future<void>.delayed(retryDelay);
    }
  }

  /// Red članstva; nepoznata uloga znači da server i aplikacija nisu
  /// usklađeni, pa nalog trenutno nije dostupan.
  static Membership _membership(Map<String, dynamic> row) {
    final household = row['households'] as Map<String, dynamic>?;
    final HouseholdRole role;
    try {
      role = HouseholdRole.parse(row['role'] as String? ?? 'owner');
    } on FormatException {
      throw const Unavailable();
    }
    return Membership(
      householdId: row['household_id'] as String,
      householdName: household?['name'] as String? ?? 'Moje domaćinstvo',
      role: role,
      joinedAt:
          DateTime.tryParse(row['joined_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  @override
  Future<void> deleteAccount() async {
    try {
      await _client.functions.invoke('delete-account');
    } on FunctionException catch (e) {
      throw e.status == 401
          ? const DeleteUnauthorized()
          : const DeleteServerError();
    } on SocketException {
      throw const DeleteOffline();
    } on TimeoutException {
      throw const DeleteOffline();
    } on http.ClientException {
      throw const DeleteOffline();
    }
  }

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      final code = e.code ?? '';
      if (code == '401' || code.startsWith('PGRST3')) {
        throw const SessionRevoked();
      }
      throw const Unavailable();
    } on SocketException {
      throw const Offline();
    } on TimeoutException {
      throw const Offline();
    } on http.ClientException {
      throw const Offline();
    }
  }
}

/// Build bez Supabase podešavanja.
class UnconfiguredAccountApi implements AccountApi {
  const UnconfiguredAccountApi();

  @override
  Future<RemoteAccount> fetch() async => throw const Unavailable();

  @override
  Future<void> deleteAccount() async => throw const DeleteServerError();
}
