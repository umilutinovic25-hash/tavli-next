/// Pozivnica za domaćinstvo: kod koji vlasnik deli, a drugi nalog unosi da
/// bi postao član. Čist domen (bez Fluttera i Supabase-a).
library;

import 'dart:math';

/// Dozvoljeni znaci za kod: bez 0, O, 1, I i L, jer se lako mešaju pri
/// čitanju i prepisivanju. Mora da se slaže sa proverom u bazi.
const inviteCodeAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
const inviteCodeLength = 6;

class HouseholdInvite {
  const HouseholdInvite({
    required this.id,
    required this.householdId,
    required this.code,
    required this.createdAt,
    required this.expiresAt,
    required this.uses,
    this.revokedAt,
  });

  final String id;
  final String householdId;
  final String code;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;
  final int uses;
}

/// Nasumičan kod od [inviteCodeLength] znakova iz [inviteCodeAlphabet].
String generateInviteCode({Random? random}) {
  final r = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < inviteCodeLength; i++)
      inviteCodeAlphabet.codeUnitAt(r.nextInt(inviteCodeAlphabet.length)),
  ]);
}

/// Kod kako ga unosi korisnik: bez razmaka i velikim slovima. Server radi
/// isto poređenje, ali se normalizuje i na klijentu.
String normalizeInviteCode(String input) => input.trim().toUpperCase();

/// Važi ako nije poništena i ako [now] još nije posle isteka.
bool isInviteUsable(HouseholdInvite invite, DateTime now) =>
    invite.revokedAt == null && now.isBefore(invite.expiresAt);
