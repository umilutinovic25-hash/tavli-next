import '../../account/auth_gateway.dart';
import '../../data/household_invite_repository.dart';
import '../../data/household_membership_repository.dart';

/// Greška pozivnice ili članstva kao poruka korisniku. Nikad ne prikazuje
/// tehničke detalje greške.
String householdErrorText(Object error) => switch (error) {
  InviteOffline() ||
  MembershipOffline() ||
  Offline() => 'Za ovo je potrebna internet veza.',
  InviteUnusable() => 'Kod nije važeći ili je istekao.',
  InviteTooManyAttempts() => 'Previše pokušaja. Pokušaj ponovo za 10 minuta.',
  InviteForbidden() || NotHouseholdOwner() => 'Samo vlasnik može to da uradi.',
  NotHouseholdMember() => 'Taj korisnik više nije član domaćinstva.',
  OwnerMustTransfer() => 'Pre napuštanja prenesi vlasništvo drugom članu.',
  _ => 'Nešto nije uspelo. Pokušaj ponovo.',
};
