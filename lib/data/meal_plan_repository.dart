import 'dart:convert';

import 'package:drift/drift.dart';

import '../account/auth_controller.dart';
import '../domain/day_rules.dart';
import '../domain/ids.dart';
import '../domain/meal_plan.dart';
import '../domain/plan_calendar.dart';
import '../domain/recipe.dart';
import '../domain/shopping_demand.dart' show maxServings, minServings;
import '../domain/shopping_source.dart';
import '../sync/synced_writer.dart';
import 'database.dart';
import 'day_rule_repository.dart';
import 'shopping_repository.dart';

/// Nacrt nije potpun, a nepotpuno čuvanje nije izričito izabrano (ili
/// nema nijednog spremnog obroka).
class IncompleteDraftException implements Exception {
  const IncompleteDraftException();
}

/// Obrok je zaključan ili skuvan; prvo ga treba otključati ili vratiti.
class ProtectedMealException implements Exception {
  const ProtectedMealException();
}

/// Obrok ne postoji u ovom domaćinstvu.
class MealNotFoundException implements Exception {
  const MealNotFoundException();
}

/// Jela na ovim mestima krše obavezno pravilo dana, a izuzetak nije dat.
class RuleViolationException implements Exception {
  const RuleViolationException(this.slots);

  final List<MealSlot> slots;
}

/// Plan se promenio otkako je nacrt počeo (ili ga više nema): nacrt se ne
/// čuva, stari plan ostaje kakav je bio.
class StaleDraftException implements Exception {
  const StaleDraftException();
}

/// Planovi obroka domaćinstva. Odobrenje upisuje plan, nove recepte, obroke i nabavku u
/// jednoj transakciji, sa outbox-om; mreža se ne koristi.
class MealPlanRepository {
  MealPlanRepository(
    this._db, {
    required this._scope,
    required this._writer,
    required this._shopping,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final AccountScope _scope;
  final SyncedWriter _writer;
  final ShoppingRepository _shopping;
  final DateTime Function() _clock;

  static const _plan = 'meal_plan';
  static const _entry = 'meal_plan_entry';
  static const _recipe = 'recipe';

  Stream<List<MealPlan>> watchPlans() {
    final q = _db.select(_db.mealPlans)
      ..where((t) => t.householdId.equals(_scope.householdId))
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.asc(t.id),
      ]);
    return q.watch().map((rows) => rows.map(_planFromRow).toList());
  }

  Stream<MealPlan?> watchPlan(String planId) =>
      _planQuery(planId)
          .watchSingleOrNull()
          .map((r) => r == null ? null : _planFromRow(r));

  /// Obroci plana, hronološki.
  Stream<List<PlannedMeal>> watchMeals(String planId) =>
      _entriesQuery(planId)
          .watch()
          .map((rows) => rows.map(_mealFromRow).toList()..sort(_bySlot));

  /// Nazivi potvrđene zalihe domaćinstva (za predlog plana; samo čitanje).
  Future<List<String>> confirmedPantryNames() async => [
    for (final p
        in await (_db.select(_db.pantryItems)
              ..where(
                (t) =>
                    t.householdId.equals(_scope.householdId) &
                    t.confirmedAt.isNotNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.name)]))
            .get())
      p.name,
  ];

  /// Otisak sačuvanog plana: menja se sa svakom izmenom plana ili obroka.
  Future<String> fingerprint(String planId) async {
    final plan = await _planQuery(planId).getSingleOrNull();
    if (plan == null) return '';
    final entries = await _entriesQuery(planId).get()
      ..sort((a, b) => a.id.compareTo(b.id));
    return jsonEncode([plan.toJson(), for (final e in entries) e.toJson()]);
  }

  /// Čuva odobren nacrt i vraća id plana. Nepotpun nacrt traži
  /// [allowPartial]; prazna mesta ostaju prazna. Nacrt sa [PlanDraft.base]
  /// menja taj plan samo ako se nije promenio i ne dira zaključane,
  /// skuvane ni prošle obroke.
  ///
  /// Jelo koje krši obavezno pravilo dana čuva se samo uz izuzetak za to
  /// mesto i to pravilo ([overrides]); inače [RuleViolationException].
  Future<String> approve(
    PlanDraft draft, {
    bool allowPartial = false,
    Map<MealSlot, Set<String>> overrides = const {},
  }) {
    final ready = draft.readySlots;
    if (ready.isEmpty || (!draft.isComplete && !allowPartial)) {
      return Future.error(const IncompleteDraftException());
    }
    return _db.transaction(() async {
      final rules = await _rules();
      final allowed = <MealSlot, String?>{};
      final violating = <MealSlot>[];
      for (final slot in ready) {
        final results = evaluateSlot(rules, slot, draft.snapshotFor(slot));
        final given = overrides[slot] ?? const <String>{};
        if (blockingViolations(results, given).isNotEmpty) {
          violating.add(slot);
          continue;
        }
        // Čuvaju se samo izuzeci za pravila koja jelo zaista krši.
        final used = [
          for (final r in results)
            if (r.fit == RuleFit.fail && given.contains(r.rule.id)) r.rule.id,
        ];
        allowed[slot] = used.isEmpty ? null : jsonEncode(used);
      }
      if (violating.isNotEmpty) throw RuleViolationException(violating);
      final base = draft.base;
      final String planId;
      final existing = <MealSlot, MealPlanEntryRow>{};
      if (base == null) {
        planId = newId();
        await _insertPlan(planId, draft.request);
      } else {
        if (await fingerprint(base.planId) != base.fingerprint ||
            base.fingerprint.isEmpty) {
          throw const StaleDraftException();
        }
        planId = base.planId;
        for (final e in await _entriesQuery(planId).get()) {
          existing[_slotOf(e)] = e;
        }
      }

      final library = {
        for (final r in await (_db.select(
          _db.recipes,
        )..where((t) => t.householdId.equals(_scope.householdId))).get())
          r.id,
      };
      // Novi recepti iz predloga idu i u Recepte (sažetak, bez koraka);
      // isti recept na više mesta je jedan recept.
      final created = <String, String>{};
      for (final slot in ready) {
        final key = draft.proposals[slot]!.draftRecipeKey;
        if (key == null || created.containsKey(key)) continue;
        created[key] = await _insertRecipe(draft.newRecipes[key]!);
      }
      final today = CivilDate.today(_clock);
      for (final slot in ready) {
        final proposal = draft.proposals[slot]!;
        final snapshot = jsonEncode(draft.snapshotFor(slot)!.toJson());
        final recipeId = proposal.isNew
            ? created[proposal.draftRecipeKey]
            : library.contains(proposal.libraryRecipeId)
            ? proposal.libraryRecipeId
            : null;
        final current = existing[slot];
        if (current == null) {
          final id = newId();
          await _db
              .into(_db.mealPlanEntries)
              .insert(
                MealPlanEntriesCompanion.insert(
                  id: id,
                  planId: planId,
                  date: slot.date.toWire(),
                  mealType: slot.type.name,
                  recipeId: Value(recipeId),
                  servings: Value(draft.request.servings),
                  recipeSnapshotJson: Value(snapshot),
                  ruleOverridesJson: Value(allowed[slot]),
                  householdId: Value(_scope.householdId),
                ),
              );
          await _writer.upsert(_entry, id);
          continue;
        }
        if (current.isLocked || current.isCooked || slot.date.isBefore(today)) {
          throw const StaleDraftException();
        }
        await (_db.update(
          _db.mealPlanEntries,
        )..where((t) => t.id.equals(current.id))).write(
          MealPlanEntriesCompanion(
            recipeId: Value(recipeId),
            // Zamena jela ne menja porcije koje je osoba izabrala za obrok.
            servings: Value(current.servings ?? draft.request.servings),
            recipeSnapshotJson: Value(snapshot),
            // Novo jelo: stari izuzeci ne važe.
            ruleOverridesJson: Value(allowed[slot]),
          ),
        );
        await _writer.upsert(_entry, current.id);
      }
      await _shopping.reconcilePlan(planId);
      return planId;
    });
  }

  /// Porcije jednog obroka (1–20); nabavka se usklađuje.
  Future<void> changeServings(String entryId, int servings) {
    if (servings < minServings || servings > maxServings) {
      throw ArgumentError.value(servings, 'servings');
    }
    return _edit(entryId, (e) async {
      if (e.isCooked) throw const ProtectedMealException();
      return MealPlanEntriesCompanion(servings: Value(servings));
    });
  }

  /// Zaključan obrok ponovni predlog ne menja.
  Future<void> setLocked(String entryId, {required bool locked}) => _edit(
    entryId,
    (_) async => MealPlanEntriesCompanion(isLocked: Value(locked)),
  );

  /// Skuvan obrok više ne traži kupovinu; kupljeno i zaliha ostaju.
  Future<void> setCooked(String entryId, {required bool cooked}) => _edit(
    entryId,
    (_) async => MealPlanEntriesCompanion(isCooked: Value(cooked)),
  );

  /// Dozvoljava (ili ukida) izuzetak od pravila dana baš za ovaj obrok.
  Future<void> setRuleOverride(
    String entryId,
    String ruleId, {
    required bool allowed,
  }) => _edit(entryId, (e) async {
    final current = _overrides(e.ruleOverridesJson);
    final next = allowed
        ? {...current, ruleId}
        : ({...current}..remove(ruleId));
    return MealPlanEntriesCompanion(
      ruleOverridesJson: Value(next.isEmpty ? null : jsonEncode(next.toList())),
    );
  });

  Future<List<DayRule>> _rules() async => [
    for (final r in await (_db.select(
      _db.dayRules,
    )..where((t) => t.householdId.equals(_scope.householdId))).get())
      ?DayRuleRepository.fromRow(r),
  ];

  static Set<String> _overrides(String? json) {
    if (json == null) return const {};
    try {
      return {
        for (final id in jsonDecode(json) as List<dynamic>)
          if (id is String) id,
      };
    } on Object {
      return const {};
    }
  }

  /// Uklanja obrok iz plana i oslobađa njegovu potrebu; kupljeno ostaje.
  Future<void> removeMeal(String entryId) => _db.transaction(() async {
    final e = await _findEntry(entryId);
    if (e.isLocked || e.isCooked) throw const ProtectedMealException();
    final sources =
        await (_db.select(_db.shoppingSources)..where(
              (t) =>
                  t.planEntryId.equals(entryId) &
                  t.householdId.equals(_scope.householdId),
            ))
            .get();
    for (final s in sources) {
      await _shopping.removeSource(s.id);
    }
    await (_db.delete(
      _db.mealPlanEntries,
    )..where((t) => t.id.equals(entryId))).go();
    await _writer.delete(_entry, entryId);
    await _shopping.reconcilePlan(e.planId);
  });

  Future<MealPlanEntryRow> _findEntry(String entryId) async {
    final e =
        await (_db.select(_db.mealPlanEntries)..where(
              (t) =>
                  t.id.equals(entryId) &
                  t.householdId.equals(_scope.householdId),
            ))
            .getSingleOrNull();
    if (e == null) throw const MealNotFoundException();
    return e;
  }

  Future<void> _edit(
    String entryId,
    Future<MealPlanEntriesCompanion> Function(MealPlanEntryRow e) change,
  ) => _db.transaction(() async {
    final e = await _findEntry(entryId);
    await (_db.update(
      _db.mealPlanEntries,
    )..where((t) => t.id.equals(entryId))).write(await change(e));
    await _writer.upsert(_entry, entryId);
    await _shopping.reconcilePlan(e.planId);
  });

  Future<String> _insertRecipe(RecipeSnapshot r) async {
    final id = newId();
    final now = _clock().toUtc();
    await _db
        .into(_db.recipes)
        .insert(
          RecipesCompanion.insert(
            id: id,
            title: r.title,
            servings: r.baseServings,
            prepMinutes: Value(r.prepMinutes),
            source: RecipeSource.ai.name,
            ingredientsJson: jsonEncode([
              for (final i in r.ingredients) i.toJson(),
            ]),
            stepsJson: jsonEncode(r.steps),
            createdAt: now,
            updatedAt: now,
            householdId: Value(_scope.householdId),
          ),
        );
    await _writer.upsert(_recipe, id);
    return id;
  }

  Future<void> _insertPlan(String id, PlanRequest request) async {
    await _db
        .into(_db.mealPlans)
        .insert(
          MealPlansCompanion.insert(
            id: id,
            startDate: request.range.start.toWire(),
            endDate: request.range.end.toWire(),
            mealTypesJson: jsonEncode([
              for (final t in MealType.values)
                if (request.mealTypes.contains(t)) t.name,
            ]),
            usePantry: Value(request.usePantry),
            defaultServings: Value(request.servings),
            createdAt: _clock().toUtc(),
            householdId: Value(_scope.householdId),
          ),
        );
    await _writer.upsert(_plan, id);
  }

  SimpleSelectStatement<$MealPlansTable, MealPlanRow> _planQuery(
    String planId,
  ) => _db.select(_db.mealPlans)
    ..where(
      (t) => t.id.equals(planId) & t.householdId.equals(_scope.householdId),
    );

  SimpleSelectStatement<$MealPlanEntriesTable, MealPlanEntryRow> _entriesQuery(
    String planId,
  ) => _db.select(_db.mealPlanEntries)
    ..where(
      (t) => t.planId.equals(planId) & t.householdId.equals(_scope.householdId),
    );

  static MealSlot _slotOf(MealPlanEntryRow e) => MealSlot(
    CivilDate.fromWire(e.date),
    MealType.tryParse(e.mealType) ?? MealType.lunch,
  );

  static int _bySlot(PlannedMeal a, PlannedMeal b) {
    final s = a.slot.compareTo(b.slot);
    return s != 0 ? s : a.id.compareTo(b.id);
  }

  static MealPlan _planFromRow(MealPlanRow r) => MealPlan(
    id: r.id,
    range: DateRange(CivilDate.fromWire(r.startDate), _end(r)),
    mealTypes: {
      for (final t in jsonDecode(r.mealTypesJson) as List<dynamic>)
        ?MealType.tryParse(t),
    },
    defaultServings: r.defaultServings,
    usePantry: r.usePantry,
    createdAt: r.createdAt,
  );

  // Pokvaren raspon sa servera (kraj pre početka) ne sme da sruši ekran.
  static CivilDate _end(MealPlanRow r) {
    final start = CivilDate.fromWire(r.startDate);
    final end = CivilDate.fromWire(r.endDate);
    return end.isBefore(start) ? start : end;
  }

  static PlannedMeal _mealFromRow(MealPlanEntryRow e) {
    RecipeSnapshot? snapshot;
    final json = e.recipeSnapshotJson;
    if (json != null) {
      try {
        snapshot = RecipeSnapshot.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );
      } on FormatException {
        snapshot = null;
      }
    }
    return PlannedMeal(
      id: e.id,
      planId: e.planId,
      slot: _slotOf(e),
      servings: e.servings ?? snapshot?.baseServings ?? 2,
      snapshot: snapshot,
      recipeId: e.recipeId,
      isLocked: e.isLocked,
      isCooked: e.isCooked,
      ruleOverrides: _overrides(e.ruleOverridesJson),
    );
  }
}
