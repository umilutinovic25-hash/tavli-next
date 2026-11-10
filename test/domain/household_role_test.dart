import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/household_role.dart';

void main() {
  group('HouseholdRole.parse', () {
    test('prepoznaje vlasnika i člana', () {
      expect(HouseholdRole.parse('owner'), HouseholdRole.owner);
      expect(HouseholdRole.parse('member'), HouseholdRole.member);
    });

    test('wire vrednost je ista kao u bazi', () {
      expect(HouseholdRole.owner.wire, 'owner');
      expect(HouseholdRole.member.wire, 'member');
    });

    test('nepoznata uloga je greška, ne član ni vlasnik', () {
      expect(
        () => HouseholdRole.parse('admin'),
        throwsA(isA<FormatException>()),
      );
    });

    test('razlikuje velika i mala slova i ne seče razmake', () {
      expect(() => HouseholdRole.parse('Owner'), throwsFormatException);
      expect(() => HouseholdRole.parse(' member'), throwsFormatException);
      expect(() => HouseholdRole.parse(''), throwsFormatException);
    });
  });
}
