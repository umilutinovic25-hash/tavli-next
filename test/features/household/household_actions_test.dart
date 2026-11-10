import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/account/auth_gateway.dart';
import 'package:tavli/account/session_store.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/household_invite_repository.dart';
import 'package:tavli/domain/household.dart';
import 'package:tavli/domain/household_role.dart';
import 'package:tavli/features/household/household_actions.dart';
import 'package:tavli/providers.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/fake_secret_storage.dart';

void main() {
  late AppDatabase db;
  late FakeBackend backend;
  late ProviderContainer c;
  late AuthSession ana;
  late AuthSession marko;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    backend = FakeBackend();
    ana = await backend.auth.verifyCode('ana@mail.com', FakeServer.code);
    marko = await backend.auth.verifyCode('marko@mail.com', FakeServer.code);
    backend.server.profiles[marko.userId]!['display_name'] = 'Marko';
    final secrets = MapSecretStorage();
    secrets.values[SessionStore.key] = marko.json;
    c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sessionStoreProvider.overrideWithValue(SessionStore(secrets)),
        authGatewayProvider.overrideWithValue(backend.auth),
        accountApiProvider.overrideWithValue(backend.accounts),
        householdInviteRemoteProvider.overrideWithValue(backend.invites),
        householdMembershipRemoteProvider.overrideWithValue(backend.membership),
      ],
    );
    // Marko je prijavljen na ovom uređaju.
    await c.read(accountServiceProvider).loadOrFetch(marko);
    await c.read(authControllerProvider.notifier).start();
    await pumpEventQueue();
    backend.auth.current = marko;
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  HouseholdActions actions() => c.read(householdActionsProvider);
  Future<List<HouseholdMember>> members() async {
    await pumpEventQueue();
    return c.read(householdMembersProvider).value ?? const [];
  }

  String activeHousehold() =>
      (c.read(authControllerProvider) as SignedIn).account.householdId;
  String anaHome() => backend.server.households[ana.userId]!;
  String markoHome() => backend.server.households[marko.userId]!;

  /// Ana (vlasnica) pravi pozivnicu za svoje domaćinstvo.
  Future<String> anaInvite() async {
    backend.auth.current = ana;
    final code = await backend.invites.create(anaHome());
    backend.auth.current = marko;
    return code;
  }

  test('pridruživanje važećim kodom menja aktivno domaćinstvo', () async {
    backend.server.householdNames[anaHome()] = 'Kod Ane';
    final code = await anaInvite();

    final outcome = await actions().join(' ${code.toLowerCase()} ');

    expect(outcome, isA<HouseholdDone>());
    expect(
      (outcome as HouseholdDone).message,
      'Sada si član domaćinstva „Kod Ane“.',
    );
    expect(activeHousehold(), anaHome());
  });

  test(
    'kod domaćinstva čiji je već član: postaje aktivno, bez upotrebe',
    () async {
      final code = await anaInvite();
      await actions().join(code);
      await actions().selectActive(markoHome());
      expect(activeHousehold(), markoHome());

      final outcome = await actions().join(code);

      expect(outcome, isA<HouseholdDone>());
      expect(activeHousehold(), anaHome());
      expect(backend.invites.invites.single.uses, 1);
    },
  );

  test('nevažeći kod ostavlja domaćinstvo', () async {
    final outcome = await actions().join('ZZZZZZZZ');
    expect(
      (outcome as HouseholdFailed).message,
      'Kod nije važeći ili je istekao.',
    );
    expect(activeHousehold(), markoHome());
  });

  test('vlasnik ne može da napusti domaćinstvo pre prenosa', () async {
    final outcome = await actions().leave();
    expect(
      (outcome as HouseholdFailed).message,
      'Pre napuštanja prenesi vlasništvo drugom članu.',
    );
  });

  test('član napušta domaćinstvo i vraća se u svoje', () async {
    await actions().join(await anaInvite());
    expect(activeHousehold(), anaHome());

    final outcome = await actions().leave();

    expect((outcome as HouseholdDone).message, 'Domaćinstvo je napušteno.');
    expect(activeHousehold(), markoHome());
  });

  test('vlasnik uklanja člana; keš članova se osvežava', () async {
    c.listen(householdMembersProvider, (_, _) {});
    backend.server.addMember(markoHome(), ana.userId);
    expect(await actions().reloadMembers(), isTrue);
    expect((await members()).map((m) => m.userId), [marko.userId, ana.userId]);

    final outcome = await actions().removeMember(
      HouseholdMember(
        userId: ana.userId,
        displayName: null,
        role: HouseholdRole.member,
        joinedAt: DateTime.utc(2026, 11, 10),
      ),
    );

    expect((outcome as HouseholdDone).message, 'Član je uklonjen.');
    expect((await members()).map((m) => m.userId), [marko.userId]);
  });

  test('prenos vlasništva menja uloge', () async {
    backend.server.addMember(markoHome(), ana.userId);
    await actions().reloadMembers();

    final outcome = await actions().transferOwnership(
      HouseholdMember(
        userId: ana.userId,
        displayName: null,
        role: HouseholdRole.member,
        joinedAt: DateTime.utc(2026, 11, 10),
      ),
    );

    expect((outcome as HouseholdDone).message, 'Vlasništvo je preneto.');
    expect((c.read(authControllerProvider) as SignedIn).account.role, 'member');
  });

  test('bez mreže: poruka o mreži i bez osvežavanja naloga', () async {
    backend.server.offline = true;
    final outcome = await actions().join('K7P2MDXN');
    expect(
      (outcome as HouseholdFailed).message,
      'Za ovo je potrebna internet veza.',
    );
    expect(await actions().reloadMembers(), isFalse);
    expect(await actions().loadInvites(), isNull);
  });

  test('vlasnik pravi pozivnicu i vidi je među aktivnim', () async {
    final outcome = await actions().createInvite();
    final code = (outcome as HouseholdDone).code;
    expect(code, hasLength(8));
    final invites = await actions().loadInvites();
    expect(invites!.single.code, code);

    expect(
      (await actions().revokeInvite(invites.single) as HouseholdDone).message,
      'Pozivnica je poništena.',
    );
    expect(await actions().loadInvites(), isEmpty);
  });

  test('istekla sesija pri pozivnici vodi na prijavu', () async {
    backend.invites.failWith = const InviteUnauthorized();
    final outcome = await actions().join('K7P2MDXN');
    expect(outcome, isA<HouseholdFailed>());
    expect(outcome.message, isEmpty);
    expect(c.read(authControllerProvider), isA<SignedOut>());
  });

  test('pridružen, a osvežavanje ne uspe: i dalje uspeh', () async {
    final code = await anaInvite();
    backend.invites.afterRedeem = () => backend.server.offline = true;

    final outcome = await actions().join(code);

    expect(outcome, isA<HouseholdDone>());
    expect(outcome.message, 'Sada si član domaćinstva.');
  });
}
