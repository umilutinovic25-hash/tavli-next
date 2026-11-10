import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/ai/ai_errors.dart';
import 'package:tavli/ai/ai_models.dart';
import 'package:tavli/ai/ai_router.dart';
import 'package:tavli/ai/chain_config.dart';
import 'package:tavli/ai/chat_client.dart';
import 'package:tavli/ai/key_store.dart';
import 'package:tavli/ai/meal_plan_ai.dart';
import 'package:tavli/ai/model_status_store.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/time_budget.dart';

const model = ModelSpec(
  provider: AIProvider.gemini,
  model: 'flash',
  label: 'Gemini Flash',
);

/// Odgovara na zahteve preko [handler]-a; beleži svaki zahtev.
class ScriptedClient implements ChatClient {
  ScriptedClient(this.handler);

  String Function(AIRequest request) handler;
  final requests = <AIRequest>[];

  @override
  Future<String> complete(
    ModelSpec model,
    AIRequest request, {
    required String apiKey,
  }) async {
    requests.add(request);
    return handler(request);
  }
}

List<Map<String, dynamic>> slotsIn(AIRequest r) {
  final m = RegExp(r'^Slots: (.*)$', multiLine: true).firstMatch(r.prompt);
  return [
    for (final s in jsonDecode(m![1]!) as List<dynamic>)
      s as Map<String, dynamic>,
  ];
}

List<String> titlesIn(AIRequest r) {
  final m = RegExp(r'^Recipes: (.*)$', multiLine: true).firstMatch(r.prompt);
  return [for (final t in jsonDecode(m![1]!) as List<dynamic>) t as String];
}

bool isOutline(AIRequest r) => r.prompt.contains('\nSlots: ');

Map<String, dynamic> summary(String title, {int servings = 4}) => {
  'title': title,
  'servings': servings,
  'prepMinutes': 30,
  'ingredients': [
    {
      'name': 'crni luk',
      'quantity': 1,
      'unit': 'kom',
      'category': 'voće i povrće',
      'note': null,
    },
  ],
};

/// Svako mesto dobija svoje jelo (`Jelo <datum> <obrok>`).
String goodAnswer(AIRequest r) {
  if (isOutline(r)) {
    return jsonEncode({
      'meals': [
        for (final s in slotsIn(r))
          {
            'date': s['date'],
            'meal': s['meal'],
            'recipeId': null,
            'title': 'Jelo ${s['date']} ${s['meal']}',
          },
      ],
    });
  }
  return jsonEncode({
    'recipes': [for (final t in titlesIn(r)) summary(t)],
  });
}

final monday = CivilDate(2026, 11, 2);

PlanRequest weekRequest({
  Set<MealType> types = const {MealType.lunch},
  String? wishes,
  bool usePantry = true,
  List<String> pantry = const [],
  List<DayBudget> budgets = const [],
}) => PlanRequest(
  range: DateRange(monday, monday.addDays(6)),
  mealTypes: types,
  wishes: wishes,
  usePantry: usePantry,
  pantryNames: pantry,
  budgets: budgets,
);

Recipe libraryRecipe(String id, String title, {int? activeMinutes}) => Recipe(
  id: id,
  title: title,
  activeMinutes: activeMinutes,
  servings: 4,
  ingredients: const [Ingredient(name: 'pasulj', quantity: 500, unit: 'g')],
  steps: const ['Skuvaj.'],
  source: RecipeSource.manual,
  createdAt: DateTime.utc(2026),
);

void main() {
  late ScriptedClient client;
  late MealPlanAI ai;

  setUp(() {
    client = ScriptedClient(goodAnswer);
    final router = AIRouter(
      config: () => const ChainConfig(vision: [model], text: [model]),
      client: client,
      keys: LayeredKeySource(
        InMemoryKeyStore({AIProvider.gemini: 'g-key'}),
        const BuiltInKeys(),
      ),
      status: InMemoryModelStatusStore(),
      clock: () => DateTime.utc(2026, 11, 2, 12),
    );
    ai = MealPlanAI(router);
  });

  group('zahtev', () {
    test('bez obroka, predugačak ili pogrešne porcije se odbija', () {
      final range = DateRange(monday, monday.addDays(6));
      expect(
        () => PlanRequest(range: range, mealTypes: const {}),
        throwsArgumentError,
      );
      expect(
        () => PlanRequest(
          range: DateRange(monday, monday.addDays(maxPlanDays)),
          mealTypes: const {MealType.lunch},
        ),
        throwsArgumentError,
      );
      for (final s in [0, 21]) {
        expect(
          () => PlanRequest(
            range: range,
            mealTypes: const {MealType.lunch},
            servings: s,
          ),
          throwsArgumentError,
        );
      }
    });

    test('mesta su hronološka, obroci redom u danu', () {
      final r = PlanRequest(
        range: DateRange(monday, monday.addDays(1)),
        mealTypes: const {MealType.dinner, MealType.breakfast},
      );
      expect(r.slots.map((s) => s.toString()), [
        '2026-11-02/breakfast',
        '2026-11-02/dinner',
        '2026-11-03/breakfast',
        '2026-11-03/dinner',
      ]);
    });
  });

  group('strogo čitanje rasporeda', () {
    final request = PlanRequest(
      range: DateRange(monday, monday.addDays(1)),
      mealTypes: const {MealType.lunch},
    );
    final slots = request.slots;
    Map<String, dynamic> meal(
      String date, {
      String type = 'lunch',
      String? id,
      String? title = 'Sarma',
    }) => {'date': date, 'meal': type, 'recipeId': id, 'title': title};

    Map<MealSlot, SlotProposal> parse(
      List<Object?> meals, {
      Map<String, String> library = const {},
    }) => parseOutline({'meals': meals}, slots: slots, library: library);

    test('ispravan raspored daje po jedan predlog za svako mesto', () {
      final r = parse(
        [
          meal('2026-11-02', title: '  Sarma '),
          meal('2026-11-03', id: 'r1', title: 'nešto'),
        ],
        library: {'r1': 'Pasulj'},
      );
      expect(r[slots[0]]!.title, 'Sarma');
      expect(r[slots[0]]!.draftRecipeKey, 'sarma');
      expect(r[slots[1]]!.libraryRecipeId, 'r1');
      expect(r[slots[1]]!.title, 'Pasulj', reason: 'naziv iz biblioteke');
    });

    test('nedostaje mesto', () {
      expect(() => parse([meal('2026-11-02')]), throwsFormatException);
    });

    test('dupliran predlog za isto mesto', () {
      expect(
        () =>
            parse([meal('2026-11-02'), meal('2026-11-02'), meal('2026-11-03')]),
        throwsFormatException,
      );
    });

    test('mesto van zahteva (drugi datum ili obrok)', () {
      expect(
        () =>
            parse([meal('2026-11-02'), meal('2026-11-03'), meal('2026-11-04')]),
        throwsFormatException,
      );
      expect(
        () => parse([
          meal('2026-11-02'),
          meal('2026-11-03'),
          meal('2026-11-03', type: 'dinner'),
        ]),
        throwsFormatException,
      );
    });

    test('nepoznat id recepta, loš datum, obrok ili naziv', () {
      expect(
        () => parse([meal('2026-11-02', id: 'tuđi'), meal('2026-11-03')]),
        throwsFormatException,
      );
      expect(
        () => parse([meal('2026-11-31'), meal('2026-11-03')]),
        throwsFormatException,
      );
      expect(
        () => parse([meal('2026-11-02', type: 'užina'), meal('2026-11-03')]),
        throwsFormatException,
      );
      expect(
        () => parse([meal('2026-11-02', title: ' '), meal('2026-11-03')]),
        throwsFormatException,
      );
      expect(
        () => parseOutline(const {}, slots: slots, library: const {}),
        throwsFormatException,
      );
    });
  });

  group('strogo čitanje recepata', () {
    test('svaki traženi recept tačno jednom, sa porcijama i sastojcima', () {
      final r = parseSummaries(
        {
          'recipes': [summary('Sarma'), summary('pasulj prebranac')],
        },
        titles: ['Sarma', 'Pasulj prebranac'],
      );
      expect(r.keys, {'sarma', 'pasulj prebranac'});
      expect(r['sarma']!.baseServings, 4);
      expect(r['sarma']!.steps, isEmpty);
      expect(r['sarma']!.ingredients.single.name, 'crni luk');
    });

    test('nedostaje, višak ili duplikat recepta', () {
      expect(
        () => parseSummaries(
          {
            'recipes': [summary('Sarma')],
          },
          titles: ['Sarma', 'Gulaš'],
        ),
        throwsFormatException,
      );
      expect(
        () => parseSummaries(
          {
            'recipes': [summary('Sarma'), summary('Gulaš')],
          },
          titles: ['Sarma'],
        ),
        throwsFormatException,
      );
      expect(
        () => parseSummaries(
          {
            'recipes': [summary('Sarma'), summary('sarma')],
          },
          titles: ['Sarma'],
        ),
        throwsFormatException,
      );
    });

    test('loše porcije ili sastojci', () {
      for (final servings in [0, 21]) {
        expect(
          () => parseSummaries(
            {
              'recipes': [summary('Sarma', servings: servings)],
            },
            titles: ['Sarma'],
          ),
          throwsFormatException,
        );
      }
      expect(
        () => parseSummaries(
          {
            'recipes': [
              {...summary('Sarma'), 'ingredients': <Object>[]},
            ],
          },
          titles: ['Sarma'],
        ),
        throwsFormatException,
      );
      expect(
        () => parseSummaries(
          {
            'recipes': [
              {
                ...summary('Sarma'),
                'ingredients': [
                  {'name': '', 'quantity': 1},
                ],
              },
            ],
          },
          titles: ['Sarma'],
        ),
        throwsFormatException,
      );
    });
  });

  group('generisanje', () {
    test('nedelja: jedan raspored, pa recepti u grupama do tri', () async {
      final draft = await ai.propose(weekRequest());

      expect(draft.isComplete, isTrue);
      expect(draft.proposals.length, 7);
      expect(draft.missingSlots, isEmpty);
      expect(client.requests.where(isOutline).length, 1);
      final batches = client.requests.where((r) => !isOutline(r)).toList();
      expect(batches.map((r) => titlesIn(r).length), [3, 3, 1]);
      for (final r in client.requests) {
        expect(r.kind, TaskKind.text);
      }
    });

    test('mesec: raspored po nedeljnim delovima, bez praznih i '
        'suvišnih mesta', () async {
      final novembar = PlanRequest(
        range: monthOf(CivilDate(2026, 11, 1)),
        mealTypes: const {MealType.lunch, MealType.dinner},
      );

      final draft = await ai.propose(novembar);

      // 1. novembar 2026. je nedelja: šest nedeljnih delova.
      final outlines = client.requests.where(isOutline).toList();
      expect(outlines.length, 6);
      expect(slotsIn(outlines.first).length, 2);
      expect(slotsIn(outlines.last).length, 2);
      expect(draft.proposals.length, 60);
      expect(draft.isComplete, isTrue);
      for (final r in client.requests.where((r) => !isOutline(r))) {
        expect(titlesIn(r).length, lessThanOrEqualTo(3));
      }
    });

    test('isti nov recept dva puta se piše jednom', () async {
      client.handler = (r) => isOutline(r)
          ? jsonEncode({
              'meals': [
                for (final s in slotsIn(r))
                  {...s, 'recipeId': null, 'title': 'Sarma'},
              ],
            })
          : goodAnswer(r);

      final draft = await ai.propose(weekRequest());

      expect(draft.newRecipes.keys, ['sarma']);
      expect(draft.isComplete, isTrue);
      expect(client.requests.length, 2);
    });

    test('recept iz biblioteke se ne piše ponovo; snimak je iz '
        'biblioteke', () async {
      client.handler = (r) => isOutline(r)
          ? jsonEncode({
              'meals': [
                for (final s in slotsIn(r))
                  {...s, 'recipeId': 'r1', 'title': 'x'},
              ],
            })
          : throw StateError('ne treba recept');

      final draft = await ai.propose(
        weekRequest(),
        library: [libraryRecipe('r1', 'Pasulj')],
      );

      expect(draft.isComplete, isTrue);
      expect(client.requests.length, 1);
      expect(client.requests.single.prompt, contains('"id":"r1"'));
      final snap = draft.snapshotFor(weekRequest().slots.first)!;
      expect(snap.title, 'Pasulj');
      expect(snap.steps, ['Skuvaj.']);
    });

    test('želje i zaliha idu u upit samo kad su izabrane', () async {
      await ai.propose(
        weekRequest(wishes: 'bez svinjetine', pantry: ['pirinač']),
      );
      expect(client.requests.first.prompt, contains('bez svinjetine'));
      expect(client.requests.first.prompt, contains('pirinač'));

      client.requests.clear();
      await ai.propose(weekRequest(usePantry: false, pantry: ['pirinač']));
      expect(client.requests.first.prompt, isNot(contains('pirinač')));
    });

    test('loš raspored se pita još jednom (ruter), pa uspeva', () async {
      var first = true;
      client.handler = (r) {
        if (isOutline(r) && first) {
          first = false;
          return '{"meals": []}';
        }
        return goodAnswer(r);
      };

      final draft = await ai.propose(weekRequest());

      expect(draft.isComplete, isTrue);
      expect(client.requests.where(isOutline).length, 2);
    });
  });

  test('predlog samo za izabrana mesta (zamena, ponovni predlog)', () async {
    final week = weekRequest(types: const {MealType.lunch, MealType.dinner});
    final only = {
      MealSlot(monday.addDays(1), MealType.dinner),
      MealSlot(monday.addDays(4), MealType.lunch),
    };
    final request = PlanRequest(
      range: week.range,
      mealTypes: week.mealTypes,
      only: only,
    );

    final draft = await ai.propose(request);

    expect(draft.proposals.keys.toSet(), only);
    expect(draft.isComplete, isTrue);
    expect(
      slotsIn(client.requests.first).map((s) => '${s['date']}/${s['meal']}'),
      ['2026-11-03/dinner', '2026-11-06/lunch'],
    );
    expect(client.requests.where(isOutline).length, 1);
  });

  test('mesta van plana ili prazan izbor se odbijaju', () {
    final week = weekRequest();
    expect(
      () => PlanRequest(
        range: week.range,
        mealTypes: week.mealTypes,
        only: const {},
      ),
      throwsArgumentError,
    );
    expect(
      () => PlanRequest(
        range: week.range,
        mealTypes: week.mealTypes,
        only: {MealSlot(monday, MealType.dinner)},
      ),
      throwsArgumentError,
    );
  });

  group('greška, nastavak i prekid', () {
    final twoWeeks = PlanRequest(
      range: DateRange(monday, monday.addDays(13)),
      mealTypes: const {MealType.lunch},
    );

    test('pala grupa čuva gotov deo; nastavak traži samo ono što '
        'nedostaje', () async {
      var outlines = 0;
      client.handler = (r) {
        if (isOutline(r) && ++outlines == 2) {
          throw const TransientError('mreža');
        }
        return goodAnswer(r);
      };

      final failed = await ai
          .propose(twoWeeks)
          .then<PlanGenerationFailed?>((_) => null)
          .catchError((Object e) => e as PlanGenerationFailed);

      expect(failed, isNotNull);
      expect(failed!.error, isA<AllModelsExhausted>());
      final partial = failed.draft;
      expect(partial.proposals.length, 7);
      expect(partial.missingSlots.length, 7);
      expect(partial.request, same(twoWeeks));

      client
        ..requests.clear()
        ..handler = goodAnswer;
      final done = await ai.propose(twoWeeks, resume: partial);

      expect(done.isComplete, isTrue);
      final outlineSlots = [
        for (final r in client.requests.where(isOutline)) ...slotsIn(r),
      ];
      expect(outlineSlots.map((s) => s['date']), [
        for (var i = 7; i < 14; i++) monday.addDays(i).toString(),
      ]);
      // Recepti se pišu tek posle svih rasporeda: sada svi, svaki jednom.
      final titles = [
        for (final r in client.requests.where((r) => !isOutline(r)))
          ...titlesIn(r),
      ];
      expect(titles.length, 14);
      expect(titles.toSet().length, 14);
    });

    test('pala grupa recepata: nastavak piše samo recepte koji '
        'nedostaju', () async {
      var batches = 0;
      client.handler = (r) {
        if (!isOutline(r) && ++batches == 2) {
          throw const TransientError('mreža');
        }
        return goodAnswer(r);
      };

      final failed = await ai
          .propose(weekRequest())
          .then<PlanGenerationFailed?>((_) => null)
          .catchError((Object e) => e as PlanGenerationFailed);
      final partial = failed!.draft;
      expect(partial.newRecipes.length, 3);
      expect(partial.missingRecipeKeys.length, 4);

      client
        ..requests.clear()
        ..handler = goodAnswer;
      final done = await ai.propose(partial.request, resume: partial);

      expect(done.isComplete, isTrue);
      expect(client.requests.where(isOutline), isEmpty);
      expect(
        client.requests.expand(titlesIn).length,
        4,
        reason: 'samo recepti koji nedostaju',
      );
    });

    test('prekid posle prve grupe ne zove dalje i vraća deo', () async {
      final cancel = PlanCancellation();
      final progress = <int>[];

      final cancelled = await ai
          .propose(
            twoWeeks,
            cancel: cancel,
            onProgress: (d) {
              progress.add(d.proposals.length);
              cancel.cancel();
            },
          )
          .then<PlanGenerationCancelled?>((_) => null)
          .catchError((Object e) => e as PlanGenerationCancelled);

      expect(cancelled, isNotNull);
      expect(cancelled!.draft.proposals.length, 7);
      expect(progress, [7]);
      expect(client.requests.length, 1);
    });

    test('napredak se javlja posle svake grupe', () async {
      final progress = <(int, int)>[];
      await ai.propose(
        weekRequest(),
        onProgress: (d) =>
            progress.add((d.proposals.length, d.readySlots.length)),
      );
      expect(progress.first, (7, 0));
      expect(progress.last, (7, 7));
      expect(progress.length, 4);
    });

    test('nastavak drugog zahteva se odbija', () {
      final other = PlanDraft(request: weekRequest());
      expect(() => ai.propose(twoWeeks, resume: other), throwsArgumentError);
    });
  });

  group('vreme po danu', () {
    const mondayLimit = DayBudget(weekday: 1, maxActiveMinutes: 20);

    String libraryAnswer(AIRequest r, String id) => isOutline(r)
        ? jsonEncode({
            'meals': [
              for (final s in slotsIn(r)) {...s, 'recipeId': id, 'title': 'x'},
            ],
          })
        : throw StateError('ne treba sažetak');

    test('ograničenje dana i vreme recepta idu u upit', () async {
      client.handler = (r) => libraryAnswer(r, 'brzo');
      await ai.propose(
        weekRequest(budgets: const [mondayLimit]),
        library: [libraryRecipe('brzo', 'Omlet', activeMinutes: 10)],
      );
      final prompt = client.requests.first.prompt;
      expect(prompt, contains('$monday: at most 20 min of active work'));
      expect(prompt, isNot(contains('${monday.addDays(1)}: at most')));
      expect(prompt, contains('"activeMinutes":10'));
    });

    test(
      'recept koji ne staje u vreme se traži ponovo, samo za taj dan',
      () async {
        client.handler = (r) {
          final slots = slotsIn(r);
          // Prvi raspored svuda stavlja dug pasulj; ponovljeni bira omlet.
          return libraryAnswer(r, slots.length == 1 ? 'brzo' : 'dugo');
        };
        final draft = await ai.propose(
          weekRequest(budgets: const [mondayLimit]),
          library: [
            libraryRecipe('dugo', 'Pasulj', activeMinutes: 60),
            libraryRecipe('brzo', 'Omlet', activeMinutes: 10),
          ],
        );
        final outlines = client.requests.where(isOutline).toList();
        expect(outlines, hasLength(2));
        expect(slotsIn(outlines[1]), [
          {'date': '$monday', 'meal': 'lunch'},
        ]);
        expect(outlines[1].prompt, contains('Pasulj'));
        expect(
          draft.snapshotFor(MealSlot(monday, MealType.lunch))!.title,
          'Omlet',
        );
        expect(
          draft.snapshotFor(MealSlot(monday.addDays(1), MealType.lunch))!.title,
          'Pasulj',
        );
      },
    );

    test(
      'ako ni ponovljen predlog ne staje, ostaje i ne pita se dalje',
      () async {
        client.handler = (r) => libraryAnswer(r, 'dugo');
        final draft = await ai.propose(
          weekRequest(budgets: const [mondayLimit]),
          library: [libraryRecipe('dugo', 'Pasulj', activeMinutes: 60)],
        );
        expect(client.requests.where(isOutline), hasLength(2));
        expect(draft.isComplete, isTrue);
        expect(
          draft.snapshotFor(MealSlot(monday, MealType.lunch))!.title,
          'Pasulj',
        );
      },
    );

    test('nepoznato vreme recepta ne traži ponovni predlog', () async {
      client.handler = (r) => libraryAnswer(r, 'nepoznato');
      await ai.propose(
        weekRequest(budgets: const [mondayLimit]),
        library: [libraryRecipe('nepoznato', 'Gulaš')],
      );
      expect(client.requests.where(isOutline), hasLength(1));
    });
  });
}
