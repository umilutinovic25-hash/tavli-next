import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/household_invite.dart';

HouseholdInvite _invite({DateTime? expiresAt, DateTime? revokedAt}) {
  final created = DateTime.utc(2026, 11, 10, 12);
  return HouseholdInvite(
    id: 'inv-1',
    householdId: 'home-1',
    code: 'K7P2MD',
    createdAt: created,
    expiresAt: expiresAt ?? created.add(const Duration(days: 7)),
    revokedAt: revokedAt,
    uses: 0,
  );
}

void main() {
  group('alfabet i dužina koda', () {
    test('alfabet nema dvosmislene znake 0, O, 1, I, L', () {
      for (final bad in ['0', 'O', '1', 'I', 'L']) {
        expect(inviteCodeAlphabet, isNot(contains(bad)), reason: bad);
      }
    });

    test('alfabet ima 31 različit znak', () {
      expect(inviteCodeAlphabet.length, 31);
      expect(inviteCodeAlphabet.split('').toSet().length, 31);
    });

    test('kod ima tačno 6 znakova iz alfabeta', () {
      final random = Random(7);
      for (var i = 0; i < 500; i++) {
        final code = generateInviteCode(random: random);
        expect(code.length, 6);
        for (final ch in code.split('')) {
          expect(inviteCodeAlphabet, contains(ch));
        }
      }
    });

    test('kod sa podrazumevanim izvorom slučajnosti je ispravnog oblika', () {
      final code = generateInviteCode();
      expect(RegExp(r'^[2-9A-HJ-KM-NP-Z]{6}$').hasMatch(code), isTrue);
    });
  });

  group('determinizam', () {
    test('isto seme daje isti kod', () {
      final a = generateInviteCode(random: Random(42));
      final b = generateInviteCode(random: Random(42));
      expect(a, b);
    });

    test('uzastopni kodovi iz istog izvora se razlikuju', () {
      final random = Random(42);
      final codes = {
        for (var i = 0; i < 20; i++) generateInviteCode(random: random),
      };
      expect(codes.length, greaterThan(1));
    });
  });

  group('normalizacija unosa', () {
    test('velika slova i razmaci se uklanjaju', () {
      expect(normalizeInviteCode('  k7p2md '), 'K7P2MD');
    });
  });

  group('isInviteUsable', () {
    final created = DateTime.utc(2026, 11, 10, 12);

    test('aktivna i neistekla pozivnica važi', () {
      expect(
        isInviteUsable(_invite(), created.add(const Duration(days: 1))),
        isTrue,
      );
    });

    test(
      'pozivnica važi tačno do trenutka isteka (isteka u trenutku isteka)',
      () {
        final invite = _invite();
        expect(
          isInviteUsable(
            invite,
            invite.expiresAt.subtract(const Duration(seconds: 1)),
          ),
          isTrue,
        );
        expect(isInviteUsable(invite, invite.expiresAt), isFalse);
      },
    );

    test('istekla pozivnica ne važi', () {
      final invite = _invite(expiresAt: created.add(const Duration(days: 7)));
      expect(
        isInviteUsable(invite, created.add(const Duration(days: 8))),
        isFalse,
      );
    });

    test('poništena pozivnica ne važi ni pre isteka', () {
      final invite = _invite(revokedAt: created.add(const Duration(hours: 1)));
      expect(
        isInviteUsable(invite, created.add(const Duration(hours: 2))),
        isFalse,
      );
    });
  });
}
