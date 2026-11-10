import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/household.dart';
import 'package:tavli/domain/household_role.dart';

Membership _m(String id, DateTime joinedAt) => Membership(
  householdId: id,
  householdName: 'Domaćinstvo $id',
  role: HouseholdRole.member,
  joinedAt: joinedAt,
);

void main() {
  group('pickActiveHousehold', () {
    final own = _m('home-1', DateTime.utc(2026, 11));
    final joined = _m('home-2', DateTime.utc(2026, 11, 10));

    test('bez izbora: poslednje pridruženo', () {
      expect(pickActiveHousehold([own, joined]), joined);
      expect(pickActiveHousehold([joined, own]), joined);
    });

    test('izbor koji postoji ima prednost', () {
      expect(pickActiveHousehold([own, joined], preferredId: 'home-1'), own);
    });

    test('izbor koji više ne postoji: poslednje pridruženo', () {
      expect(pickActiveHousehold([own, joined], preferredId: 'home-9'), joined);
    });

    test('prazna lista je greška', () {
      expect(() => pickActiveHousehold([]), throwsStateError);
    });
  });

  test('Membership i HouseholdMember se porede po vrednosti', () {
    expect(_m('home-1', DateTime.utc(2026)), _m('home-1', DateTime.utc(2026)));
    final a = HouseholdMember(
      userId: 'u1',
      displayName: null,
      role: HouseholdRole.owner,
      joinedAt: DateTime.utc(2026),
    );
    final b = HouseholdMember(
      userId: 'u1',
      displayName: null,
      role: HouseholdRole.owner,
      joinedAt: DateTime.utc(2026),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('formatInviteCode deli kod u dve grupe po četiri', () {
    expect(formatInviteCode('ABCDEFGH'), 'ABCD EFGH');
  });

  test('usesLeftText prati srpsku množinu', () {
    expect(usesLeftText(1), 'Još 1 upotreba');
    expect(usesLeftText(2), 'Još 2 upotrebe');
    expect(usesLeftText(3), 'Još 3 upotrebe');
    expect(usesLeftText(4), 'Još 4 upotrebe');
    expect(usesLeftText(5), 'Još 5 upotreba');
    expect(usesLeftText(11), 'Još 11 upotreba');
    expect(usesLeftText(12), 'Još 12 upotreba');
    expect(usesLeftText(21), 'Još 21 upotreba');
    expect(usesLeftText(22), 'Još 22 upotrebe');
  });

  test('inviteDate je d.m.gggg.', () {
    expect(inviteDate(DateTime(2026, 11, 17)), '17.11.2026.');
    expect(inviteDate(DateTime(2026, 3, 7)), '7.3.2026.');
  });

  test('inviteShareText sadrži kod i uputstvo', () {
    expect(
      inviteShareText('ABCDEFGH'),
      'Pridruži se mom domaćinstvu u aplikaciji Tavli. Kod: ABCDEFGH. '
      'Otvori Tavli → Profil → Domaćinstvo → Pridruži se kodom.',
    );
  });
}
