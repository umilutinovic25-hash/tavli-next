/// Uloga u domaćinstvu, kako je zapisana u `household_members.role`.
enum HouseholdRole {
  owner('owner'),
  member('member');

  const HouseholdRole(this.wire);

  /// Vrednost u bazi.
  final String wire;

  /// Nepoznata vrednost je greška: ne sme da se tumači kao član ili vlasnik.
  static HouseholdRole parse(String value) {
    for (final role in values) {
      if (role.wire == value) return role;
    }
    throw FormatException('Unknown household role', value);
  }
}
