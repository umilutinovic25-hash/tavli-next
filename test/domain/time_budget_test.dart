import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/time_budget.dart';

const tuesday = DayBudget(weekday: 2, maxActiveMinutes: 20);
const sunday = DayBudget(weekday: 7, maxActiveMinutes: 90);

void main() {
  test('utorak 20 min: 15 aktivno / 60 ukupno staje, 25 / 30 ne staje', () {
    expect(
      checkTime(budget: tuesday, activeMinutes: 15, totalMinutes: 60)!.fit,
      TimeFit.fits,
    );
    final over = checkTime(
      budget: tuesday,
      activeMinutes: 25,
      totalMinutes: 30,
    )!;
    expect(over.fit, TimeFit.exceeds);
    expect(over.reasons, ['Aktivno 25 min, limit 20 min.']);
  });

  test('granica 20 / 21 minut', () {
    expect(checkTime(budget: tuesday, activeMinutes: 20)!.fit, TimeFit.fits);
    expect(checkTime(budget: tuesday, activeMinutes: 21)!.fit, TimeFit.exceeds);
  });

  test('prozor 18:00–18:45: 60 ukupno ne staje iako aktivni rad prolazi', () {
    const withWindow = DayBudget(
      weekday: 2,
      maxActiveMinutes: 20,
      windowStart: 18 * 60,
      windowEnd: 18 * 60 + 45,
    );
    final check = checkTime(
      budget: withWindow,
      activeMinutes: 15,
      totalMinutes: 60,
    )!;
    expect(check.fit, TimeFit.exceeds);
    expect(check.reasons, ['Ukupno 60 min ne staje u 18:00–18:45.']);
    expect(
      checkTime(budget: withWindow, activeMinutes: 15, totalMinutes: 45)!.fit,
      TimeFit.fits,
    );
  });

  test('nepotvrđeno vreme je nepoznato, ne "staje"; staro vreme pripreme se '
      'ne računa', () {
    // Recept sa samo prepMinutes = 15 nema potvrđeno aktivno vreme.
    final check = checkTime(budget: tuesday)!;
    expect(check.fit, TimeFit.unknown);
    expect(check.reasons, ['Aktivno vreme nije potvrđeno (limit 20 min).']);
  });

  test(
    'prekoračenje je jače od nepoznatog; dan bez ograničenja nema proveru',
    () {
      const both = DayBudget(
        weekday: 2,
        maxActiveMinutes: 20,
        windowStart: 1080,
        windowEnd: 1125,
      );
      expect(checkTime(budget: both, activeMinutes: 30)!.fit, TimeFit.exceeds);
      expect(checkTime(budget: null, activeMinutes: 300), isNull);
      expect(
        checkTime(budget: const DayBudget(weekday: 3), activeMinutes: 300),
        isNull,
      );
    },
  );

  test('nedelja 90 ne menja utorak', () {
    final budgets = [tuesday, sunday];
    expect(budgetFor(budgets, 2), tuesday);
    expect(budgetFor(budgets, 7)!.maxActiveMinutes, 90);
    expect(budgetFor(budgets, 3), isNull);
    expect(
      checkTime(budget: budgetFor(budgets, 2), activeMinutes: 60)!.fit,
      TimeFit.exceeds,
    );
    expect(
      checkTime(budget: budgetFor(budgets, 7), activeMinutes: 60)!.fit,
      TimeFit.fits,
    );
  });

  test('provera unosa: nula, negativno, aktivno duže od ukupnog, prozor', () {
    expect(() => validateTiming(activeMinutes: 0), throwsArgumentError);
    expect(() => validateTiming(totalMinutes: -5), throwsArgumentError);
    expect(
      () => validateTiming(activeMinutes: 40, totalMinutes: 30),
      throwsArgumentError,
    );
    validateTiming(activeMinutes: 30, totalMinutes: 30);
    expect(
      () => validBudget(const DayBudget(weekday: 1, maxActiveMinutes: 0)),
      throwsArgumentError,
    );
    expect(
      () => validBudget(
        const DayBudget(weekday: 1, windowStart: 1125, windowEnd: 1080),
      ),
      throwsArgumentError,
    );
    expect(
      () => validBudget(const DayBudget(weekday: 1, windowStart: 1080)),
      throwsArgumentError,
    );
  });

  test('sat: zapis i čitanje', () {
    expect(clockLabel(1080), '18:00');
    expect(clockLabel(545), '09:05');
    expect(parseClock('18:45'), 1125);
    expect(parseClock('7'), 420);
    expect(parseClock('25:00'), isNull);
    expect(parseClock('18:60'), isNull);
    expect(parseClock('nije'), isNull);
  });
}
