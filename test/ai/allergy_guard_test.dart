import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/ai/ai_models.dart';
import 'package:tavli/ai/ai_router.dart';
import 'package:tavli/ai/chain_config.dart';
import 'package:tavli/ai/chat_client.dart';
import 'package:tavli/ai/key_store.dart';
import 'package:tavli/ai/model_status_store.dart';
import 'package:tavli/ai/recipe_ai.dart';
import 'package:tavli/domain/allergy.dart';
import 'package:tavli/domain/food.dart';
import 'package:tavli/domain/recipe.dart';

const _model = ModelSpec(
  provider: AIProvider.gemini,
  model: 'flash',
  label: 'Gemini Flash',
  supportsVision: true,
);

class _Client implements ChatClient {
  _Client(this.answers);

  final List<List<String>> answers;
  final prompts = <String>[];

  @override
  Future<String> complete(
    ModelSpec model,
    AIRequest request, {
    required String apiKey,
  }) async {
    final i = prompts.length;
    prompts.add(request.prompt);
    return _recipe(answers[i < answers.length ? i : answers.length - 1]);
  }
}

String _recipe(List<String> ingredients) => jsonEncode({
  'title': 'Kolač',
  'servings': 4,
  'prepMinutes': 30,
  'ingredients': [
    for (final n in ingredients)
      {'name': n, 'quantity': 1, 'unit': 'kom', 'category': 'ostalo'},
  ],
  'steps': ['Umesiti.'],
});

final _catalog = FoodCatalog(
  foods: const [
    Food(
      id: 'f_kik',
      name: 'kikiriki',
      category: 'ostalo',
      baseUnit: BaseUnit.g,
    ),
    Food(
      id: 'f_jaje',
      name: 'jaje',
      category: 'ostalo',
      baseUnit: BaseUnit.kom,
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
    FoodAlias(foodId: 'f_jaje', alias: 'jaja'),
    FoodAlias(foodId: 'f_bras', alias: 'brašno'),
  ],
  allergens: const [
    (foodId: 'f_kik', code: 'peanuts'),
    (foodId: 'f_jaje', code: 'eggs'),
  ],
);

(RecipeAI, _Client) _ai(
  List<List<String>> answers, {
  Set<String> codes = const {'peanuts', 'eggs'},
  List<String> custom = const ['jagode'],
  List<String> legacy = const [],
}) {
  final client = _Client(answers);
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
    PersonAllergies(householdId: 'h1', userId: 'u1', codes: codes),
    PersonAllergies(householdId: 'h1', userId: 'u2', custom: custom),
  ], legacy: legacy);
  return (
    RecipeAI(
      router,
      allergyContext: () async => (catalog: _catalog, allergies: allergies),
    ),
    client,
  );
}

void main() {
  test(
    'kasna legacy alergija se proverava i kad AI zanemari uputstvo',
    () async {
      final (ai, client) = _ai(
        [
          ['kikiriki'],
        ],
        codes: const {},
        custom: const [],
        legacy: const ['kikiriki'],
      );
      await expectLater(
        ai.fromDishName('Kolač'),
        throwsA(isA<AllergenViolation>()),
      );
      expect(client.prompts, hasLength(2));
    },
  );
  test('upit po nazivu nosi uniju alergija svih članova', () async {
    final (ai, client) = _ai([
      ['brašno'],
    ]);
    await ai.fromDishName('Kolač');
    expect(client.prompts.single, contains('peanuts'));
    expect(client.prompts.single, contains('eggs'));
    expect(client.prompts.single, contains('jagode'));
  });

  test(
    'po nazivu: alergen → jedan ponovni zahtev sa spiskom, čist recept prolazi',
    () async {
      final (ai, client) = _ai([
        ['brašno', 'kikiriki'],
        ['brašno'],
      ]);
      final r = await ai.fromDishName('Kolač');
      expect(r.value.ingredients.map((i) => i.name), ['brašno']);
      expect(client.prompts, hasLength(2));
      expect(client.prompts.first, isNot(contains('previous recipe')));
      expect(client.prompts.last, contains('previous recipe'));
      expect(client.prompts.last, contains('kikiriki'));
    },
  );

  test(
    'po nazivu: alergen i posle ponovnog zahteva → AllergenViolation',
    () async {
      final (ai, client) = _ai([
        ['jaja', 'kikiriki'],
      ]);
      await expectLater(
        ai.fromDishName('Kolač'),
        throwsA(
          isA<AllergenViolation>().having((e) => e.allergens, 'alergeni', [
            'jaja',
            'kikiriki',
          ]),
        ),
      );
      expect(client.prompts, hasLength(2));
    },
  );

  test('slobodan unos se proverava po nazivu sastojka', () async {
    final (ai, client) = _ai([
      ['sveže jagode'],
      ['brašno'],
    ]);
    await ai.fromDishName('Kolač');
    expect(client.prompts, hasLength(2));
  });

  test('nepotvrđen sastojak se prihvata bez ponovnog zahteva', () async {
    final (ai, client) = _ai([
      ['pesto đenoveze'],
    ]);
    final r = await ai.fromDishName('Pasta');
    expect(r.value.ingredients.single.name, 'pesto đenoveze');
    expect(client.prompts, hasLength(1));
  });

  test('bez alergija u domaćinstvu nema provere', () async {
    final (ai, client) = _ai(
      [
        ['kikiriki'],
      ],
      codes: const {},
      custom: const [],
    );
    await ai.fromDishName('Kolač');
    expect(client.prompts, hasLength(1));
  });

  Recipe current(List<String> names) => Recipe(
    id: 'r1',
    title: 'Kolač',
    servings: 4,
    ingredients: [for (final n in names) Ingredient(name: n)],
    steps: const ['Umesiti.'],
    source: RecipeSource.photo,
    createdAt: DateTime.utc(2026),
  );

  test('izmena: alergen koji je već bio u receptu ne odbija izmenu', () async {
    final (ai, client) = _ai([
      ['brašno', 'kikiriki', 'so'],
    ]);
    final r = await ai.refine(current(['brašno', 'kikiriki']), 'dodaj so');
    expect(r.value.ingredients, hasLength(3));
    expect(client.prompts, hasLength(1));
  });

  test('izmena: nov alergen → ponovni zahtev, pa greška', () async {
    final (ai, client) = _ai([
      ['brašno', 'jaja'],
    ]);
    await expectLater(
      ai.refine(current(['brašno']), 'dodaj jaja'),
      throwsA(isA<AllergenViolation>()),
    );
    expect(client.prompts, hasLength(2));
  });

  test(
    'fotografija se ne odbija ni ne ponavlja (upozorenje je u pregledu)',
    () async {
      final (ai, client) = _ai([
        ['kikiriki'],
      ]);
      final r = await ai.fromImage(
        AIImage(Uint8List.fromList(const [1, 2, 3])),
      );
      expect(r.value.ingredients.single.name, 'kikiriki');
      expect(client.prompts, hasLength(1));
    },
  );
}
