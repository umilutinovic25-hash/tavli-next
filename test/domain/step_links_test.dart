import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/domain/step_links.dart';

const brasno = Ingredient(id: 'i-b', name: 'brašno', quantity: 500, unit: 'g');
const jaja = Ingredient(id: 'i-j', name: 'jaja', quantity: 3);
const steps = ['Prosejati brašno.', 'Umutiti jaja.', 'Dodati ostatak brašna.'];

Recipe recipe({
  List<Ingredient> ingredients = const [brasno, jaja],
  List<String> steps = steps,
  List<List<StepUse>> uses = const [
    [StepUse(ingredientId: 'i-b', quantity: 300, unit: 'g')],
    [StepUse(ingredientId: 'i-j')],
    [StepUse(ingredientId: 'i-b', quantity: 200)],
  ],
}) => Recipe(
  id: 'r1',
  title: 'Testo',
  servings: 4,
  ingredients: ingredients,
  steps: steps,
  stepUses: uses,
  source: RecipeSource.manual,
  createdAt: DateTime.utc(2026),
);

Recipe roundTrip(Recipe r) =>
    Recipe.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);

void main() {
  group('količine', () {
    test('500 g podeljeno 300 + 200 g: obe upotrebe, bez sukoba', () {
      final r = recipe();
      expect(r.usesFor(0).single.quantity, 300);
      expect(r.usesFor(2).single.quantity, 200);
      expect(useConflicts(r.ingredients, r.stepUses), isEmpty);
    });

    test('600 g ukupno je sukob; recept se ne menja', () {
      final r = recipe(
        uses: const [
          [StepUse(ingredientId: 'i-b', quantity: 300, unit: 'g')],
          [],
          [StepUse(ingredientId: 'i-b', quantity: 300, unit: 'G')],
        ],
      );
      final conflicts = useConflicts(r.ingredients, r.stepUses);
      expect(conflicts.single.ingredient.name, 'brašno');
      expect(conflicts.single.usedQuantity, 600);
      expect(r.ingredients.first.quantity, 500);
    });

    test('druga jedinica i upotreba bez količine se ne sabiraju', () {
      final r = recipe(
        uses: const [
          [StepUse(ingredientId: 'i-b', quantity: 2, unit: 'šolje')],
          [StepUse(ingredientId: 'i-b')],
          [StepUse(ingredientId: 'i-b', quantity: 400)],
        ],
      );
      expect(useConflicts(r.ingredients, r.stepUses), isEmpty);
    });
  });

  group('veze po id-ju', () {
    test('premeštanje sastojaka i koraka čuva veze', () {
      final r = recipe();
      final moved = r.copyWith(
        ingredients: [jaja, brasno],
        steps: [steps[2], steps[0], steps[1]],
      );
      expect(moved.usesFor(0).single.quantity, 200);
      expect(moved.usesFor(1).single.quantity, 300);
      expect(moved.usesFor(2).single.ingredientId, 'i-j');
      expect(useConflicts(moved.ingredients, moved.stepUses), isEmpty);
    });

    test('uklonjen sastojak ostavlja vidljivu nerazrešenu vezu', () {
      final r = recipe().copyWith(ingredients: [brasno]);
      expect(isUnresolved(r.usesFor(1).single, r.ingredients), isTrue);
      expect(isUnresolved(r.usesFor(0).single, r.ingredients), isFalse);
    });

    test('izmenjen tekst koraka gubi samo svoju vezu; ponovljen tekst '
        'redom', () {
      final dup = recipe(
        steps: const ['Promešati.', 'Umutiti jaja.', 'Promešati.'],
        uses: const [
          [StepUse(ingredientId: 'i-b', quantity: 100)],
          [StepUse(ingredientId: 'i-j')],
          [StepUse(ingredientId: 'i-b', quantity: 400)],
        ],
      );
      final edited = dup.copyWith(
        steps: const ['Promešati.', 'Umutiti 3 jaja.', 'Promešati.'],
      );
      expect(edited.usesFor(0).single.quantity, 100);
      expect(edited.usesFor(1), isEmpty);
      expect(edited.usesFor(2).single.quantity, 400);
    });

    test('AI izmena preuzima id-jeve po nazivu; veze ne prelaze na '
        'drugi sastojak', () {
      final next = carryIngredientIds(
        const [brasno, jaja],
        const [
          Ingredient(name: 'jaja', quantity: 4),
          Ingredient(name: 'mleko', quantity: 1, unit: 'l'),
          Ingredient(name: 'Brasno', quantity: 600, unit: 'g'),
        ],
      );
      expect(next.map((i) => i.id), ['i-j', null, 'i-b']);
    });

    test('id se dodeljuje samo sastojku bez id-ja', () {
      var n = 0;
      final items = withIngredientIds(const [
        brasno,
        Ingredient(name: 'so'),
      ], () => 'novi-${++n}');
      expect(items.map((i) => i.id), ['i-b', 'novi-1']);
    });
  });

  group('zapisi', () {
    test('recept v1 ostaje isti: isti tekst, količine i JSON bez novih '
        'ključeva', () {
      final v1 = {
        'id': 'r1',
        'title': 'Testo',
        'servings': 4,
        'prepMinutes': null,
        'ingredients': [
          {
            'name': 'brašno',
            'quantity': 500.0,
            'unit': 'g',
            'category': 'ostalo',
            'note': null,
          },
        ],
        'steps': ['Prosejati brašno.'],
        'source': 'manual',
        'imagePath': null,
        'answeredBy': null,
        'createdAt': '2026-01-01T00:00:00.000Z',
      };
      final r = Recipe.fromJson(v1);
      expect(r.steps, ['Prosejati brašno.']);
      expect(r.ingredients.single.quantity, 500);
      expect(r.ingredients.single.id, isNull);
      expect(r.usesFor(0), isEmpty);
      expect(r.toJson(), v1);
    });

    test('recept sa vezama: Recipe.toJson/fromJson bez gubitka', () {
      final back = roundTrip(recipe());
      expect(back.ingredients.map((i) => i.id), ['i-b', 'i-j']);
      expect(back.stepUses, recipe().stepUses);
    });

    test('snimak plana čuva veze', () {
      final snap = RecipeSnapshot.fromRecipe(recipe());
      final back = RecipeSnapshot.fromJson(
        jsonDecode(jsonEncode(snap.toJson())) as Map<String, dynamic>,
      );
      expect(back.stepUses, recipe().stepUses);
      expect(back.ingredients.first.id, 'i-b');
      expect(back.withIngredients(const [jaja]).stepUses, recipe().stepUses);
    });

    test('starija verzija koja prepiše korake i sastojke bez id-ja: veze '
        'se ne prebacuju, nerazrešene su vidljive', () {
      final links = writeStepLinks(steps, recipe().stepUses);
      // Stariji klijent: drugačiji redosled koraka, sastojci bez id-ja.
      final oldSteps = [steps[1], 'Nov korak.', steps[0]];
      final uses = readStepLinks(oldSteps, links);
      expect(uses[0].single.ingredientId, 'i-j');
      expect(uses[1], isEmpty);
      expect(uses[2].single.quantity, 300);
      const stripped = [
        Ingredient(name: 'brašno', quantity: 500, unit: 'g'),
        Ingredient(name: 'jaja', quantity: 3),
      ];
      expect(isUnresolved(uses[0].single, stripped), isTrue);
    });

    test('pokvaren zapis veza se zanemaruje', () {
      expect(readStepLinks(steps, 'nije lista'), everyElement(isEmpty));
      expect(
        readStepLinks(steps, [
          {
            'text': steps[0],
            'uses': [
              {'quantity': 2},
              'x',
            ],
          },
        ]),
        everyElement(isEmpty),
      );
      expect(writeStepLinks(steps, const []), isNull);
    });
  });
}
