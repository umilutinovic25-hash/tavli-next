import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/recipe.dart';

Recipe parse(Map<String, dynamic> json) => Recipe.fromAiJson(
  json,
  id: 'r1',
  source: RecipeSource.ai,
  createdAt: DateTime(2026),
);

void main() {
  test('čita kompletan recept', () {
    final r = parse({
      'title': 'Sarma',
      'servings': 6,
      'prepMinutes': 180,
      'ingredients': [
        {
          'name': 'kiseli kupus',
          'quantity': 1,
          'unit': 'glavica',
          'category': 'konzerve i tegle',
        },
        {
          'name': 'mleveno meso',
          'quantity': '0,5',
          'unit': 'kg',
          'category': 'meso i riba',
        },
        {
          'name': 'biber',
          'quantity': null,
          'unit': '',
          'category': 'začini i sosovi',
          'note': 'po ukusu',
        },
      ],
      'steps': ['Umotati sarme.', ' ', 'Kuvati 3 sata.'],
    });

    expect(r.title, 'Sarma');
    expect(r.servings, 6);
    expect(r.ingredients[1].quantity, 0.5);
    expect(r.ingredients[2].unit, isNull);
    expect(r.steps, ['Umotati sarme.', 'Kuvati 3 sata.']);
    expect(r.detailLevel, DetailLevel.full);
  });

  test('razlomak i nepoznata kategorija', () {
    final r = parse({
      'title': 'Palačinke',
      'ingredients': [
        {
          'name': 'šećer',
          'quantity': '1/2',
          'unit': 'šolja',
          'category': 'slatkiši',
        },
      ],
    });

    expect(r.ingredients.single.quantity, 0.5);
    expect(r.ingredients.single.category, 'ostalo');
    expect(r.servings, 2);
    expect(r.detailLevel, DetailLevel.summary);
  });

  test('recept bez naziva ili sastojaka je FormatException', () {
    expect(
      () => parse({
        'title': '',
        'ingredients': [
          {'name': 'x'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => parse({'title': 'X', 'ingredients': <Object>[]}),
      throwsFormatException,
    );
    expect(
      () => parse({
        'title': 'X',
        'ingredients': [
          {'name': ' '},
        ],
      }),
      throwsFormatException,
    );
  });

  test('toAiJson -> fromAiJson zadržava sadržaj', () {
    final r = parse({
      'title': 'Pasulj',
      'servings': 4,
      'ingredients': [
        {
          'name': 'pasulj',
          'quantity': 500,
          'unit': 'g',
          'category': 'suvi proizvodi',
        },
      ],
      'steps': ['Potopiti preko noći.'],
    });

    final copy = parse(r.toAiJson());
    expect(copy.toAiJson(), r.toAiJson());
  });

  group('čuvanje', () {
    final original = Recipe(
      id: 'r1',
      title: 'Sarma',
      servings: 6,
      prepMinutes: 180,
      ingredients: const [
        Ingredient(
          name: 'kupus',
          quantity: 1,
          unit: 'glavica',
          category: 'konzerve i tegle',
          note: 'kiseli',
        ),
      ],
      steps: const ['Umotati.'],
      source: RecipeSource.photo,
      imagePath: 'recipe_photos/r1.jpg',
      answeredBy: 'Gemini Pro',
      createdAt: DateTime.utc(2026, 10, 30, 12),
    );

    test('toJson/fromJson vraća isti recept', () {
      final copy = Recipe.fromJson(original.toJson());
      expect(copy.toJson(), original.toJson());
      expect(copy.createdAt.isAtSameMomentAs(original.createdAt), isTrue);
      expect(copy.source, RecipeSource.photo);
    });

    test('fromJson bez naziva baca FormatException', () {
      final json = original.toJson()..['title'] = '';
      expect(() => Recipe.fromJson(json), throwsFormatException);
    });

    test('copyWith menja samo zadata polja', () {
      final c = original.copyWith(title: 'Posna sarma');
      expect(c.title, 'Posna sarma');
      expect(c.imagePath, 'recipe_photos/r1.jpg');
      expect(c.servings, 6);
      expect(original.copyWith(clearPrepMinutes: true).prepMinutes, isNull);
    });
  });

  group('foodId (036)', () {
    test('fromJson čita foodId, prazan je null', () {
      final i = Ingredient.fromJson({'name': 'jaja', 'foodId': 'f_jaje'});
      expect(i.foodId, 'f_jaje');
      expect(
        Ingredient.fromJson({'name': 'jaja', 'foodId': ' '}).foodId,
        isNull,
      );
      expect(Ingredient.fromJson({'name': 'jaja'}).foodId, isNull);
    });

    test('toJson bez foodId je isti kao pre kataloga', () {
      const i = Ingredient(name: 'jaja', quantity: 3, unit: 'kom', id: 'i1');
      expect(i.toJson(), {
        'name': 'jaja',
        'quantity': 3.0,
        'unit': 'kom',
        'category': 'ostalo',
        'note': null,
        'id': 'i1',
      });
      expect(i.toJson().containsKey('foodId'), isFalse);
    });

    test('withFood čuva tekst, id i količinu; withId čuva foodId', () {
      const i = Ingredient(name: 'Jajce', quantity: 2, unit: 'kom', id: 'i1');
      final f = i.withFood('f_jaje');
      expect(f.foodId, 'f_jaje');
      expect(f.name, 'Jajce');
      expect(f.id, 'i1');
      expect(f.quantity, 2);
      expect(f.toJson()['foodId'], 'f_jaje');
      expect(f.withId('i2').foodId, 'f_jaje');
      expect(f.withFood(null).foodId, isNull);
      expect(Ingredient.fromJson(f.toJson()).foodId, 'f_jaje');
    });
  });
}
