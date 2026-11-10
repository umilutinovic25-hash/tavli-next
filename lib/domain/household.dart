/// Domaćinstvo: članstva korisnika, članovi i tekstovi pozivnice.
/// Čist domen (bez Fluttera i Supabase-a).
library;

import 'household_role.dart';

/// Jedno članstvo prijavljenog korisnika.
class Membership {
  const Membership({
    required this.householdId,
    required this.householdName,
    required this.role,
    required this.joinedAt,
  });

  final String householdId;
  final String householdName;
  final HouseholdRole role;
  final DateTime joinedAt;

  @override
  bool operator ==(Object other) =>
      other is Membership &&
      other.householdId == householdId &&
      other.householdName == householdName &&
      other.role == role &&
      other.joinedAt == joinedAt;

  @override
  int get hashCode => Object.hash(householdId, householdName, role, joinedAt);
}

/// Član domaćinstva kako ga vide ostali članovi: bez imejla.
class HouseholdMember {
  const HouseholdMember({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.joinedAt,
  });

  final String userId;
  final String? displayName;
  final HouseholdRole role;
  final DateTime joinedAt;

  @override
  bool operator ==(Object other) =>
      other is HouseholdMember &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.role == role &&
      other.joinedAt == joinedAt;

  @override
  int get hashCode => Object.hash(userId, displayName, role, joinedAt);
}

/// Aktivno domaćinstvo: ručni izbor ako je još među članstvima, inače ono
/// kome se korisnik poslednje pridružio. Prazna lista je greška.
Membership pickActiveHousehold(List<Membership> all, {String? preferredId}) {
  if (all.isEmpty) throw StateError('Korisnik nema nijedno članstvo');
  if (preferredId != null) {
    for (final m in all) {
      if (m.householdId == preferredId) return m;
    }
  }
  return all.reduce((a, b) => b.joinedAt.isAfter(a.joinedAt) ? b : a);
}

/// "ABCDEFGH" → "ABCD EFGH" (samo za prikaz).
String formatInviteCode(String code) =>
    code.length == 8 ? '${code.substring(0, 4)} ${code.substring(4)}' : code;

/// "Još 1 upotreba", "Još 3 upotrebe", "Još 5 upotreba".
String usesLeftText(int n) {
  final lastTwo = n % 100;
  final last = n % 10;
  final few = last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14);
  return 'Još $n ${few ? 'upotrebe' : 'upotreba'}';
}

/// "17.11.2026." u lokalnom vremenu (isti oblik kao datumi u Ostavi).
String inviteDate(DateTime t) {
  final d = t.toLocal();
  return '${d.day}.${d.month}.${d.year}.';
}

/// Poruka za sistemski meni za deljenje: samo kod i uputstvo.
String inviteShareText(String code) =>
    'Pridruži se mom domaćinstvu u aplikaciji Tavli. Kod: $code. '
    'Otvori Tavli → Profil → Domaćinstvo → Pridruži se kodom.';
