import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/ai/meal_plan_ai.dart';
import 'package:tavli/domain/allergy.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/features/planning/meal_actions.dart';
import 'package:tavli/features/settings/ai_error_text.dart';

void main() {
  const message =
      'Nije pronađen recept bez alergena članova domaćinstva (kikiriki). '
      'Promeni zahtev i pokušaj ponovo.';

  test('AllergenViolation ima jasnu poruku, ne „Nešto nije u redu“', () {
    expect(aiErrorText(const AllergenViolation(['kikiriki'])), message);
  });

  test('plan: ista poruka kad generisanje stane zbog alergena', () {
    final day = CivilDate(2026, 11, 16);
    final draft = PlanDraft(
      request: PlanRequest(
        range: DateRange(day, day),
        mealTypes: const {MealType.lunch},
      ),
    );
    expect(
      mealErrorText(
        PlanGenerationFailed(draft, const AllergenViolation(['kikiriki'])),
      ),
      message,
    );
  });
}
