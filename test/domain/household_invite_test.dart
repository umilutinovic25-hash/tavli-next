import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/household_invite.dart';

HouseholdInvite _invite({DateTime? expiresAt, DateTime? revokedAt}) {
  final created = DateTime.utc(2026, 11, 10, 12);
  return HouseholdInvite(
    id: 'inv-1',
    householdId: 'home-1',
    code: 'K7P2MDXN',
    createdAt: created,
    expiresAt: expiresAt ?? created.add(const Duration(days: 7)),
    revokedAt: revokedAt,
    uses: 0,
  );
}

void main() {
  group('normalizacija unosa', () {
    test('velika slova i razmaci se uklanjaju', () {
      expect(normalizeInviteCode('  k7p2mdxn '), 'K7P2MDXN');
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
}
