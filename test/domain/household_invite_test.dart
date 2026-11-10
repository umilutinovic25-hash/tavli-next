import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/household_invite.dart';

HouseholdInvite _invite({
  DateTime? expiresAt,
  DateTime? revokedAt,
  int uses = 0,
  int maxUses = 5,
}) {
  final created = DateTime.utc(2026, 11, 10, 12);
  return HouseholdInvite(
    id: 'inv-1',
    householdId: 'home-1',
    code: 'K7P2MDXN',
    createdAt: created,
    expiresAt: expiresAt ?? created.add(const Duration(days: 7)),
    revokedAt: revokedAt,
    uses: uses,
    maxUses: maxUses,
  );
}

void main() {
  group('normalizacija unosa', () {
    test('velika slova i razmaci se uklanjaju', () {
      expect(normalizeInviteCode('  k7p2mdxn '), 'K7P2MDXN');
    });

    test('nalepljen kod sa crticom, razmacima i prelomom reda', () {
      expect(normalizeInviteCode(' abcd-efgh\n'), 'ABCDEFGH');
      expect(normalizeInviteCode('AB CD EF GH'), 'ABCDEFGH');
      expect(normalizeInviteCode('abcd\tefgh'), 'ABCDEFGH');
    });

    test('kod ostaje 8 znakova posle normalizacije', () {
      expect(normalizeInviteCode(' k7p2mdxn ').length, 8);
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

  group('upotrebe', () {
    test('preostale upotrebe su max minus iskorišćene', () {
      expect(_invite(uses: 2).usesLeft, 3);
    });

    test('podrazumevano je 5 upotreba', () {
      final invite = HouseholdInvite(
        id: 'inv-2',
        householdId: 'home-1',
        code: 'K7P2MDXN',
        createdAt: DateTime.utc(2026, 11, 10),
        expiresAt: DateTime.utc(2026, 11, 17),
        uses: 0,
      );
      expect(invite.maxUses, 5);
    });

    test('potrošena pozivnica ne važi ni pre isteka', () {
      final created = DateTime.utc(2026, 11, 10, 12);
      expect(
        isInviteUsable(_invite(uses: 5), created.add(const Duration(hours: 1))),
        isFalse,
      );
    });
  });
}
