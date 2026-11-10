/// Pozivnica za domaćinstvo: kod koji vlasnik deli, a drugi nalog unosi da
/// bi postao član. Čist domen (bez Fluttera i Supabase-a). Kod pravi server
/// (create_household_invite); klijent ga samo prikazuje i normalizuje unos.
library;

class HouseholdInvite {
  const HouseholdInvite({
    required this.id,
    required this.householdId,
    required this.code,
    required this.createdAt,
    required this.expiresAt,
    required this.uses,
    this.maxUses = 5,
    this.revokedAt,
  });

  final String id;
  final String householdId;
  final String code;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;
  final int uses;

  /// Najviše upotreba (server, podrazumevano 5).
  final int maxUses;

  int get usesLeft => maxUses - uses;
}

/// Kod kako ga unosi ili nalepi korisnik: bez razmaka, preloma reda i
/// crtica, velikim slovima. Iz nalepljene cele poruke za deljenje uzima se
/// kod posle „Kod:“ (ili prva grupa od 8 znakova iz alfabeta koda). Server
/// radi isto poređenje, ali se normalizuje i na klijentu.
String normalizeInviteCode(String input) {
  final stripped = input.replaceAll(_separators, '').toUpperCase();
  if (stripped.length <= 8) return stripped;
  final upper = input.toUpperCase();
  final match =
      RegExp('KOD:\\s*($_group[\\s\\-–—]?$_group)').firstMatch(upper) ??
      RegExp('(?<![A-Z0-9])($_group[\\s\\-–—]?$_group)(?![A-Z0-9])')
          .firstMatch(upper);
  return match == null ? stripped : match.group(1)!.replaceAll(_separators, '');
}

final _separators = RegExp(r'[\s\-–—]');

/// Četiri znaka iz alfabeta koda (bez 0, 1, I, L, O).
const _group = '[2-9A-HJ-KM-NP-Z]{4}';

/// Važi ako nije poništena, nije potrošena i ako [now] još nije posle isteka.
bool isInviteUsable(HouseholdInvite invite, DateTime now) =>
    invite.revokedAt == null &&
    invite.usesLeft > 0 &&
    now.isBefore(invite.expiresAt);
