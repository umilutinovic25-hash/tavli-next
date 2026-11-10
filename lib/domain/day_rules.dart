/// Pravila po danima ("ponedeljak bez mesa", "petak riba") i njihova
/// provera nad sastojcima odobrenog recepta. Provera je deterministička:
/// prepoznat sastojak daje "poštuje"/"krši" sa dokazom, a neprepoznat
/// sastojak iz kategorije meso i riba daje "neprovereno".
library;

import 'meal_plan.dart';
import 'recipe.dart';
import 'recipe_format.dart' show normalizeForSearch;
import 'shopping_source.dart';

enum RuleKind {
  noMeat('bez mesa'),
  fish('riba'),
  without('bez sastojka'),
  withIngredient('sa sastojkom');

  const RuleKind(this.label);

  final String label;

  bool get needsValue => this == without || this == withIngredient;

  static RuleKind? tryParse(Object? name) =>
      values.asNameMap()[name is String ? name : null];
}

enum RuleMode {
  required,
  preferred;

  static RuleMode parse(Object? name) =>
      name == preferred.name ? preferred : required;
}

const weekdayNames = [
  'Ponedeljak',
  'Utorak',
  'Sreda',
  'Četvrtak',
  'Petak',
  'Subota',
  'Nedelja',
];

/// Najduži naziv sastojka u pravilu.
const maxRuleValueLength = 40;

class DayRule {
  const DayRule({
    required this.id,
    required this.weekday,
    required this.kind,
    this.mealType,
    this.value,
    this.mode = RuleMode.required,
  });

  final String id;

  /// 1 = ponedeljak … 7 = nedelja.
  final int weekday;

  /// null = svi obroci tog dana.
  final MealType? mealType;
  final RuleKind kind;

  /// Naziv sastojka za [RuleKind.without] i [RuleKind.withIngredient].
  final String? value;
  final RuleMode mode;

  bool appliesTo(MealSlot slot) =>
      slot.date.weekday == weekday &&
      (mealType == null || mealType == slot.type);

  /// "Ponedeljak · bez mesa", "Petak · ručak · riba", "Sreda · bez: luk
  /// (želja)".
  String get label {
    final what = switch (kind) {
      RuleKind.without => 'bez: $value',
      RuleKind.withIngredient => 'sa: $value',
      _ => kind.label,
    };
    return [
          weekdayNames[weekday - 1],
          ?mealType?.label.toLowerCase(),
          what,
        ].join(' · ') +
        (mode == RuleMode.preferred ? ' (želja)' : '');
  }

  /// Opis za AI (engleski, kao ostatak upita).
  String get promptLine {
    final day = const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][weekday - 1];
    final meal = mealType == null ? 'all meals' : mealType!.name;
    final what = switch (kind) {
      RuleKind.noMeat => 'no meat (fish is allowed)',
      RuleKind.fish => 'a fish dish',
      RuleKind.without => 'without "$value"',
      RuleKind.withIngredient => 'with "$value"',
    };
    final strength = mode == RuleMode.required ? 'required' : 'preferred';
    return '$day ($meal): $what — $strength';
  }
}

/// Proverava pravilo; baca [ArgumentError] na neispravan unos.
DayRule validRule(DayRule r) {
  if (r.weekday < 1 || r.weekday > 7) {
    throw ArgumentError.value(r.weekday, 'weekday');
  }
  final v = r.value?.trim() ?? '';
  if (r.kind.needsValue && (v.isEmpty || v.length > maxRuleValueLength)) {
    throw ArgumentError.value(r.value, 'value');
  }
  if (!r.kind.needsValue && r.value != null) {
    throw ArgumentError.value(r.value, 'value');
  }
  return r;
}

enum RuleFit { pass, fail, unknown }

class RuleResult {
  const RuleResult(this.rule, this.fit, [this.evidence = const []]);

  final DayRule rule;
  final RuleFit fit;

  /// Sastojci koji su odlučili (srpski nazivi iz recepta).
  final List<String> evidence;
}

// Početci reči (bez kvačica) za meso i ribu; kratke reči samo cele.
const _meatStems = [
  'meso',
  'mesa',
  'mesn',
  'pacet',
  'patk',
  'pacje',
  'svinj',
  'junet',
  'junec',
  'juneć',
  'goved',
  'teletin',
  'telec',
  'teleć',
  'pilet',
  'pilec',
  'pileć',
  'curet',
  'cureć',
  'curec',
  'jagnjet',
  'jagnjec',
  'kobasic',
  'slanin',
  'sunk',
  'pecenic',
  'kulen',
  'cvarc',
  'cevap',
  'pljeskavic',
  'kranjsk',
  'virsl',
  'salam',
  'pancet',
  'prsut',
  'batak',
  'karabatak',
  'krilc',
  'cufte',
  'curetin',
  'piletin',
  'svinjetin',
  'govedin',
  'jagnjetin',
  'dzigeric',
  'iznutric',
  'kotlet',
  'odrezak',
  'stek',
  'gulas',
];
const _fishStems = [
  'rib',
  'tunjevin',
  'tunj',
  'losos',
  'oslic',
  'sardin',
  'skus',
  'pastrmk',
  'saran',
  'smudj',
  'bakalar',
  'incun',
  'skamp',
  'lignj',
  'hobotnic',
  'skoljk',
  'dagnj',
  'kozic',
  'brancin',
  'orad',
  'haringa',
  'skusa',
];
const _fishWords = {'som', 'rak', 'raci', 'rakovi', 'tuna'};

List<String> _tokens(String name) =>
    normalizeForSearch(name)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();

bool _isMeat(Ingredient i) =>
    _tokens(i.name).any((t) => _meatStems.any(t.startsWith));

bool _isFish(Ingredient i) =>
    _tokens(i.name)
        .any((t) => _fishWords.contains(t) || _fishStems.any(t.startsWith));

bool _contains(Ingredient i, String value) {
  final name = _tokens(i.name);
  final query = _tokens(value);
  if (query.isEmpty || query.length > name.length) return false;
  for (var start = 0; start <= name.length - query.length; start++) {
    var matches = true;
    for (var j = 0; j < query.length; j++) {
      final token = query[j];
      if (name[start + j] != token &&
          !(token.length >= 4 && name[start + j].startsWith(token))) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

RuleResult evaluateRule(DayRule rule, RecipeSnapshot? snapshot) {
  final items = snapshot?.ingredients ?? const <Ingredient>[];
  if (items.isEmpty) return RuleResult(rule, RuleFit.unknown);
  // Iz kategorije meso i riba, a nije prepoznato ni kao meso ni kao riba.
  final unclassified = [
    for (final i in items)
      if (i.category == 'meso i riba' && !_isMeat(i) && !_isFish(i)) i.name,
  ];
  switch (rule.kind) {
    case RuleKind.noMeat:
      final meat = [
        for (final i in items)
          if (_isMeat(i) && !_isFish(i)) i.name,
      ];
      if (meat.isNotEmpty) return RuleResult(rule, RuleFit.fail, meat);
      if (unclassified.isNotEmpty) {
        return RuleResult(rule, RuleFit.unknown, unclassified);
      }
      return RuleResult(rule, RuleFit.pass);
    case RuleKind.fish:
      final fish = [
        for (final i in items)
          if (_isFish(i)) i.name,
      ];
      if (fish.isNotEmpty) return RuleResult(rule, RuleFit.pass, fish);
      if (unclassified.isNotEmpty) {
        return RuleResult(rule, RuleFit.unknown, unclassified);
      }
      return RuleResult(rule, RuleFit.fail);
    case RuleKind.without:
      final found = [
        for (final i in items)
          if (_contains(i, rule.value!)) i.name,
      ];
      return found.isEmpty
          ? RuleResult(rule, RuleFit.pass)
          : RuleResult(rule, RuleFit.fail, found);
    case RuleKind.withIngredient:
      final found = [
        for (final i in items)
          if (_contains(i, rule.value!)) i.name,
      ];
      return found.isEmpty
          ? RuleResult(rule, RuleFit.fail)
          : RuleResult(rule, RuleFit.pass, found);
  }
}

/// Provera svih pravila koja važe za mesto.
List<RuleResult> evaluateSlot(
  List<DayRule> rules,
  MealSlot slot,
  RecipeSnapshot? snapshot,
) => [
  for (final r in rules)
    if (r.appliesTo(slot)) evaluateRule(r, snapshot),
];

/// Obavezna pravila koja jelo krši, a za ovaj obrok nema izuzetka.
List<RuleResult> blockingViolations(
  List<RuleResult> results,
  Set<String> overrides,
) => [
  for (final r in results)
    if (r.fit == RuleFit.fail &&
        r.rule.mode == RuleMode.required &&
        !overrides.contains(r.rule.id))
      r,
];

/// Tekst rezultata za prikaz; null kad pravilo prolazi bez napomene.
String? ruleResultText(RuleResult r, {bool overridden = false}) {
  final evidence = r.evidence.isEmpty ? '' : ' (${r.evidence.join(', ')})';
  return switch (r.fit) {
    RuleFit.pass => null,
    RuleFit.unknown => 'Neprovereno: ${r.rule.label}$evidence',
    RuleFit.fail when overridden => 'Izuzetak: ${r.rule.label}$evidence',
    RuleFit.fail when r.rule.mode == RuleMode.preferred =>
      'Odstupa od želje: ${r.rule.label}$evidence',
    RuleFit.fail => 'Krši pravilo: ${r.rule.label}$evidence',
  };
}
