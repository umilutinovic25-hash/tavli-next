import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/recipe_labels.dart';
import 'package:tavli/domain/recipe_search.dart';

Recipe recipe(
  String title, {
  int? minutes,
  Set<MealSuitability> meals = const {},
  DishWeight? weight,
  DishKind? kind,
}) => Recipe(
  id: title,
  title: title,
  servings: 2,
  prepMinutes: minutes,
  ingredients: const [],
  source: RecipeSource.manual,
  createdAt: DateTime(2026),
  labels: RecipeLabels.byUser(meals: meals, weight: weight, dishKind: kind),
);

List<String> titles(List<Recipe> rs) => [for (final r in rs) r.title];

void main() {
  final supa = recipe(
    'Pileća supa',
    minutes: 40,
    meals: {MealSuitability.lunch, MealSuitability.dinner},
    weight: DishWeight.light,
    kind: DishKind.soup,
  );
  final cevapi = recipe(
    'Ćevapi',
    minutes: 25,
    meals: {MealSuitability.lunch},
    weight: DishWeight.hearty,
    kind: DishKind.bakedFried,
  );
  final salata = recipe(
    'Piletina salata',
    minutes: 15,
    meals: {MealSuitability.dinner},
    weight: DishWeight.light,
    kind: DishKind.salad,
  );
  final bezOznaka = recipe('Đuveč');
  final all = [supa, cevapi, salata, bezOznaka];

  group('naziv', () {
    test('deo reči, bez kvačica i velikih slova', () {
      expect(titles(searchRecipes(all, const RecipeFilter(query: 'cevapi'))), [
        'Ćevapi',
      ]);
      expect(titles(searchRecipes(all, const RecipeFilter(query: 'SUPA'))), [
        'Pileća supa',
      ]);
      expect(titles(searchRecipes(all, const RecipeFilter(query: 'djuvec'))), [
        'Đuveč',
      ]);
      expect(titles(searchRecipes(all, const RecipeFilter(query: 'đuveč'))), [
        'Đuveč',
      ]);
    });

    test('prazan upit i bez filtera vraća sve, istim redom', () {
      expect(searchRecipes(all, const RecipeFilter(query: '  ')), all);
      expect(searchRecipes(all, RecipeFilter.none), all);
    });
  });

  group('filteri', () {
    test('obrok, težina, vrsta jela i vreme', () {
      expect(
        titles(
          searchRecipes(all, const RecipeFilter(meal: MealSuitability.dinner)),
        ),
        ['Pileća supa', 'Piletina salata'],
      );
      expect(
        titles(
          searchRecipes(all, const RecipeFilter(weight: DishWeight.hearty)),
        ),
        ['Ćevapi'],
      );
      expect(
        titles(searchRecipes(all, const RecipeFilter(dishKind: DishKind.soup))),
        ['Pileća supa'],
      );
      expect(
        titles(searchRecipes(all, const RecipeFilter(maxPrepMinutes: 30))),
        ['Ćevapi', 'Piletina salata'],
      );
    });

    test('svi uslovi zajedno: „pile, do 30 minuta, za večeru“', () {
      final r = searchRecipes(
        all,
        const RecipeFilter(
          query: 'pile',
          maxPrepMinutes: 30,
          meal: MealSuitability.dinner,
        ),
      );
      expect(titles(r), ['Piletina salata']);
    });

    test('„Do 15 min“ uključuje tačno 15, ne i 16 minuta', () {
      final r = searchRecipes([
        recipe('Tačno 15', minutes: 15),
        recipe('Šesnaest', minutes: 16),
      ], const RecipeFilter(maxPrepMinutes: 15));
      expect(titles(r), ['Tačno 15']);
    });

    test('recept bez oznake ili vremena ne prolazi uključen filter', () {
      for (final f in const [
        RecipeFilter(meal: MealSuitability.lunch),
        RecipeFilter(weight: DishWeight.light),
        RecipeFilter(dishKind: DishKind.cooked),
        RecipeFilter(maxPrepMinutes: 60),
      ]) {
        expect(searchRecipes(all, f), isNot(contains(bezOznaka)));
      }
    });

    test('nepoznata oznaka sa servera se ne poklapa ni sa čim', () {
      final strana = recipe('Strano').copyWith(
        labels: const RecipeLabels(weight: 'ogromno', source: 'user'),
      );
      expect(
        searchRecipes([strana], const RecipeFilter(weight: DishWeight.hearty)),
        isEmpty,
      );
    });
  });

  group('filter', () {
    test('broji uključene filtere i čisti ih bez naziva', () {
      const f = RecipeFilter(
        query: 'sarma',
        meal: MealSuitability.lunch,
        maxPrepMinutes: 30,
      );
      expect(f.activeFilters, 2);
      expect(f.cleared(), const RecipeFilter(query: 'sarma'));
      expect(f.cleared().hasFilters, isFalse);
    });

    test('copyWith može da isključi filter', () {
      const f = RecipeFilter(weight: DishWeight.light);
      expect(f.copyWith(weight: () => null).weight, isNull);
      expect(f.copyWith(query: 'x').weight, DishWeight.light);
    });
  });

  test('500 recepata za manje od 300 ms', () {
    final many = [
      for (var i = 0; i < 500; i++)
        recipe(
          'Recept $i ${i.isEven ? 'pileći' : 'goveđi'}',
          minutes: 10 + i % 90,
          meals: {MealSuitability.values[i % 4]},
          weight: DishWeight.values[i % 3],
          kind: DishKind.values[i % 9],
        ),
    ];
    const filter = RecipeFilter(
      query: 'pileci',
      meal: MealSuitability.lunch,
      maxPrepMinutes: 60,
      weight: DishWeight.light,
    );
    final watch = Stopwatch()..start();
    final result = searchRecipes(many, filter);
    watch.stop();
    expect(result, isNotEmpty);
    expect(watch.elapsedMilliseconds, lessThan(300));
  });

  group('semantička pretraga', () {
    test('rangira po sličnosti i čuva redosled kod izjednačenja', () {
      final result = searchSemantically(
        [supa, cevapi, salata],
        const RecipeFilter(),
        [1, 0],
        {
          supa.id: [0.8, 0.6],
          cevapi.id: [0, 1],
          salata.id: [0.8, 0.6],
        },
      );
      expect(titles(result), ['Pileća supa', 'Piletina salata', 'Ćevapi']);
    });

    test(
      'primenjuje filtere pre rangiranja i preskače nedostajuće vektore',
      () {
        final result = searchSemantically(
          [supa, cevapi, salata],
          const RecipeFilter(maxPrepMinutes: 30),
          [1, 0],
          {
            supa.id: [1, 0],
            cevapi.id: [0.4, 0.6],
          },
        );
        expect(titles(result), ['Ćevapi']);
      },
    );

    test('ne poredi nulte ili vektore različite dužine', () {
      expect(cosineSimilarity([0, 0], [1, 0]), isNull);
      expect(cosineSimilarity([1], [1, 0]), isNull);
    });
  });
}
