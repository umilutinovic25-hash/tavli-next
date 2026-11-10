import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/auth_controller.dart';
import '../../data/household_invite_repository.dart';
import '../../data/household_membership_repository.dart';
import '../../domain/household.dart';
import '../../domain/household_invite.dart';
import '../../providers.dart';
import '../recipes/recipe_providers.dart';
import 'household_error_text.dart';

/// Ishod radnje nad domaćinstvom; UI prikazuje [message] (prazna poruka se
/// ne prikazuje).
sealed class HouseholdOutcome {
  const HouseholdOutcome(this.message);

  final String message;
}

class HouseholdDone extends HouseholdOutcome {
  const HouseholdDone(super.message, {this.code});

  /// Kod nove pozivnice (samo za [HouseholdActions.createInvite]).
  final String? code;
}

class HouseholdFailed extends HouseholdOutcome {
  const HouseholdFailed(super.message);
}

/// Jedino mesto kroz koje ekrani menjaju domaćinstvo: server, pa osvežen
/// nalog i keš članova. Nikad ne baca.
class HouseholdActions {
  HouseholdActions(this._ref);

  final Ref _ref;

  AuthController get _auth => _ref.read(authControllerProvider.notifier);

  AccountScope? get _scope => _ref.read(accountScopeProvider);

  String? get _householdName => switch (_ref.read(authControllerProvider)) {
    SignedIn(:final account) ||
    NeedsName(:final account) => account.householdName,
    _ => null,
  };

  Future<HouseholdOutcome> createInvite() => _run(() async {
    final code = await _ref
        .read(householdInviteRepositoryProvider)
        .create(_scope!.householdId);
    return HouseholdDone('', code: code);
  });

  Future<HouseholdOutcome> revokeInvite(HouseholdInvite invite) =>
      _run(() async {
        await _ref.read(householdInviteRepositoryProvider).revoke(invite);
        return const HouseholdDone('Pozivnica je poništena.');
      });

  /// Aktivne pozivnice domaćinstva; null kad nisu mogle da se učitaju.
  Future<List<HouseholdInvite>?> loadInvites() async {
    final scope = _scope;
    if (scope == null) return null;
    try {
      final now = _ref.read(clockProvider)();
      final all = await _ref
          .read(householdInviteRepositoryProvider)
          .listForHousehold(scope.householdId);
      return [
        for (final i in all)
          if (isInviteUsable(i, now)) i,
      ];
    } on Exception {
      return null;
    }
  }

  /// Iskorišćen kod postaje izabrano aktivno domaćinstvo (i kad je korisnik
  /// već bio član, pa se vreme pridruživanja ne menja).
  Future<HouseholdOutcome> join(String rawCode) => _run(() async {
    final householdId = await _ref
        .read(householdInviteRepositoryProvider)
        .redeem(rawCode);
    await _ref
        .read(accountServiceProvider)
        .setPreferredHousehold(_scope!.userId, householdId);
    if (!await _auth.refreshAccount()) {
      return const HouseholdFailed('Za ovo je potrebna internet veza.');
    }
    return HouseholdDone('Sada si član domaćinstva „${_householdName ?? ''}“.');
  });

  Future<HouseholdOutcome> removeMember(HouseholdMember member) =>
      _run(() async {
        await _ref
            .read(householdMembershipRepositoryProvider)
            .removeMember(_scope!.householdId, member.userId);
        await _auth.refreshAccount();
        await reloadMembers();
        return const HouseholdDone('Član je uklonjen.');
      });

  Future<HouseholdOutcome> leave() => _run(() async {
    await _ref
        .read(householdMembershipRepositoryProvider)
        .leave(_scope!.householdId);
    await _auth.refreshAccount();
    return const HouseholdDone('Domaćinstvo je napušteno.');
  });

  Future<HouseholdOutcome> transferOwnership(HouseholdMember member) =>
      _run(() async {
        await _ref
            .read(householdMembershipRepositoryProvider)
            .transferOwnership(_scope!.householdId, member.userId);
        await _auth.refreshAccount();
        await reloadMembers();
        return const HouseholdDone('Vlasništvo je preneto.');
      });

  /// Ručni izbor aktivnog domaćinstva; važi tek kad ga server potvrdi.
  Future<HouseholdOutcome> selectActive(String householdId) => _run(() async {
    final service = _ref.read(accountServiceProvider);
    final userId = _scope!.userId;
    final previous = await service.cachedPreferred(userId);
    await service.setPreferredHousehold(userId, householdId);
    if (!await _auth.refreshAccount()) {
      await service.setPreferredHousehold(userId, previous);
      return const HouseholdFailed('Za ovo je potrebna internet veza.');
    }
    return const HouseholdDone('');
  });

  /// Članovi aktivnog domaćinstva sa servera u keš; false kad nije uspelo.
  Future<bool> reloadMembers() async {
    final scope = _scope;
    if (scope == null) return false;
    try {
      final members = await _ref
          .read(householdMembershipRepositoryProvider)
          .listMembers(scope.householdId);
      await _ref
          .read(accountServiceProvider)
          .cacheMembers(
            scope.userId,
            scope.householdId,
            members,
            _ref.read(clockProvider)(),
          );
      return true;
    } on MembershipUnauthorized {
      await _auth.sessionExpired();
      return false;
    } on Exception {
      return false;
    }
  }

  Future<HouseholdOutcome> _run(
    Future<HouseholdOutcome> Function() action,
  ) async {
    if (_scope == null) {
      return const HouseholdFailed('Nešto nije uspelo. Pokušaj ponovo.');
    }
    try {
      return await action();
    } on MembershipUnauthorized {
      await _auth.sessionExpired();
      return const HouseholdFailed('');
    } on InviteUnauthorized {
      await _auth.sessionExpired();
      return const HouseholdFailed('');
    } on Exception catch (e) {
      return HouseholdFailed(householdErrorText(e));
    }
  }
}

final householdActionsProvider = Provider<HouseholdActions>(
  HouseholdActions.new,
);
