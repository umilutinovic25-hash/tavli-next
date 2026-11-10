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

/// Kod kako ga unosi korisnik: bez razmaka i velikim slovima. Server radi
/// isto poređenje, ali se normalizuje i na klijentu.
String normalizeInviteCode(String input) => input.trim().toUpperCase();

/// Važi ako nije poništena i ako [now] još nije posle isteka.
bool isInviteUsable(HouseholdInvite invite, DateTime now) =>
    invite.revokedAt == null && now.isBefore(invite.expiresAt);
