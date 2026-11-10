import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/supabase_config.dart';
import 'package:tavli/data/household_invite_repository.dart';
import 'package:tavli/data/household_membership_repository.dart';
import 'package:tavli/providers.dart';

void main() {
  test(
    'bez Supabase podešavanja radnje domaćinstva javljaju offline',
    () async {
      final c = ProviderContainer(
        overrides: [
          supabaseConfigProvider.overrideWithValue(
            const SupabaseConfig(url: '', anonKey: ''),
          ),
        ],
      );
      addTearDown(c.dispose);

      await expectLater(
        c.read(householdMembershipRepositoryProvider).leave('h1'),
        throwsA(isA<MembershipOffline>()),
      );
      await expectLater(
        c.read(householdMembershipRepositoryProvider).listMembers('h1'),
        throwsA(isA<MembershipOffline>()),
      );
      await expectLater(
        c.read(householdInviteRepositoryProvider).create('h1'),
        throwsA(isA<InviteOffline>()),
      );
      await expectLater(
        c.read(householdInviteRepositoryProvider).redeem('K7P2MDXN'),
        throwsA(isA<InviteOffline>()),
      );
    },
  );
}
