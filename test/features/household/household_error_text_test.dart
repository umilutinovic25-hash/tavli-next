import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_gateway.dart';
import 'package:tavli/data/household_invite_repository.dart';
import 'package:tavli/data/household_membership_repository.dart';
import 'package:tavli/features/household/household_error_text.dart';

void main() {
  const offline = 'Za ovo je potrebna internet veza.';
  const generic = 'Nešto nije uspelo. Pokušaj ponovo.';

  test('svaka poznata greška ima svoj tekst', () {
    final cases = <Object, String>{
      const InviteOffline(): offline,
      const MembershipOffline(): offline,
      const Offline(): offline,
      const InviteUnusable(): 'Kod nije važeći ili je istekao.',
      const InviteTooManyAttempts():
          'Previše pokušaja. Pokušaj ponovo za 10 minuta.',
      const InviteForbidden(): 'Samo vlasnik može to da uradi.',
      const NotHouseholdOwner(): 'Samo vlasnik može to da uradi.',
      const NotHouseholdMember(): 'Taj korisnik više nije član domaćinstva.',
      const OwnerMustTransfer():
          'Pre napuštanja prenesi vlasništvo drugom članu.',
      const InviteServerError(): generic,
      const MembershipServerError(): generic,
      const CannotRemoveSelf(): generic,
    };
    for (final MapEntry(key: error, value: text) in cases.entries) {
      expect(householdErrorText(error), text, reason: '$error');
    }
  });

  test('nepoznata greška daje opšti tekst bez detalja', () {
    final text = householdErrorText(StateError('tajni detalj'));
    expect(text, generic);
    expect(text, isNot(contains('tajni')));
  });
}
