/// Raspoloživo vreme po danu u nedelji i provera da li recept staje.
/// Staro "vreme pripreme" (prepMinutes) nije ni aktivno ni ukupno vreme:
/// bez potvrđenog vremena provera je "nepoznato", ne "staje".
library;

/// Najviše minuta za jedno vreme (aktivno, ukupno, limit).
const maxTimeMinutes = 24 * 60;

/// Ograničenje za jedan dan u nedelji (1 = ponedeljak … 7 = nedelja).
class DayBudget {
  const DayBudget({
    required this.weekday,
    this.maxActiveMinutes,
    this.windowStart,
    this.windowEnd,
  }) : assert(weekday >= 1 && weekday <= 7);

  final int weekday;

  /// Najviše aktivnog rada za jedan obrok tog dana.
  final int? maxActiveMinutes;

  /// Prozor za kuvanje u minutima od ponoći (npr. 18:00 = 1080).
  final int? windowStart;
  final int? windowEnd;

  /// Trajanje prozora; null kad prozor nije zadat ili nije ispravan.
  int? get windowMinutes {
    final s = windowStart;
    final e = windowEnd;
    if (s == null || e == null || e <= s) return null;
    return e - s;
  }

  bool get isEmpty => maxActiveMinutes == null && windowMinutes == null;

  @override
  bool operator ==(Object other) =>
      other is DayBudget &&
      other.weekday == weekday &&
      other.maxActiveMinutes == maxActiveMinutes &&
      other.windowStart == windowStart &&
      other.windowEnd == windowEnd;

  @override
  int get hashCode =>
      Object.hash(weekday, maxActiveMinutes, windowStart, windowEnd);
}

/// Proverava ograničenje; baca [ArgumentError] na neispravan unos.
DayBudget validBudget(DayBudget b) {
  final limit = b.maxActiveMinutes;
  if (limit != null && (limit <= 0 || limit > maxTimeMinutes)) {
    throw ArgumentError.value(limit, 'maxActiveMinutes');
  }
  final s = b.windowStart;
  final e = b.windowEnd;
  if ((s == null) != (e == null)) throw ArgumentError('Prozor bez kraja');
  if (s != null && e != null && (s < 0 || e > maxTimeMinutes || e <= s)) {
    throw ArgumentError('Kraj prozora mora biti posle početka');
  }
  return b;
}

/// Potvrđeno vreme je pozitivno, najviše dan, i aktivno nije duže od
/// ukupnog.
bool isValidTiming({int? activeMinutes, int? totalMinutes}) {
  for (final m in [activeMinutes, totalMinutes]) {
    if (m != null && (m <= 0 || m > maxTimeMinutes)) return false;
  }
  return activeMinutes == null ||
      totalMinutes == null ||
      activeMinutes <= totalMinutes;
}

/// Kao [isValidTiming], ali baca [ArgumentError].
void validateTiming({int? activeMinutes, int? totalMinutes}) {
  if (!isValidTiming(
    activeMinutes: activeMinutes,
    totalMinutes: totalMinutes,
  )) {
    throw ArgumentError('Neispravno vreme recepta');
  }
}

enum TimeFit { fits, exceeds, unknown }

/// Rezultat provere sa objašnjenjima (srpski, za prikaz).
class TimeCheck {
  const TimeCheck(this.fit, this.reasons);

  final TimeFit fit;
  final List<String> reasons;
}

/// "18:00"
String clockLabel(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// "18:00" ili "18" → minuti od ponoći; null kad nije ispravno.
int? parseClock(String text) {
  final m = RegExp(r'^(\d{1,2})(?::(\d{2}))?$').firstMatch(text.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2) ?? '0');
  if (h > 24 || min > 59 || (h == 24 && min > 0)) return null;
  return h * 60 + min;
}

/// null kad dan nema ograničenja. Aktivni rad se meri limitom, ukupno
/// vreme prozorom; prekoračenje je jače od nepoznatog.
TimeCheck? checkTime({
  required DayBudget? budget,
  int? activeMinutes,
  int? totalMinutes,
}) {
  if (budget == null || budget.isEmpty) return null;
  final exceeds = <String>[];
  final unknown = <String>[];
  if (budget.maxActiveMinutes case final limit?) {
    if (activeMinutes == null) {
      unknown.add('Aktivno vreme nije potvrđeno (limit $limit min).');
    } else if (activeMinutes > limit) {
      exceeds.add('Aktivno $activeMinutes min, limit $limit min.');
    }
  }
  if (budget.windowMinutes case final window?) {
    final range =
        '${clockLabel(budget.windowStart!)}–${clockLabel(budget.windowEnd!)}';
    if (totalMinutes == null) {
      unknown.add('Ukupno vreme nije potvrđeno (prozor $range).');
    } else if (totalMinutes > window) {
      exceeds.add('Ukupno $totalMinutes min ne staje u $range.');
    }
  }
  if (exceeds.isNotEmpty) return TimeCheck(TimeFit.exceeds, exceeds);
  if (unknown.isNotEmpty) return TimeCheck(TimeFit.unknown, unknown);
  return const TimeCheck(TimeFit.fits, []);
}

/// Ograničenje za dan u nedelji iz spiska (ili null).
DayBudget? budgetFor(List<DayBudget> budgets, int weekday) {
  for (final b in budgets) {
    if (b.weekday == weekday) return b;
  }
  return null;
}
