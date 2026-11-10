/// Plan obroka: zahtev za generisanje i nacrt koji osoba pregleda pre
/// čuvanja. Nacrt živi samo u sesiji; čuva se tek odobren.
library;

import 'day_rules.dart';
import 'plan_calendar.dart';
import 'shopping_demand.dart' show maxServings, minServings;
import 'shopping_source.dart';

/// Vrste obroka, redom kojim idu u danu. `name` je vrednost u bazi.
enum MealType {
  breakfast('Doručak'),
  lunch('Ručak'),
  dinner('Večera');

  const MealType(this.label);

  final String label;

  static MealType? tryParse(Object? name) =>
      values.asNameMap()[name is String ? name.trim() : null];
}

/// Vrsta obroka u planu. `away` zauzima mesto, ali ne traži namirnice.
enum MealKind {
  cook,
  away;

  /// Prazno je stari zapis (kuva se); nepoznata vrsta sa novije verzije
  /// zauzima mesto bez nabavke, kao [away].
  static MealKind parse(String? name) => switch (name) {
    null || 'cook' => cook,
    _ => away,
  };
}

/// Zašto se obrok ne kuva kod kuće. `name` je vrednost u bazi.
enum AwayReason {
  restaurant('Restoran'),
  visiting('Kod roditelja'),
  skip('Preskačem');

  const AwayReason(this.label);

  final String label;

  static AwayReason? tryParse(Object? name) =>
      values.asNameMap()[name is String ? name : null];
}

/// Najduža napomena uz obrok van kuće.
const maxAwayNoteLength = 80;

/// Najduži plan: ceo kalendarski mesec.
const maxPlanDays = 31;

/// Jedno mesto u planu: datum i vrsta obroka.
class MealSlot implements Comparable<MealSlot> {
  const MealSlot(this.date, this.type);

  final CivilDate date;
  final MealType type;

  @override
  int compareTo(MealSlot other) {
    final d = date.compareTo(other.date);
    return d != 0 ? d : type.index - other.type.index;
  }

  @override
  bool operator ==(Object other) =>
      other is MealSlot && other.date == date && other.type == type;

  @override
  int get hashCode => Object.hash(date, type);

  @override
  String toString() => '$date/${type.name}';
}

/// Šta osoba traži od plana. Proverava se pre nego što se pita AI.
class PlanRequest {
  PlanRequest({
    required this.range,
    required Set<MealType> mealTypes,
    this.servings = 2,
    this.usePantry = true,
    this.wishes,
    this.pantryNames = const [],
    this.rules = const [],
    Set<MealSlot>? only,
  }) : mealTypes = Set.unmodifiable(mealTypes),
       only = only == null ? null : Set.unmodifiable(only) {
    if (mealTypes.isEmpty) {
      throw ArgumentError('Izaberi bar jedan obrok');
    }
    if (only != null &&
        (only.isEmpty ||
            only.any(
              (s) => !range.contains(s.date) || !mealTypes.contains(s.type),
            ))) {
      throw ArgumentError('Mesta za predlog nisu u planu');
    }
    if (servings < minServings || servings > maxServings) {
      throw ArgumentError.value(servings, 'servings');
    }
    if (range.dayCount > maxPlanDays) {
      throw ArgumentError('Plan je duži od $maxPlanDays dana');
    }
  }

  final DateRange range;
  final Set<MealType> mealTypes;
  final int servings;
  final bool usePantry;

  /// Slobodne želje osobe (npr. "bez svinjetine, više povrća").
  final String? wishes;

  /// Nazivi potvrđene zalihe; koriste se samo kad je [usePantry].
  final List<String> pantryNames;

  /// Pravila po danima domaćinstva (AI ih dobija; čuvanje ih proverava).
  final List<DayRule> rules;

  /// Samo ova mesta (zamena jednog jela ili ponovni predlog bez zaštićenih
  /// obroka); null = sva mesta plana.
  final Set<MealSlot>? only;

  /// Mesta za predlog, hronološki.
  List<MealSlot> get slots => [
    for (final d in range.days)
      for (final t in MealType.values)
        if (mealTypes.contains(t) && (only?.contains(MealSlot(d, t)) ?? true))
          MealSlot(d, t),
  ];
}

/// Predlog za jedno mesto: recept iz biblioteke ili nov recept iz nacrta.
class SlotProposal {
  const SlotProposal({
    required this.title,
    this.libraryRecipeId,
    this.draftRecipeKey,
  }) : assert((libraryRecipeId == null) != (draftRecipeKey == null));

  final String title;
  final String? libraryRecipeId;

  /// Ključ novog recepta u [PlanDraft.newRecipes].
  final String? draftRecipeKey;

  bool get isNew => draftRecipeKey != null;
}

/// Ključ novog recepta: naziv bez razlike u velikim slovima i razmacima.
/// Isti naziv dva puta u planu je isti recept.
String draftRecipeKey(String title) =>
    title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Sačuvan plan kakav je bio kad je nacrt počeo. Ako se u međuvremenu
/// promenio, nacrt je zastareo i ne čuva se.
class PlanBase {
  const PlanBase({required this.planId, required this.fingerprint});

  final String planId;
  final String fingerprint;
}

/// Nacrt plana u sesiji. Zna šta je gotovo i šta još nedostaje, pa
/// ponovni pokušaj traži samo to.
class PlanDraft {
  PlanDraft({
    required this.request,
    Map<MealSlot, SlotProposal> proposals = const {},
    Map<String, RecipeSnapshot> newRecipes = const {},
    Map<String, RecipeSnapshot> libraryRecipes = const {},
    this.base,
  }) : proposals = Map.unmodifiable(proposals),
       newRecipes = Map.unmodifiable(newRecipes),
       libraryRecipes = Map.unmodifiable(libraryRecipes);

  final PlanRequest request;
  final Map<MealSlot, SlotProposal> proposals;

  /// Plan koji nacrt menja (zamena ili ponovno generisanje), null za nov.
  final PlanBase? base;

  /// Novi recepti po [draftRecipeKey] (sažetak, bez koraka).
  final Map<String, RecipeSnapshot> newRecipes;

  /// Snimci recepata iz biblioteke po id-ju, u trenutku predloga.
  final Map<String, RecipeSnapshot> libraryRecipes;

  List<MealSlot> get missingSlots => [
    for (final s in request.slots)
      if (!proposals.containsKey(s)) s,
  ];

  /// Novi recepti koji su predloženi, a još nemaju sastojke.
  List<String> get missingRecipeKeys {
    final keys = <String>{};
    for (final p in proposals.values) {
      final key = p.draftRecipeKey;
      if (key != null && !newRecipes.containsKey(key)) keys.add(key);
    }
    return keys.toList();
  }

  /// Snimak recepta za mesto, ili null dok nije spreman.
  RecipeSnapshot? snapshotFor(MealSlot slot) {
    final p = proposals[slot];
    if (p == null) return null;
    return p.isNew
        ? newRecipes[p.draftRecipeKey]
        : libraryRecipes[p.libraryRecipeId];
  }

  /// Mesta koja imaju predlog i recept, spremna za čuvanje.
  List<MealSlot> get readySlots => [
    for (final s in request.slots)
      if (snapshotFor(s) != null) s,
  ];

  bool get isComplete => readySlots.length == request.slots.length;

  PlanDraft copyWith({
    Map<MealSlot, SlotProposal>? proposals,
    Map<String, RecipeSnapshot>? newRecipes,
    Map<String, RecipeSnapshot>? libraryRecipes,
  }) => PlanDraft(
    request: request,
    proposals: proposals ?? this.proposals,
    newRecipes: newRecipes ?? this.newRecipes,
    libraryRecipes: libraryRecipes ?? this.libraryRecipes,
    base: base,
  );
}

/// Sačuvan plan, kako ga je osoba odobrila.
class MealPlan {
  const MealPlan({
    required this.id,
    required this.range,
    required this.mealTypes,
    required this.defaultServings,
    required this.usePantry,
    required this.createdAt,
  });

  final String id;
  final DateRange range;
  final Set<MealType> mealTypes;
  final int defaultServings;
  final bool usePantry;
  final DateTime createdAt;

  List<MealSlot> get slots => [
    for (final d in range.days)
      for (final t in MealType.values)
        if (mealTypes.contains(t)) MealSlot(d, t),
  ];
}

/// Obrok u sačuvanom planu, sa receptom odobrenim u trenutku planiranja.
class PlannedMeal {
  const PlannedMeal({
    required this.id,
    required this.planId,
    required this.slot,
    required this.servings,
    this.snapshot,
    this.recipeId,
    this.isLocked = false,
    this.isCooked = false,
    this.kind = MealKind.cook,
    this.awayReason,
    this.awayNote,
    this.ruleOverrides = const {},
  });

  final String id;
  final String planId;
  final MealSlot slot;
  final int servings;

  /// Kod [MealKind.away] snimak (ako postoji) je jelo pre promene, da
  /// može da se vrati; nabavka ga ne vidi.
  final MealKind kind;
  final AwayReason? awayReason;
  final String? awayNote;

  bool get isAway => kind == MealKind.away;

  /// "Restoran · sa kolegama"; nepoznat razlog je "Van kuće".
  String get awayTitle =>
      [awayReason?.label ?? 'Van kuće', ?awayNote].join(' · ');

  /// Obavezna pravila dana (id) dozvoljena baš za ovaj obrok.
  final Set<String> ruleOverrides;

  /// null samo za stari unos bez snimka.
  final RecipeSnapshot? snapshot;

  /// Recept iz biblioteke, ako ga ima (posle brisanja recepta je null).
  final String? recipeId;
  final bool isLocked;
  final bool isCooked;
}

/// Mesta plana koja ponovni predlog sme da menja: bez zaključanih,
/// skuvanih, obroka van kuće i prošlih obroka.
Set<MealSlot> regenerableSlots(
  MealPlan plan,
  List<PlannedMeal> meals,
  CivilDate today,
) {
  final protected = {
    for (final m in meals)
      if (m.isLocked || m.isCooked || m.isAway) m.slot,
  };
  return {
    for (final s in plan.slots)
      if (!s.date.isBefore(today) && !protected.contains(s)) s,
  };
}
