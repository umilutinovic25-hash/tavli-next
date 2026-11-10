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
/// crtica, velikim slovima. Server radi isto poređenje, ali se normalizuje i
/// na klijentu.
String normalizeInviteCode(String input) =>
    input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

/// Važi ako nije poništena, nije potrošena i ako [now] još nije posle isteka.
bool isInviteUsable(HouseholdInvite invite, DateTime now) =>
    invite.revokedAt == null &&
    invite.usesLeft > 0 &&
    now.isBefore(invite.expiresAt);
