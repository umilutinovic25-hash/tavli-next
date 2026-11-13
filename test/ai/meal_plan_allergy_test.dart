import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/ai/ai_models.dart';
import 'package:tavli/ai/ai_router.dart';
import 'package:tavli/ai/chain_config.dart';
import 'package:tavli/ai/chat_client.dart';
import 'package:tavli/ai/key_store.dart';
import 'package:tavli/ai/meal_plan_ai.dart';
import 'package:tavli/ai/model_status_store.dart';
import 'package:tavli/domain/allergy.dart';
import 'package:tavli/domain/food.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/domain/recipe.dart';

const _model = ModelSpec(
  provider: AIProvider.gemini,
  model: 'flash',
  label: 'Gemini Flash',
);

/// Raspored: novo jelo „Jelo“ za svako mesto. Sažeci: sastojci iz
/// [summaries] redom poziva (poslednji se ponavlja).
class _Client implements ChatClient {
  _Client(this.summaries);

  final List<List<String>> summaries;
  final prompts = <String>[];
  var _summaryCalls = 0;

  List<String> get outlinePrompts => [
    for (final p in prompts)
      if (p.contains('\nSlots: ')) p,
  ];

  List<String> get summaryPrompts => [
    for (final p in prompts)
      if (p.contains('\nRecipes: ')) p,
  ];

  @override
  Future<String> complete(
    ModelSpec model,
    AIRequest request, {
    required String apiKey,
  }) async {
    final prompt = request.prompt;
    prompts.add(prompt);
    if (prompt.contains('\nSlots: ')) {
      final slots = RegExp(
        r'^Slots: (.*)$',
        multiLine: true,
      ).firstMatch(prompt)![1]!;
      return jsonEncode({
        'meals': [
          for (final s in jsonDecode(slots) as List<dynamic>)
            {
              'date': (s as Map<String, dynamic>)['date'],
              'meal': s['meal'],
              'recipeId': null,
              'title': 'Jelo',
            },
        ],
      });
    }
    final i = _summaryCalls++;
    final names = summaries[i < summaries.length ? i : summaries.length - 1];
    return jsonEncode({
      'recipes': [
        {
          'title': 'Jelo',
          'servings': 2,
          'prepMinutes': 20,
          'ingredients': [
            for (final n in names)
              {'name': n, 'quantity': 1, 'unit': 'kom', 'category': 'ostalo'},
          ],
        },
      ],
    });
  }
}

final _catalog = FoodCatalog(
  foods: const [
    Food(
      id: 'f_kik',
      name: 'kikiriki',
      category: 'ostalo',
      baseUnit: BaseUnit.g,
    ),
    Food(
      id: 'f_bras',
      name: 'brašno',
      category: 'ostalo',
      baseUnit: BaseUnit.g,
    ),
  ],
  aliases: const [
    FoodAlias(foodId: 'f_kik', alias: 'kikiriki'),
    FoodAlias(foodId: 'f_bras', alias: 'brašno'),
  ],
  allergens: const [(foodId: 'f_kik', code: 'peanuts')],
);

final _day = CivilDate(2026, 11, 16);
final _request = PlanRequest(
  range: DateRange(_day, _day),
  mealTypes: const {MealType.lunch},
);

(MealPlanAI, _Client) _ai(List<List<String>> summaries) {
  final client = _Client(summaries);
  final router = AIRouter(
    config: () => const ChainConfig(vision: [_model], text: [_model]),
    client: client,
    keys: LayeredKeySource(
      InMemoryKeyStore({AIProvider.gemini: 'g-key'}),
      const BuiltInKeys(),
    ),
    status: InMemoryModelStatusStore(),
    clock: () => DateTime.utc(2026, 11, 12, 12),
  );
  final allergies = HouseholdAllergies.union([
    PersonAllergies(householdId: 'h1', userId: 'u1', codes: {'peanuts'}),
  ]);
  return (
    MealPlanAI(
      router,
      allergyContext: () async => (catalog: _catalog, allergies: allergies),
    ),
    client,
  );
}

Recipe _lib(String id, List<String> names) => Recipe(
  id: id,
  title: 'Recept $id',
  servings: 2,
  ingredients: [for (final n in names) Ingredient(name: n)],
  source: RecipeSource.manual,
  createdAt: DateTime.utc(2026),
);

void main() {
  test('recept iz biblioteke sa alergenom se ne nudi AI-ju', () async {
    final (ai, client) = _ai([
      ['brašno'],
    ]);
    await ai.propose(
      _request,
      library: [
        _lib('r_kik', ['kikiriki']),
        _lib('r_ok', ['brašno']),
      ],
    );
    final outline = client.outlinePrompts.single;
    expect(outline, contains('r_ok'));
    expect(outline, isNot(contains('r_kik')));
    expect(outline, contains('peanuts'));
  });

  test('novi recept sa alergenom: ponovni zahtev samo za njega', () async {
    final (ai, client) = _ai([
      ['brašno', 'kikiriki'],
      ['brašno'],
    ]);
    final draft = await ai.propose(_request);
    expect(draft.isComplete, isTrue);
    expect(draft.newRecipes.values.single.ingredients.map((i) => i.name), [
      'brašno',
    ]);
    expect(client.summaryPrompts, hasLength(2));
    expect(client.summaryPrompts.last, contains('previous recipe'));
    expect(client.summaryPrompts.last, contains('kikiriki'));
  });

  test(
    'alergen i posle ponovnog zahteva: mesto je prazno, generisanje staje',
    () async {
      final (ai, client) = _ai([
        ['kikiriki'],
      ]);
      await expectLater(
        ai.propose(_request),
        throwsA(
          isA<PlanGenerationFailed>()
              .having((e) => e.error, 'greška', isA<AllergenViolation>())
              .having((e) => e.draft.missingSlots, 'prazna mesta', hasLength(1))
              .having((e) => e.draft.newRecipes, 'novi recepti', isEmpty),
        ),
      );
      expect(client.summaryPrompts, hasLength(2));
    },
  );

  test('nepotvrđen sastojak se prihvata bez ponovnog zahteva', () async {
    final (ai, client) = _ai([
      ['nepoznati začin'],
    ]);
    final draft = await ai.propose(_request);
    expect(draft.isComplete, isTrue);
    expect(client.summaryPrompts, hasLength(1));
  });
}
