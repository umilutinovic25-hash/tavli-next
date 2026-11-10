import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:tavli/account/account_api.dart';
import 'package:tavli/account/auth_gateway.dart';
import 'package:tavli/data/household_invite_repository.dart';
import 'package:tavli/data/household_membership_repository.dart';
import 'package:tavli/domain/household.dart';
import 'package:tavli/domain/household_invite.dart';
import 'package:tavli/domain/household_role.dart';
import 'package:tavli/sync/sync_remote.dart';

/// Server u memoriji: nalozi sa domaćinstvom, tabele sa upsert-om po id-ju,
/// tragovi brisanja (brisanje pobeđuje), redosled po (updated_at, id),
/// slike i ubačene greške. Bez RLS-a: vidi se samo ono što pripada
/// trenutno prijavljenom nalogu ([FakeAuth.current]).
class FakeServer {
  /// Kod koji "stiže" e-poštom.
  static const code = '123456';

  final users = <String, String>{}; // email → userId
  final profiles = <String, Map<String, Object?>>{}; // userId → profil
  final households = <String, String>{}; // userId → lično householdId

  /// Članstva: householdId → (userId → uloga i vreme pridruživanja).
  final members = <String, Map<String, ({String role, DateTime joinedAt})>>{};
  final householdNames = <String, String>{}; // householdId → naziv

  /// Dodaje [userId] u [householdId] (bez provere pozivnice).
  void addMember(
    String householdId,
    String userId, {
    String role = 'member',
    DateTime? joinedAt,
  }) {
    householdNames.putIfAbsent(householdId, () => 'Domaćinstvo $householdId');
    members.putIfAbsent(householdId, () => {})[userId] = (
      role: role,
      joinedAt: joinedAt ?? DateTime.utc(2026, 11, 10),
    );
  }

  /// Članstva korisnika, poslednje pridruženo prvo.
  List<Membership> membershipsOf(String userId) {
    final out = [
      for (final MapEntry(key: hid, value: m) in members.entries)
        if (m[userId] case final me?)
          Membership(
            householdId: hid,
            householdName: householdNames[hid] ?? 'Moje domaćinstvo',
            role: HouseholdRole.parse(me.role),
            joinedAt: me.joinedAt,
          ),
    ]..sort((a, b) => b.joinedAt.compareTo(a.joinedAt));
    return out;
  }

  final tables = <String, Map<String, Map<String, Object?>>>{};
  final photos = <String, Uint8List>{};
  final revoked = <String>{}; // userId-jevi kojima je sesija opozvana

  bool offline = false;

  /// Sledeći poziv(i) baca(ju) ovu grešku.
  final failures = <SyncError>[];

  /// Posle toliko upisanih redova sledeći upsert pukne (prekinuto slanje).
  int? interruptAfterRows;

  /// Odbija upsert reda sa ovim id-jem (trajna greška, npr. 23514).
  final rejectIds = <String>{};

  /// Slanje slika baca grešku.
  bool photoUploadFails = false;

  /// Broj poziva po vrsti, za proveru grupisanja.
  final calls = <String>[];

  var _tick = 0;
  var _n = 0;

  /// Vreme na serveru raste sa svakim upisom (po sekundu, da bi pozicija
  /// preuzimanja bila jasna i sa sekundnom tačnošću lokalne baze).
  String _now() =>
      DateTime.utc(2026, 11).add(Duration(seconds: ++_tick)).toIso8601String();

  /// Posle toliko uspešnih preuzimanja sledeće pukne (prekinuto preuzimanje).
  int? fetchesBeforeFailure;

  Map<String, Map<String, Object?>> table(String name) =>
      tables.putIfAbsent(name, () => {});

  /// Redovi tabele sa servera (bez meta kolona) — za provere u testovima.
  List<Map<String, Object?>> rows(String name) => [...table(name).values];

  String userFor(String email) => users.putIfAbsent(email, () {
    final uid = 'user-${++_n}';
    final hid = 'home-$_n';
    households[uid] = hid;
    householdNames[hid] = 'Moje domaćinstvo';
    members[hid] = {uid: (role: 'owner', joinedAt: DateTime.utc(2026, 11))};
    profiles[uid] = {
      'id': uid,
      'email': email,
      'display_name': null,
      'updated_at': _now(),
    };
    return uid;
  });

  void _check() {
    if (offline) throw const TransientSyncError('offline');
    if (failures.isNotEmpty) throw failures.removeAt(0);
  }

  static const _entityOf = {
    'recipes': 'recipe',
    'recipe_versions': 'recipe_version',
    'day_time_budgets': 'day_time_budget',
    'household_preferences': 'household_preference',
    'shopping_lists': 'shopping_list',
    'shopping_items': 'shopping_item',
    'pantry_items': 'pantry_item',
    'meal_plans': 'meal_plan',
    'week_templates': 'week_template',
    'meal_plan_entries': 'meal_plan_entry',
    'cook_soon_items': 'cook_soon_item',
    'day_rules': 'day_rule',
    'shopping_sources': 'shopping_source',
    'shopping_contributions': 'shopping_contribution',
    'supply_allocations': 'supply_allocation',
    'ratings': 'rating',
    'taste_profiles': 'taste_profile',
    'saved_recipe_searches': 'saved_recipe_search',
  };

  /// Roditelji po stranim ključevima: dete obrisanog roditelja se preskače.
  static const _parentsOf = {
    'recipe_versions': [('recipe', 'recipe_id')],
    'shopping_items': [('shopping_list', 'list_id')],
    'meal_plan_entries': [('meal_plan', 'plan_id')],
    'ratings': [('recipe', 'recipe_id')],
    'shopping_sources': [
      ('shopping_list', 'list_id'),
      ('meal_plan_entry', 'plan_entry_id'),
    ],
    'shopping_contributions': [
      ('shopping_source', 'source_id'),
      ('shopping_item', 'shopping_item_id'),
    ],
    'supply_allocations': [
      ('shopping_contribution', 'contribution_id'),
      ('pantry_item', 'pantry_item_id'),
      ('shopping_item', 'purchased_shopping_item_id'),
    ],
  };

  bool _deleted(String entity, Object? id) =>
      id != null && table('deletions').containsKey('$entity/$id');

  void upsert(String name, List<Map<String, Object?>> rows, String key) {
    _check();
    calls.add('upsert:$name:${rows.length}');
    for (final r in rows) {
      if (interruptAfterRows case final n?) {
        if (n <= 0) {
          interruptAfterRows = null;
          throw const TransientSyncError('interrupted');
        }
        interruptAfterRows = n - 1;
      }
      final id = r[key]! as String;
      if (rejectIds.contains(id)) throw const PermanentSyncError('23514');
      final entity = _entityOf[name]!;
      if (_deleted(entity, id)) continue;
      if (_parentsOf[name]?.any((p) => _deleted(p.$1, r[p.$2])) ?? false) {
        continue;
      }
      final row = {...?table(name)[id], ...r, 'updated_at': _now()};
      // Kao kolona koju računa baza (generated always).
      if (name == 'supply_allocations') {
        row['supply_id'] =
            row['purchased_shopping_item_id'] ?? row['pantry_item_id'];
      }
      table(name)[id] = row;
    }
  }

  void delete(String name, List<String> ids, String key) {
    _check();
    calls.add('delete:$name:${ids.length}');
    for (final id in ids) {
      _deleteRow(name, id, key);
    }
  }

  void _deleteRow(String name, String id, String key) {
    final row = table(name).remove(id);
    if (row == null) return;
    final entity = _entityOf[name]!;
    table('deletions')['$entity/$id'] = {
      'id': '$entity/$id',
      'entity': entity,
      'record_id': id,
      'household_id': row['household_id'],
      'user_id': row.containsKey('household_id') ? null : row['user_id'],
      'deleted_at': _now(),
    };
    // Kaskade kao na serveru.
    void cascade(String child, String column) {
      for (final c in [...table(child).values]) {
        if (c[column] == id) _deleteRow(child, c['id']! as String, 'id');
      }
    }

    void setNull(String child, String column) {
      for (final c in table(child).values) {
        if (c[column] == id) {
          c[column] = null;
          c['updated_at'] = _now();
        }
      }
    }

    switch (name) {
      case 'recipes':
        cascade('recipe_versions', 'recipe_id');
        cascade('ratings', 'recipe_id');
        setNull('meal_plan_entries', 'recipe_id');
        setNull('shopping_sources', 'recipe_id');
        setNull('cook_soon_items', 'recipe_id');
      case 'shopping_lists':
        cascade('shopping_items', 'list_id');
        cascade('shopping_sources', 'list_id');
      case 'meal_plans':
        cascade('meal_plan_entries', 'plan_id');
        setNull('shopping_lists', 'meal_plan_id');
      case 'meal_plan_entries':
        cascade('shopping_sources', 'plan_entry_id');
      case 'shopping_items':
        setNull('shopping_contributions', 'shopping_item_id');
        setNull('pantry_items', 'source_shopping_item_id');
        cascade('supply_allocations', 'purchased_shopping_item_id');
      case 'pantry_items':
        cascade('supply_allocations', 'pantry_item_id');
      case 'shopping_sources':
        cascade('shopping_contributions', 'source_id');
      case 'shopping_contributions':
        cascade('supply_allocations', 'contribution_id');
    }
  }

  bool _visible(Map<String, Object?> row, String userId) {
    if (row['household_id'] case final h?) {
      return members[h]?.containsKey(userId) ?? false;
    }
    if (row['user_id'] case final u?) return u == userId;
    return row['id'] == userId; // profiles
  }

  List<Map<String, Object?>> fetchSince(
    String name,
    String userId, {
    required int limit,
    String? since,
    String? afterId,
    required String timeColumn,
    required String idColumn,
  }) {
    _check();
    if (fetchesBeforeFailure case final n?) {
      fetchesBeforeFailure = n == 0 ? null : n - 1;
      if (n == 0) throw const TransientSyncError('interrupted');
    }
    calls.add('fetch:$name');
    final source = name == 'profiles' ? profiles.values : table(name).values;
    final sorted =
        [
          for (final r in source)
            if (_visible(r, userId)) Map<String, Object?>.of(r),
        ]..sort((a, b) {
          final t = (a[timeColumn]! as String).compareTo(
            b[timeColumn]! as String,
          );
          return t != 0
              ? t
              : (a[idColumn]! as String).compareTo(b[idColumn]! as String);
        });
    final out = <Map<String, Object?>>[];
    for (final r in sorted) {
      if (since != null) {
        final t = r[timeColumn]! as String;
        final c = t.compareTo(since);
        if (c < 0) continue;
        if (c == 0 && (r[idColumn]! as String).compareTo(afterId ?? '') <= 0) {
          continue;
        }
      }
      out.add(r);
      if (out.length == limit) break;
    }
    // Kao JSON preko mreže.
    return [
      for (final r in out) jsonDecode(jsonEncode(r)) as Map<String, Object?>,
    ];
  }

  /// Briše sve što pripada nalogu (kao Edge Function delete-account).
  void deleteAccount(String userId) {
    final hid = households.remove(userId);
    for (final m in members.values) {
      m.remove(userId);
    }
    for (final t in tables.values) {
      t.removeWhere(
        (_, r) =>
            (hid != null && r['household_id'] == hid) || r['user_id'] == userId,
      );
    }
    photos.removeWhere((k, _) => hid != null && k.startsWith('$hid/'));
    profiles.remove(userId);
    users.removeWhere((_, u) => u == userId);
  }
}

/// Lažni Supabase Auth nad [FakeServer].
class FakeAuth implements AuthGateway {
  FakeAuth(this.server);

  final FakeServer server;
  final _changes = StreamController<AuthSession?>.broadcast();

  AuthSession? current;
  final sentCodes = <String>[];

  /// Sledeći poziv baca ovu grešku.
  AuthFailure? failNext;

  /// Koliko puta je sesija obnovljena.
  int refreshes = 0;

  AuthSession sessionFor(String email) {
    final uid = server.userFor(email);
    return AuthSession(
      userId: uid,
      email: email,
      json: jsonEncode({
        'user': {'id': uid, 'email': email},
        'refresh_token': 'fake-refresh-${server._n}',
      }),
    );
  }

  void _check() {
    if (failNext case final f?) {
      failNext = null;
      throw f;
    }
    if (server.offline) throw const Offline();
  }

  @override
  Future<void> sendCode(String email) async {
    _check();
    sentCodes.add(email);
  }

  @override
  Future<AuthSession> verifyCode(String email, String code) async {
    _check();
    if (code != FakeServer.code) throw const WrongCode();
    return current = sessionFor(email);
  }

  AuthSession _restoreFrom(String json) {
    final user =
        (jsonDecode(json) as Map<String, Object?>)['user']!
            as Map<String, Object?>;
    final uid = user['id']! as String;
    if (!server.profiles.containsKey(uid)) throw const AccountGone();
    if (server.revoked.contains(uid)) throw const SessionRevoked();
    return current = AuthSession(
      userId: uid,
      email: user['email']! as String,
      json: json,
    );
  }

  @override
  Future<AuthSession> restore(String sessionJson) async {
    _check();
    return _restoreFrom(sessionJson);
  }

  @override
  Future<AuthSession> refresh() async {
    _check();
    final c = current;
    if (c == null) throw const SessionRevoked();
    refreshes++;
    final s = _restoreFrom(c.json);
    _changes.add(s);
    return s;
  }

  @override
  Stream<AuthSession?> get sessionChanges => _changes.stream;

  @override
  Future<void> signOutLocal() async => current = null;

  Future<void> close() => _changes.close();
}

class FakeAccountApi implements AccountApi {
  FakeAccountApi(this.server, this.auth);

  final FakeServer server;
  final FakeAuth auth;

  /// Brisanje naloga baca ovu grešku.
  DeleteFailure? deleteFails;

  @override
  Future<RemoteAccount> fetch() async {
    if (server.offline) throw const Offline();
    final uid = auth.current!.userId;
    final p = server.profiles[uid]!;
    final all = server.membershipsOf(uid);
    final first = all.first;
    return RemoteAccount(
      userId: uid,
      email: p['email']! as String,
      displayName: p['display_name'] as String?,
      householdId: first.householdId,
      householdName: first.householdName,
      role: first.role.wire,
      memberships: all,
    );
  }

  @override
  Future<void> deleteAccount() async {
    if (server.offline) throw const DeleteOffline();
    if (deleteFails case final f?) throw f;
    server.deleteAccount(auth.current!.userId);
  }
}

class FakeSyncRemote implements SyncRemote {
  FakeSyncRemote(this.server, this.auth);

  final FakeServer server;
  final FakeAuth auth;

  String get _uid => auth.current?.userId ?? '';

  /// Opozvana ili obrisana sesija: server odgovara 401.
  void _checkSession() {
    final uid = auth.current?.userId;
    if (uid != null &&
        (server.revoked.contains(uid) || !server.profiles.containsKey(uid))) {
      throw const UnauthorizedSyncError();
    }
  }

  @override
  Future<void> upsert(
    String table,
    List<Map<String, Object?>> rows, {
    String onConflict = 'id',
  }) async {
    _checkSession();
    server.upsert(table, [
      for (final r in rows) jsonDecode(jsonEncode(r)) as Map<String, Object?>,
    ], onConflict);
  }

  @override
  Future<void> delete(
    String table,
    List<String> ids, {
    String idColumn = 'id',
  }) async {
    _checkSession();
    server.delete(table, ids, idColumn);
  }

  @override
  Future<void> updateProfileName(String userId, String name) async {
    _checkSession();
    server._check();
    server.calls.add('profile');
    server.profiles[userId]!
      ..['display_name'] = name
      ..['updated_at'] = server._now();
  }

  @override
  Future<List<Map<String, Object?>>> fetchSince(
    String table, {
    required int limit,
    String? since,
    String? afterId,
    String timeColumn = 'updated_at',
    String idColumn = 'id',
  }) async {
    _checkSession();
    return server.fetchSince(
      table,
      _uid,
      limit: limit,
      since: since,
      afterId: afterId,
      timeColumn: timeColumn,
      idColumn: idColumn,
    );
  }
}

class FakePhotoRemote implements PhotoRemote {
  FakePhotoRemote(this.server);

  final FakeServer server;

  /// Objekti koji (još) ne mogu da se preuzmu.
  final missing = <String>{};

  @override
  Future<void> upload(String objectKey, Uint8List jpeg) async {
    server._check();
    if (server.photoUploadFails) throw const TransientSyncError('503');
    server.calls.add('photo:upload');
    server.photos[objectKey] = jpeg;
  }

  @override
  Future<Uint8List> download(String objectKey) async {
    server._check();
    final p = server.photos[objectKey];
    if (p == null || missing.contains(objectKey)) {
      throw const PermanentSyncError('404');
    }
    return p;
  }

  @override
  Future<void> remove(List<String> objectKeys) async {
    server._check();
    objectKeys.forEach(server.photos.remove);
  }
}

/// Sve lažne granice nad jednim serverom.
class FakeBackend {
  FakeBackend() {
    auth = FakeAuth(server);
    accounts = FakeAccountApi(server, auth);
    sync = FakeSyncRemote(server, auth);
    photos = FakePhotoRemote(server);
    invites = FakeInviteRemote(server, auth);
    membership = FakeMembershipRemote(server, auth);
  }

  final server = FakeServer();
  late final FakeAuth auth;
  late final FakeAccountApi accounts;
  late final FakeSyncRemote sync;
  late final FakePhotoRemote photos;
  late final FakeInviteRemote invites;
  late final FakeMembershipRemote membership;
}

/// Pozivnice na lažnom serveru, po pravilima iz migracije
/// 20261111130000_household_invites.sql.
class FakeInviteRemote implements HouseholdInviteRemote {
  FakeInviteRemote(this.server, this.auth);

  final FakeServer server;
  final FakeAuth auth;
  final invites = <HouseholdInvite>[];
  final calls = <String>[];

  /// Ako nije null, svaki poziv čeka ovaj Completer (za test duplog dodira).
  Completer<void>? gate;

  /// Neuspeli pokušaji po korisniku (bez vremena: test je kratak).
  final _failures = <String, int>{};
  var _n = 0;

  String get _uid => auth.current!.userId;

  Future<void> _enter(String call) async {
    calls.add(call);
    if (gate case final g?) await g.future;
    if (server.offline) throw const InviteOffline();
  }

  bool _owner(String householdId) =>
      server.members[householdId]?[_uid]?.role == 'owner';

  @override
  Future<String> create(String householdId) async {
    await _enter('create');
    if (!_owner(householdId)) throw const InviteForbidden();
    final code = 'K7P2MDX${++_n}'.padRight(8, 'N').substring(0, 8);
    final now = DateTime.utc(2026, 11, 10, 12);
    invites.add(
      HouseholdInvite(
        id: 'inv-$_n',
        householdId: householdId,
        code: code,
        createdAt: now,
        expiresAt: now.add(const Duration(days: 7)),
        uses: 0,
      ),
    );
    return code;
  }

  @override
  Future<List<HouseholdInvite>> listForHousehold(String householdId) async {
    await _enter('list');
    if (!_owner(householdId)) return const [];
    return [
      for (final i in invites.reversed)
        if (i.householdId == householdId) i,
    ];
  }

  @override
  Future<void> revoke(String id) async {
    await _enter('revoke');
    final i = invites.indexWhere((x) => x.id == id);
    if (i < 0 || !_owner(invites[i].householdId)) return;
    final old = invites[i];
    invites[i] = HouseholdInvite(
      id: old.id,
      householdId: old.householdId,
      code: old.code,
      createdAt: old.createdAt,
      expiresAt: old.expiresAt,
      uses: old.uses,
      maxUses: old.maxUses,
      revokedAt: DateTime.utc(2026, 11, 10, 13),
    );
  }

  @override
  Future<String?> redeem(String code) async {
    await _enter('redeem');
    if ((_failures[_uid] ?? 0) >= 5) throw const InviteTooManyAttempts();
    final i = invites.indexWhere(
      (x) => x.code == code && x.revokedAt == null && x.usesLeft > 0,
    );
    if (i < 0) {
      _failures[_uid] = (_failures[_uid] ?? 0) + 1;
      return null;
    }
    final inv = invites[i];
    if (server.members[inv.householdId]?.containsKey(_uid) != true) {
      server.addMember(inv.householdId, _uid, joinedAt: DateTime.utc(2026, 12));
      invites[i] = HouseholdInvite(
        id: inv.id,
        householdId: inv.householdId,
        code: inv.code,
        createdAt: inv.createdAt,
        expiresAt: inv.expiresAt,
        uses: inv.uses + 1,
        maxUses: inv.maxUses,
      );
    }
    return inv.householdId;
  }
}

/// Članstvo na lažnom serveru, po pravilima iz migracija
/// 20261111130100_household_membership_ops.sql i 20261111130300.
class FakeMembershipRemote implements HouseholdMembershipRemote {
  FakeMembershipRemote(this.server, this.auth);

  final FakeServer server;
  final FakeAuth auth;
  final calls = <String>[];

  String get _uid => auth.current!.userId;

  void _enter(String call) {
    calls.add(call);
    if (server.offline) throw const MembershipOffline();
  }

  Map<String, ({String role, DateTime joinedAt})> _household(String id) =>
      server.members[id] ?? {};

  void _requireOwner(String householdId) {
    if (_household(householdId)[_uid]?.role != 'owner') {
      throw const NotHouseholdOwner();
    }
  }

  @override
  Future<void> removeMember(String householdId, String userId) async {
    _enter('remove');
    _requireOwner(householdId);
    if (userId == _uid) throw const CannotRemoveSelf();
    if (_household(householdId).remove(userId) == null) {
      throw const NotHouseholdMember();
    }
  }

  @override
  Future<void> leave(String householdId) async {
    _enter('leave');
    final me = _household(householdId)[_uid];
    if (me == null) throw const NotHouseholdMember();
    if (me.role == 'owner') throw const OwnerMustTransfer();
    _household(householdId).remove(_uid);
  }

  @override
  Future<void> transferOwnership(String householdId, String userId) async {
    _enter('transfer');
    _requireOwner(householdId);
    if (userId == _uid) throw const CannotTransferToSelf();
    final h = _household(householdId);
    final target = h[userId];
    if (target == null) throw const NotHouseholdMember();
    h[userId] = (role: 'owner', joinedAt: target.joinedAt);
    final me = h[_uid]!;
    h[_uid] = (role: 'member', joinedAt: me.joinedAt);
  }

  @override
  Future<List<HouseholdMember>> listMembers(String householdId) async {
    _enter('list');
    final h = _household(householdId);
    if (!h.containsKey(_uid)) throw const NotHouseholdMember();
    final out =
        [
          for (final MapEntry(key: uid, value: m) in h.entries)
            HouseholdMember(
              userId: uid,
              displayName: server.profiles[uid]?['display_name'] as String?,
              role: HouseholdRole.parse(m.role),
              joinedAt: m.joinedAt,
            ),
        ]..sort((a, b) {
          if (a.role != b.role) return a.role == HouseholdRole.owner ? -1 : 1;
          return a.joinedAt.compareTo(b.joinedAt);
        });
    return out;
  }
}
