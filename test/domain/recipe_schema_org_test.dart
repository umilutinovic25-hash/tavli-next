import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/recipe_schema_org.dart';

final sarma = Recipe(
  id: 'r1',
  title: 'Sarma',
  servings: 6,
  prepMinutes: 90,
  ingredients: const [
    Ingredient(
      name: 'kiseli kupus',
      quantity: 1,
      unit: 'glavica',
      category: 'konzerve i tegle',
    ),
    Ingredient(
      name: 'mleveno meso',
      quantity: 0.5,
      unit: 'kg',
      category: 'meso i riba',
    ),
    Ingredient(name: 'biber', category: 'začini i sosovi', note: 'po ukusu'),
  ],
  steps: const ['Umotati sarme.', 'Kuvati 3 sata.'],
  source: RecipeSource.manual,
  createdAt: DateTime.utc(2026, 3, 7),
);

var _ids = 0;
String nextId() => 'novi-${++_ids}';

SchemaOrgImport parse(Object json, {List<Recipe> existing = const []}) =>
    parseSchemaOrgRecipes(
      jsonEncode(json),
      existing: existing,
      newId: nextId,
      now: DateTime.utc(2026, 11, 10),
    );

void main() {
  setUp(() => _ids = 0);

  group('izvoz', () {
    test('pravi schema.org/Recipe sa čitljivim poljima', () {
      final json = recipeToSchemaOrg(sarma);
      expect(json['@context'], 'https://schema.org');
      expect(json['@type'], 'Recipe');
      expect(json['name'], 'Sarma');
      expect(json['recipeYield'], '6');
      expect(json['totalTime'], 'PT1H30M');
      expect(json['recipeIngredient'], [
        '1 glavica kiseli kupus',
        '0,5 kg mleveno meso',
        'biber (po ukusu)',
      ]);
      expect(json['recipeInstructions'], [
        {'@type': 'HowToStep', 'text': 'Umotati sarme.'},
        {'@type': 'HowToStep', 'text': 'Kuvati 3 sata.'},
      ]);
      expect(json['dateCreated'], '2026-03-07T00:00:00.000Z');
    });

    test('bez vremena nema totalTime', () {
      final json = recipeToSchemaOrg(sarma.copyWith(clearPrepMinutes: true));
      expect(json.containsKey('totalTime'), isFalse);
    });

    test('više recepata ide u niz', () {
      final text = encodeSchemaOrgRecipes([sarma, sarma]);
      expect(jsonDecode(text), hasLength(2));
      expect(
        jsonDecode(encodeSchemaOrgRecipes([sarma])),
        isA<Map<String, dynamic>>(),
      );
    });
  });

  group('povratni uvoz', () {
    test('izvezen recept se vraća bez gubitka', () {
      final result = parseSchemaOrgRecipes(
        encodeSchemaOrgRecipes([sarma]),
        existing: const [],
        newId: nextId,
        now: DateTime.utc(2026, 11, 10),
      );
      expect(result.skipped, isEmpty);
      expect(result.ignoredFields, isEmpty);
      final r = result.recipes.single;
      expect(r.id, 'novi-1');
      expect(r.source, RecipeSource.manual);
      expect(r.title, 'Sarma');
      expect(r.servings, 6);
      expect(r.prepMinutes, 90);
      expect(r.steps, sarma.steps);
      expect(
        [for (final i in r.ingredients) i.toJson()],
        [for (final i in sarma.ingredients) i.toJson()],
      );
    });

    test('ručno izmenjeni sastojci imaju prednost nad Tavli kopijom', () {
      final json = recipeToSchemaOrg(sarma);
      (json['recipeIngredient'] as List).add('2 jaja');
      final r = parse(json).recipes.single;
      expect(r.ingredients.map((i) => i.name), [
        'kiseli kupus',
        'mleveno meso',
        'biber',
        'jaja',
      ]);
      expect(r.ingredients.first.category, 'ostalo');
    });
  });

  group('uvoz iz drugih izvora', () {
    test('tekstualni sastojci, sekcije koraka i vreme pripreme', () {
      final r = parse({
        '@context': 'https://schema.org/',
        '@type': ['Recipe'],
        'name': ' Palačinke ',
        'recipeYield': ['4 porcije', '4'],
        'prepTime': 'PT15M',
        'cookTime': 'PT1H',
        'recipeIngredient': [
          '500 ml mleka',
          '1/2 kg brašna',
          '2 jaja',
          'so (po ukusu)',
          '1,5 kašika ulja',
        ],
        'recipeInstructions': [
          {
            '@type': 'HowToSection',
            'name': 'Testo',
            'itemListElement': [
              {'@type': 'HowToStep', 'text': 'Umutiti jaja i mleko.'},
              {'@type': 'HowToStep', 'text': 'Dodati brašno.'},
            ],
          },
          'Peći na tiganju.',
        ],
      }).recipes.single;
      expect(r.title, 'Palačinke');
      expect(r.servings, 4);
      expect(r.prepMinutes, 75);
      expect(r.steps, [
        'Umutiti jaja i mleko.',
        'Dodati brašno.',
        'Peći na tiganju.',
      ]);
      final ingredients = [
        for (final i in r.ingredients) (i.quantity, i.unit, i.name, i.note),
      ];
      expect(ingredients, [
        (500.0, 'ml', 'mleka', null),
        (0.5, 'kg', 'brašna', null),
        (2.0, null, 'jaja', null),
        (null, null, 'so', 'po ukusu'),
        (1.5, 'kašika', 'ulja', null),
      ]);
    });

    test(
      'totalTime ima prednost; koraci kao jedan tekst se dele po redovima',
      () {
        final r = parse({
          '@type': 'Recipe',
          'name': 'Čaj',
          'recipeYield': 2,
          'totalTime': 'P0DT0H10M',
          'prepTime': 'PT5M',
          'recipeIngredient': ['voda'],
          'recipeInstructions': 'Prokuvati vodu.\n\nDodati čaj.',
        }).recipes.single;
        expect(r.servings, 2);
        expect(r.prepMinutes, 10);
        expect(r.steps, ['Prokuvati vodu.', 'Dodati čaj.']);
      },
    );

    test('pronalazi recepte u @graph i preskače ostale tipove', () {
      final result = parse({
        '@context': 'https://schema.org',
        '@graph': [
          {'@type': 'WebPage', 'name': 'Blog'},
          {
            '@type': 'Recipe',
            'name': 'Pasulj',
            'recipeIngredient': ['pasulj'],
          },
        ],
      });
      expect(result.recipes.single.title, 'Pasulj');
      expect(result.recipes.single.servings, 2);
      expect(result.skipped, isEmpty);
    });

    test('izveštaj: neispravni, duplikati i zanemarena polja', () {
      final result = parse(
        [
          {
            '@type': 'Recipe',
            'name': 'Đuveč',
            'recipeIngredient': ['pirinač'],
            'image': 'https://primer.rs/djuvec.jpg',
            'nutrition': {'calories': '300'},
            'author': {'name': 'Neko'},
          },
          {'@type': 'Recipe', 'name': 'Bez sastojaka'},
          {
            '@type': 'Recipe',
            'recipeIngredient': ['so'],
          },
          {
            '@type': 'Recipe',
            'name': 'sarma',
            'recipeIngredient': ['kupus'],
          },
          {
            '@type': 'Recipe',
            'name': 'Đuveč',
            'recipeIngredient': ['pirinač'],
          },
        ],
        existing: [sarma],
      );
      expect(result.recipes.map((r) => r.title), ['Đuveč']);
      expect(result.skipped.map((s) => (s.title, s.reason)), [
        ('Bez sastojaka', 'nema sastojke'),
        (null, 'nema naziv'),
        ('sarma', 'već postoji u receptima'),
        ('Đuveč', 'ponavlja se u fajlu'),
      ]);
      expect(result.ignoredFields, ['author', 'image', 'nutrition']);
    });

    test('fajl bez recepata i pokvaren JSON', () {
      expect(parse({'@type': 'WebPage'}).recipes, isEmpty);
      expect(
        () => parseSchemaOrgRecipes(
          '{nije json',
          existing: const [],
          newId: nextId,
          now: DateTime.utc(2026),
        ),
        throwsFormatException,
      );
    });
  });
}
