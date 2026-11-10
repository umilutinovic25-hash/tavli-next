import 'dart:convert';

import 'package:drift/drift.dart';

import '../ai/key_store.dart';
import '../data/database.dart';
import '../data/recipe_photo_store.dart';
import '../domain/account.dart';
import '../domain/household.dart';
import '../domain/household_role.dart';
import '../sync/entities.dart';
import '../sync/synced_writer.dart';
import 'account_api.dart';
import 'auth_gateway.dart';

/// Nalog na uređaju: keširan profil i domaćinstvo (za pokretanje bez
/// mreže), ime i brisanje naloga.
class AccountService {
  AccountService(
    this._db,
    this._api, {
    this._photos,
    this._keys,
    DateTime Function()? clock,
    this._onChange,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final AccountApi _api;
  final RecipePhotoStore? _photos;
  final KeyStore? _keys;
  final DateTime Function() _clock;
  final void Function()? _onChange;

  /// Nalog sačuvan na uređaju (bez mreže) ili null.
  Future<Account?> cached(String userId) async {
    final row = await (_db.select(
      _db.accounts,
    )..where((t) => t.userId.equals(userId))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  /// Keširan nalog, a ako ga nema na uređaju — sa servera (prva prijava
  /// na ovom uređaju). Baca `AuthFailure`.
  Future<Account> loadOrFetch(AuthSession session) async {
    final local = await cached(session.userId);
    if (local != null) return local;
    return refresh();
  }

  /// Nalog i članstva uvek sa servera. Kad se skup članstava promeni, kursori
  /// preuzimanja se prazne (podaci novog domaćinstva mogu biti stariji od
  /// kursora), a lokalni podaci domaćinstava kojih više nema se brišu.
  /// Baca `AuthFailure`; tada se na uređaju ništa ne menja.
  Future<Account> refresh() async {
    final remote = await _api.fetch();
    final userId = remote.userId;
    final memberships = remote.memberships.isNotEmpty
        ? remote.memberships
        : [
            Membership(
              householdId: remote.householdId,
              householdName: remote.householdName,
              role: HouseholdRole.parse(remote.role),
              joinedAt: _clock(),
            ),
          ];
    final photos = <String>{};
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.accounts,
      )..where((t) => t.userId.equals(userId))).getSingleOrNull();
      final oldIds = {
        for (final m in await (_db.select(
          _db.householdMemberships,
        )..where((t) => t.accountId.equals(userId))).get())
          m.householdId,
      };
      if (oldIds.isEmpty && existing != null) oldIds.add(existing.householdId);
      final newIds = {for (final m in memberships) m.householdId};
      var preferred = existing?.preferredHouseholdId;
      if (preferred != null && !newIds.contains(preferred)) preferred = null;
      final active = pickActiveHousehold(memberships, preferredId: preferred);

      for (final gone in oldIds.difference(newIds)) {
        photos.addAll(await _purgeHousehold(userId, gone));
        await (_db.delete(_db.householdMemberCache)..where(
              (t) => t.accountId.equals(userId) & t.householdId.equals(gone),
            ))
            .go();
      }
      final changed =
          oldIds.length != newIds.length || !oldIds.containsAll(newIds);
      if (existing == null) {
        await _db
            .into(_db.accounts)
            .insert(
              AccountsCompanion.insert(
                userId: userId,
                email: normalizeEmail(remote.email),
                displayName: Value(remote.displayName),
                householdId: active.householdId,
                householdName: active.householdName,
                role: active.role.wire,
                createdAt: _clock(),
              ),
            );
      } else {
        await (_db.update(
          _db.accounts,
        )..where((t) => t.userId.equals(userId))).write(
          // Ime i e-pošta se ovde ne diraju: ime koje još čeka slanje
          // (outbox) ne sme da se prepiše starijim stanjem sa servera.
          AccountsCompanion(
            householdId: Value(active.householdId),
            householdName: Value(active.householdName),
            role: Value(active.role.wire),
            preferredHouseholdId: Value(preferred),
            initialDownloadDone: changed
                ? const Value(false)
                : const Value.absent(),
          ),
        );
        if (changed) {
          await (_db.delete(
            _db.syncCursors,
          )..where((t) => t.accountId.equals(userId))).go();
        }
      }
      await (_db.delete(
        _db.householdMemberships,
      )..where((t) => t.accountId.equals(userId))).go();
      for (final m in memberships) {
        await _db
            .into(_db.householdMemberships)
            .insert(
              HouseholdMembershipsCompanion.insert(
                accountId: userId,
                householdId: m.householdId,
                householdName: m.householdName,
                role: m.role.wire,
                joinedAt: m.joinedAt,
              ),
            );
      }
    });
    for (final p in photos) {
      await _photos?.delete(p);
    }
    return (await cached(userId))!;
  }

  /// Sačuvani ručni izbor aktivnog domaćinstva (null = nema izbora).
  Future<String?> cachedPreferred(String userId) async =>
      (await (_db.select(
            _db.accounts,
          )..where((t) => t.userId.equals(userId))).getSingleOrNull())
          ?.preferredHouseholdId;

  /// Ručni izbor aktivnog domaćinstva (null = poslednje pridruženo). Važi
  /// od sledećeg [refresh]; mreža se ne zove.
  Future<void> setPreferredHousehold(String userId, String? householdId) =>
      (_db.update(_db.accounts)..where((t) => t.userId.equals(userId))).write(
        AccountsCompanion(preferredHouseholdId: Value(householdId)),
      );

  /// Članovi [householdId] sa servera, kao ceo skup za taj nalog.
  Future<void> cacheMembers(
    String userId,
    String householdId,
    List<HouseholdMember> members,
    DateTime fetchedAt,
  ) => _db.transaction(() async {
    await (_db.delete(_db.householdMemberCache)..where(
          (t) => t.accountId.equals(userId) & t.householdId.equals(householdId),
        ))
        .go();
    for (final m in members) {
      await _db
          .into(_db.householdMemberCache)
          .insert(
            HouseholdMemberCacheCompanion.insert(
              accountId: userId,
              householdId: householdId,
              userId: m.userId,
              displayName: Value(m.displayName),
              role: m.role.wire,
              joinedAt: m.joinedAt,
              fetchedAt: fetchedAt,
            ),
          );
    }
  });

  /// Domaćinstva korisnika, poslednje pridruženo prvo.
  Stream<List<Membership>> watchMemberships(String userId) =>
      (_db.select(_db.householdMemberships)
            ..where((t) => t.accountId.equals(userId))
            ..orderBy([(t) => OrderingTerm.desc(t.joinedAt)]))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                Membership(
                  householdId: r.householdId,
                  householdName: r.householdName,
                  role: HouseholdRole.parse(r.role),
                  joinedAt: r.joinedAt,
                ),
            ],
          );

  /// Članovi domaćinstva iz keša: vlasnik prvi, pa po pridruživanju.
  Stream<List<HouseholdMember>> watchMembers(
    String userId,
    String householdId,
  ) =>
      (_db.select(_db.householdMemberCache)
            ..where(
              (t) =>
                  t.accountId.equals(userId) &
                  t.householdId.equals(householdId),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.joinedAt)]))
          .watch()
          .map((rows) {
            final members = [
              for (final r in rows)
                HouseholdMember(
                  userId: r.userId,
                  displayName: r.displayName,
                  role: HouseholdRole.parse(r.role),
                  joinedAt: r.joinedAt,
                ),
            ];
            return [
              ...members.where((m) => m.role == HouseholdRole.owner),
              ...members.where((m) => m.role != HouseholdRole.owner),
            ];
          });

  /// Čuva ime (1–40 znakova posle skidanja razmaka) lokalno i u redu za
  /// slanje. Baca [ArgumentError] za neispravno ime.
  Future<Account> saveName(Account account, String name) async {
    final n = normalizeName(name);
    if (n == null) throw ArgumentError.value(name, 'name');
    await _db.transaction(() async {
      await (_db.update(_db.accounts)
            ..where((t) => t.userId.equals(account.userId)))
          .write(AccountsCompanion(displayName: Value(n)));
      await SyncedWriter(
        _db,
        accountId: account.userId,
        clock: _clock,
        onChange: _onChange,
      ).upsert(profileEntity, account.userId);
    });
    return account.copyWith(displayName: n);
  }

  /// "Obriši nalog": prvo server (Edge Function), pa tek posle uspeha sve
  /// na uređaju: keš naloga, izmene koje čekaju, slike i sopstveni AI
  /// ključevi. Tema i pauze modela ostaju. Baca [DeleteFailure]; tada se na
  /// uređaju ne briše ništa (FR-024).
  Future<void> deleteAccount(Account account) async {
    await _api.deleteAccount();
    await wipeLocal(account.userId);
    await _keys?.clear();
  }

  /// Briše sa uređaja sve što pripada nalogu (i kad je nalog obrisan na
  /// drugom uređaju), uključujući sva domaćinstva iz keša. Podaci drugih
  /// naloga ostaju.
  Future<void> wipeLocal(String userId) async {
    final photos = <String>{};
    await _db.transaction(() async {
      final account = await (_db.select(
        _db.accounts,
      )..where((t) => t.userId.equals(userId))).getSingleOrNull();
      final households = {
        ?account?.householdId,
        for (final m in await (_db.select(
          _db.householdMemberships,
        )..where((t) => t.accountId.equals(userId))).get())
          m.householdId,
      };
      for (final hid in households) {
        photos.addAll(await _purgeHousehold(userId, hid));
      }
      await (_db.delete(
        _db.savedRecipeSearches,
      )..where((t) => t.userId.equals(userId))).go();
      await (_db.delete(
        _db.ratings,
      )..where((t) => t.userId.equals(userId))).go();
      await (_db.delete(
        _db.userProfiles,
      )..where((t) => t.id.equals(userId))).go();
      for (final pending
          in await (_db.select(_db.syncOutbox)..where(
                (t) => t.accountId.equals(userId) & t.entity.equals('photo'),
              ))
              .get()) {
        photos.add(pending.recordId);
      }
      await (_db.delete(
        _db.syncOutbox,
      )..where((t) => t.accountId.equals(userId))).go();
      await (_db.delete(
        _db.syncCursors,
      )..where((t) => t.accountId.equals(userId))).go();
      await (_db.delete(
        _db.householdMemberCache,
      )..where((t) => t.accountId.equals(userId))).go();
      await (_db.delete(
        _db.householdMemberships,
      )..where((t) => t.accountId.equals(userId))).go();
      await (_db.delete(
        _db.accounts,
      )..where((t) => t.userId.equals(userId))).go();
    });
    for (final p in photos) {
      await _photos?.delete(p);
    }
  }

  /// Briše lokalne podatke domaćinstva [householdId] i izmene naloga
  /// [userId] koje na njih čekaju slanje. Vraća putanje slika za brisanje
  /// (posle transakcije). Zove se unutar transakcije.
  Future<Set<String>> _purgeHousehold(String userId, String householdId) async {
    final photos = <String>{};
    for (final r in await (_db.select(
      _db.recipes,
    )..where((t) => t.householdId.equals(householdId))).get()) {
      if (r.imagePath case final p?) photos.add(p);
    }
    for (final v in await (_db.select(
      _db.recipeVersions,
    )..where((t) => t.householdId.equals(householdId))).get()) {
      if (_imagePath(v.recipeJson) case final p?) photos.add(p);
    }
    for (final item in await (_db.select(
      _db.shoppingItems,
    )..where((t) => t.householdId.equals(householdId))).get()) {
      if (item.photoPath case final p?) photos.add(p);
    }
    // Deca pre roditelja: registar drži roditelje pre dece.
    for (final e in syncEntities.reversed) {
      if (e.scope != EntityScope.household) continue;
      final table = e.table(_db);
      final ids = [
        for (final r
            in await _db
                .customSelect(
                  'SELECT id FROM ${table.actualTableName} WHERE household_id = ?',
                  variables: [Variable.withString(householdId)],
                  readsFrom: {table},
                )
                .get())
          r.read<String>('id'),
      ];
      if (ids.isEmpty) continue;
      await (_db.delete(_db.syncOutbox)..where(
            (t) =>
                t.accountId.equals(userId) &
                t.entity.equals(e.name) &
                t.recordId.isIn(ids),
          ))
          .go();
      await _db.customUpdate(
        'DELETE FROM ${table.actualTableName} WHERE household_id = ?',
        variables: [Variable.withString(householdId)],
        updates: {table},
        updateKind: UpdateKind.delete,
      );
    }
    if (photos.isNotEmpty) {
      await (_db.delete(_db.syncOutbox)..where(
            (t) =>
                t.accountId.equals(userId) &
                t.entity.equals('photo') &
                t.recordId.isIn(photos),
          ))
          .go();
    }
    return photos;
  }

  static String? _imagePath(String recipeJson) {
    try {
      final json = jsonDecode(recipeJson);
      return json is Map && json['imagePath'] is String
          ? json['imagePath'] as String
          : null;
    } on FormatException {
      return null;
    }
  }

  static Account _fromRow(AccountRow r) => Account(
    userId: r.userId,
    email: r.email,
    displayName: r.displayName,
    householdId: r.householdId,
    householdName: r.householdName,
    role: r.role,
  );
}
