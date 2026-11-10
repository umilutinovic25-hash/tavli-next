import 'shopping_demand.dart';

enum SupplyOrigin { pantry, purchase }

/// Potvrđena zaliha: stavka iz ostave ili kupljena stavka.
class Supply {
  const Supply({
    required this.id,
    required this.origin,
    required this.ingredient,
    required this.unitGroup,
    required this.micros,
    this.samePhysicalAs,
    this.dictionaryIngredient,
    this.dictionaryUnitGroup,
  });

  final String id;
  final SupplyOrigin origin;

  /// Ključ sastojka (`ingredientKey`) i grupa jedinica kao u potražnji.
  final String ingredient;
  final String unitGroup;

  /// V1 aliases point to the same physical capacity, never a second supply.
  final String? dictionaryIngredient;
  final String? dictionaryUnitGroup;

  /// Potvrđena količina u osnovnoj jedinici; `null` = nepotvrđeno, ne pokriva
  /// brojčanu potrebu.
  final int? micros;

  /// Prijem kupljenog u ostavu pokazuje na kupljenu stavku: to je ista
  /// zaliha, ne nova.
  final String? samePhysicalAs;

  /// Kanonski identitet zalihe; kupovina i njen prijem dele isti.
  String get canonicalId => samePhysicalAs ?? id;
}

/// Hronološki redosled potražnje. Planirani obroci idu po datumu, pa po
/// vrsti obroka; samostalne pripreme bez datuma idu posle njih.
class DemandOrder {
  const DemandOrder({this.date, this.mealOrder = 0});

  /// Kalendarski datum (UTC ponoć istog dana) ili `null`.
  final DateTime? date;
  final int mealOrder;
}

class DemandRequest {
  const DemandRequest(this.line, this.order);

  final DemandLine line;
  final DemandOrder order;
}

typedef Allocation = ({DemandKey demand, String supplyId, int micros});

class AllocationResult {
  AllocationResult._(this.allocations, this._remaining);

  final List<Allocation> allocations;
  final Map<DemandKey, int?> _remaining;

  /// Koliko još treba kupiti; `null` kad je količina nepoznata i nije
  /// izričito potvrđena, pa traži proveru.
  int? remaining(DemandKey key) {
    if (!_remaining.containsKey(key)) {
      throw ArgumentError.value(key, 'key', 'Nepoznata potražnja');
    }
    return _remaining[key];
  }

  bool isCovered(DemandKey key) => remaining(key) == 0;

  int get allocatedTotal => allocations.fold(0, (sum, a) => sum + a.micros);
}

/// Raspoređuje potvrđenu zalihu na potražnju, determinisano: hronološki,
/// pa vrsta obroka, pa id izvora. Svaka zaliha se troši jednom kroz ceo plan;
/// kupovina i njen prijem u ostavu su jedna zaliha (važi potvrđena količina
/// prijema). [confirmedWhole] su unosi za koje je osoba potvrdila "imam celu
/// stavku"; oni ne troše brojčanu zalihu.
AllocationResult allocateSupply(
  List<DemandRequest> demands,
  List<Supply> supplies, {
  Set<DemandKey> confirmedWhole = const {},
}) {
  final capacity = <String, Supply>{};
  for (final s in supplies) {
    final m = s.micros;
    if (m != null && m < 0) {
      throw ArgumentError.value(m, 'micros', 'Negativna zaliha');
    }
    final prev = capacity[s.canonicalId];
    // Prijem ima prednost nad kupovinom: to je potvrđeno stanje kod kuće.
    if (prev == null || (s.samePhysicalAs != null && m != null)) {
      capacity[s.canonicalId] = s;
    }
  }
  final left = {
    for (final MapEntry(:key, :value) in capacity.entries)
      if (value.micros != null) key: value.micros!,
  };
  final supplyOrder = left.keys.toList()..sort();

  final ordered = [...demands]..sort(_compare);
  final allocations = <Allocation>[];
  final remaining = <DemandKey, int?>{};
  for (final d in ordered) {
    final key = d.line.key;
    if (confirmedWhole.contains(key)) {
      remaining[key] = 0;
      continue;
    }
    var need = d.line.micros;
    if (need == null) {
      remaining[key] = null;
      continue;
    }
    for (final id in supplyOrder) {
      if (need == 0) break;
      final s = capacity[id]!;
      final legacyMatch =
          s.ingredient == key.ingredient && s.unitGroup == key.unitGroup;
      final dictionaryMatch =
          s.dictionaryIngredient == key.ingredient &&
          s.dictionaryUnitGroup == key.unitGroup;
      if (!legacyMatch && !dictionaryMatch) {
        continue;
      }
      final take = need! < left[id]! ? need : left[id]!;
      if (take == 0) continue;
      left[id] = left[id]! - take;
      need -= take;
      allocations.add((demand: key, supplyId: id, micros: take));
    }
    remaining[key] = need;
  }
  return AllocationResult._(allocations, remaining);
}

int _compare(DemandRequest a, DemandRequest b) {
  final ad = a.order.date, bd = b.order.date;
  if (ad != bd) {
    if (ad == null) return 1;
    if (bd == null) return -1;
    final c = ad.compareTo(bd);
    if (c != 0) return c;
  }
  final m = a.order.mealOrder.compareTo(b.order.mealOrder);
  if (m != 0) return m;
  final ak = a.line.key, bk = b.line.key;
  for (final c in [
    ak.sourceId.compareTo(bk.sourceId),
    ak.ingredient.compareTo(bk.ingredient),
    ak.unitGroup.compareTo(bk.unitGroup),
  ]) {
    if (c != 0) return c;
  }
  return 0;
}
