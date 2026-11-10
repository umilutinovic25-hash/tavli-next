import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/ai/ai_models.dart';
import 'package:tavli/ai/ai_router.dart';
import 'package:tavli/ai/chain_config.dart';
import 'package:tavli/ai/chat_client.dart';
import 'package:tavli/ai/key_store.dart';
import 'package:tavli/ai/meal_plan_ai.dart';
import 'package:tavli/ai/meal_plan_prompts.dart';
import 'package:tavli/ai/model_status_store.dart';
import 'package:tavli/ai/prompts.dart';
import 'package:tavli/ai/recipe_ai.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/domain/user_preferences.dart';

const _model = ModelSpec(
  provider: AIProvider.gemini,
  model: 'flash',
  label: 'Gemini Flash',
);

final _allergic = UserPreferences(
  allergies: const ['Orasi', 'susam'],
  diet: const [FoodDiet.vegan],
  dislikes: const ['pasulj'],
  servings: 4,
);

/// Beleži zahteve i odgovara JSON-om koji zavisi od upita.
class _Client implements ChatClient {
  _Client(this.answer);

  final String Function(AIRequest) answer;
  final prompts = <String>[];

  @override
  Future<String> complete(
    ModelSpec model,
    AIRequest request, {
    required String apiKey,
  }) async {
    prompts.add(request.prompt);
    return answer(request);
  }
}

AIRouter _router(ChatClient client) => AIRouter(
  config: () => const ChainConfig(vision: [_model], text: [_model]),
  client: client,
  keys: LayeredKeySource(
    InMemoryKeyStore({AIProvider.gemini: 'g-key'}),
    const BuiltInKeys(),
  ),
  status: InMemoryModelStatusStore(),
  clock: () => DateTime.utc(2026, 11, 10, 12),
);

String _recipeAnswer(AIRequest r) => jsonEncode({
  'title': 'Sarma',
  'servings': 4,
  'prepMinutes': 30,
  'ingredients': [
    {'name': 'kupus', 'quantity': 1, 'unit': 'kg', 'category': 'voće i povrće'},
  ],
  'steps': ['Kuvati.'],
});

/// Predlog za svako mesto i sažetak za svaki recept iz upita.
String _planAnswer(AIRequest r) {
  if (r.prompt.contains('\nSlots: ')) {
    final slots = RegExp(
      r'^Slots: (.*)$',
      multiLine: true,
    ).firstMatch(r.prompt)![1]!;
    return jsonEncode({
      'meals': [
        for (final s in jsonDecode(slots) as List<dynamic>)
          {
            'date': (s as Map<String, dynamic>)['date'],
            'meal': s['meal'],
            'recipeId': null,
            'title': 'Jelo ${s['date']}',
          },
      ],
    });
  }
  final titles = RegExp(
    r'^Recipes: (.*)$',
    multiLine: true,
  ).firstMatch(r.prompt)![1]!;
  return jsonEncode({
    'recipes': [
      for (final t in jsonDecode(titles) as List<dynamic>)
        {
          'title': t,
          'servings': 4,
          'prepMinutes': 20,
          'ingredients': [
            {
              'name': 'krompir',
              'quantity': 1,
              'unit': 'kg',
              'category': 'voće i povrće',
            },
          ],
        },
    ],
  });
}

void main() {
  group('preferencesBlock', () {
    test('bez unosa nema bloka', () {
      expect(preferencesBlock(null), isEmpty);
      expect(preferencesBlock(UserPreferences.defaults), isEmpty);
      expect(
        recipeFromNamePrompt('Sarma', servings: 2),
        recipeFromNamePrompt(
          'Sarma',
          servings: 2,
          preferences: UserPreferences.defaults,
        ),
      );
    });

    test('alergija je prva i zabranjena, sa svim stavkama', () {
      final block = preferencesBlock(_allergic);
      final allergy = block.indexOf('ALLERGIES');
      expect(allergy, greaterThan(-1));
      expect(block, contains('must NOT contain'));
      expect(block, contains('"orasi"'));
      expect(block, contains('"susam"'));
      expect(block, contains('vegan'));
      expect(block, contains('"pasulj"'));
      expect(block, contains('Household size: 4'));
      expect(allergy, lessThan(block.indexOf('Diet:')));
      expect(block.indexOf('Diet:'), lessThan(block.indexOf('Dislikes:')));
    });

    test('blok stoji pre zadatka u upitu za recept', () {
      final prompt = recipeFromNamePrompt(
        'Sarma',
        servings: 4,
        preferences: _allergic,
      );
      expect(prompt, startsWith('Household preferences'));
      expect(prompt, contains('"orasi"'));
      expect(prompt, contains('Create a home-cooking recipe for: "Sarma".'));
    });

    test('upit za sliku i izmenu recepta takođe nose blok', () {
      expect(
        recipeFromImagePrompt(preferences: _allergic),
        contains('"orasi"'),
      );
    });

    test('plan: raspored i sažeci nose alergiju', () {
      final monday = CivilDate(2026, 11, 2);
      final outline = planOutlinePrompt(
        slots: [MealSlot(monday, MealType.lunch)],
        servings: 4,
        library: const [],
        preferences: _allergic,
      );
      expect(outline, contains('"orasi"'));
      expect(outline, contains('\nSlots: '));

      final summaries = recipeSummariesPrompt(const [
        'Sarma',
      ], preferences: _allergic);
      expect(summaries, startsWith('Household preferences'));
      expect(summaries, contains('"susam"'));
    });
  });

  group('AI sa preferencijama', () {
    test('RecipeAI šalje alergije u upitu za recept po nazivu', () async {
      final client = _Client(_recipeAnswer);
      final ai = RecipeAI(_router(client), preferences: () async => _allergic);
      await ai.fromDishName('Sarma', servings: 4);
      expect(client.prompts.single, contains('"orasi"'));
      expect(client.prompts.single, startsWith('Household preferences'));
    });

    test('RecipeAI bez unosa ne dodaje blok', () async {
      final client = _Client(_recipeAnswer);
      final ai = RecipeAI(
        _router(client),
        preferences: () async => UserPreferences.defaults,
      );
      await ai.fromDishName('Sarma');
      expect(client.prompts.single, isNot(contains('Household preferences')));
    });

    test('MealPlanAI šalje alergije u rasporedu i u sažecima', () async {
      final client = _Client(_planAnswer);
      final ai = MealPlanAI(
        _router(client),
        preferences: () async => _allergic,
      );
      final monday = CivilDate(2026, 11, 2);
      await ai.propose(
        PlanRequest(
          range: DateRange(monday, monday.addDays(6)),
          mealTypes: const {MealType.lunch},
          servings: 4,
        ),
      );
      expect(client.prompts, hasLength(greaterThan(1)));
      for (final prompt in client.prompts) {
        expect(prompt, startsWith('Household preferences'));
        expect(prompt, contains('"orasi"'));
      }
    });
  });
}
