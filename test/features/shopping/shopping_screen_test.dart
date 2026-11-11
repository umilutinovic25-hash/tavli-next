import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/data/meal_plan_repository.dart';
import 'package:tavli/data/shopping_repository.dart';
import 'package:tavli/domain/meal_plan.dart';
import 'package:tavli/domain/plan_calendar.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_source.dart';
import 'package:tavli/features/recipes/recipe_providers.dart';
import 'package:tavli/sync/synced_writer.dart';

import '../../helpers/food_seed.dart';
import '../../helpers/test_app.dart';

/// Sreda u prvoj nedelji plana 2–15. novembra.
final today = DateTime(2026, 11, 4, 9);

final twoWeeks = DateRange(CivilDate(2026, 11, 2), CivilDate(2026, 11, 15));

Future<AccountScope> scopeOf(AppDatabase db) async {
  final account = await db.select(db.accounts).getSingle();
  return AccountScope(userId: account.userId, householdId: account.householdId);
}

/// Ručak svaki dan: 1 kg krompira i so bez količine.
Future<String> seedPlan(AppDatabase db, DateRange range) async {
  final scope = await scopeOf(db);
  final writer = SyncedWriter(db, accountId: scope.userId);
  final repo = MealPlanRepository(
    db,
    scope: scope,
    writer: writer,
    shopping: ShoppingRepository(db, scope: scope, writer: writer),
    clock: () => DateTime.utc(2026, 11),
  );
  final request = PlanRequest(range: range, mealTypes: const {MealType.lunch});
  String key(MealSlot s) => 'ručak ${s.date.month}-${s.date.day}';
  return repo.approve(
    PlanDraft(
      request: request,
      proposals: {
        for (final s in request.slots)
          s: SlotProposal(
            title: 'Ručak ${s.date.day}.${s.date.month}.',
            draftRecipeKey: key(s),
          ),
      },
      newRecipes: {
        for (final s in request.slots)
          key(s): RecipeSnapshot(
            title: 'Ručak ${s.date.day}.${s.date.month}.',
            baseServings: 2,
            ingredients: const [
              Ingredient(
                name: 'krompir',
                quantity: 1,
                unit: 'kg',
                category: 'voće i povrće',
              ),
              Ingredient(name: 'so', category: 'začini i sosovi'),
            ],
          ),
      },
    ),
  );
}

Future<TestApp> pumpShopping(
  WidgetTester tester, {
  Size size = phone,
  String location = '/shopping',
  Future<void> Function(AppDatabase db)? setup,
}) => pumpTavli(
  tester,
  size: size,
  location: location,
  setup: setup ?? (db) => seedPlan(db, twoWeeks),
  overrides: [clockProvider.overrideWithValue(() => today)],
);

Finder tileOf(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(ListTile)).first;

Future<void> tapIn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testTavli('uređivanje detalja i fotografije stavke bez promene količine', (
    tester,
  ) async {
    final app = await pumpShopping(tester);
    final edit = find.descendant(
      of: tileOf('krompir'),
      matching: find.byTooltip('Detalji stavke'),
    );
    await tapIn(tester, edit);
    await tester.enterText(
      find.widgetWithText(TextField, 'Brend'),
      'Moj brend',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Napomena'),
      'Sitniji',
    );
    expect(find.text('Dodaj fotografiju'), findsOneWidget);
    app.picker.next = fakePhoto;
    await tapIn(tester, find.text('Galerija'));
    expect(find.text('Promeni fotografiju'), findsOneWidget);
    await tapIn(tester, find.text('Sačuvaj'));
    expect(find.textContaining('Moj brend'), findsOneWidget);
    var item = (await app.db.select(app.db.shoppingItems).get()).firstWhere(
      (i) => i.name == 'krompir',
    );
    expect(
      [item.brand, item.note, item.quantity],
      ['Moj brend', 'Sitniji', 7.0],
    );
    expect(item.photoPath, isNotNull);
    await tapIn(
      tester,
      find.descendant(
        of: tileOf('krompir'),
        matching: find.byTooltip('Detalji stavke'),
      ),
    );
    await tapIn(tester, find.text('Ukloni fotografiju'));
    await tapIn(tester, find.text('Sačuvaj'));
    item = (await app.db.select(app.db.shoppingItems).get()).firstWhere(
      (i) => i.name == 'krompir',
    );
    expect(item.photoPath, isNull);
    expect(item.brand, 'Moj brend');
  });

  testTavli('iz plana u dva dodira: nabavka tekuće nedelje po kategorijama', (
    tester,
  ) async {
    await pumpShopping(tester, location: '/plan');
    await tapIn(tester, find.text('Otvori nabavku'));

    expect(find.text('Po planu'), findsOneWidget);
    expect(find.text('Po receptu'), findsOneWidget);
    expect(find.text('2–8. novembar 2026.'), findsOneWidget);
    expect(find.text('Voće i povrće'), findsOneWidget);
    expect(find.text('Začini i sosovi'), findsOneWidget);
    expect(find.text('krompir'), findsOneWidget);
    expect(find.text('7 kg'), findsOneWidget);
    // Nepoznata količina se ne izmišlja.
    expect(find.text('Proveri količinu'), findsOneWidget);
  });

  testTavli('stavka pokazuje za koje obroke je', (tester) async {
    await pumpShopping(tester);
    await tapIn(
      tester,
      find.descendant(
        of: tileOf('krompir'),
        matching: find.byTooltip('Za koje obroke'),
      ),
    );
    expect(find.text('Potrebno za:'), findsOneWidget);
    expect(find.text('Ručak 2.11.'), findsOneWidget);
    expect(
      find.text('Ponedeljak, 2. novembar · Ručak · 2 porcije'),
      findsOneWidget,
    );
    expect(find.text('Ručak 9.11.'), findsNothing);
  });

  testTavli('štikliranje odmah prebacuje u Kupljeno, Poništi vraća; prijem '
      'u ostavu zaključava kupovinu', (tester) async {
    await pumpShopping(tester);
    await tapIn(tester, tileOf('krompir'));

    expect(find.text('Kupljeno: krompir'), findsOneWidget);
    expect(find.text('Kupljeno · 1'), findsOneWidget);
    await tester.tap(find.text('Poništi'));
    await tester.pumpAndSettle();
    expect(find.text('Kupljeno · 1'), findsNothing);
    expect(find.text('7 kg'), findsOneWidget);

    await tapIn(tester, tileOf('krompir'));
    await tapIn(tester, find.text('Prebaci u ostavu (1)'));
    expect(find.text('Prebačeno u ostavu: 1'), findsOneWidget);
    expect(find.text('7 kg · U ostavi'), findsOneWidget);
    expect(find.textContaining('Prebaci u ostavu'), findsNothing);
    final checkbox = tester.widget<Checkbox>(
      find.descendant(of: tileOf('krompir'), matching: find.byType(Checkbox)),
    );
    expect(checkbox.onChanged, isNull);
  });

  testTavli('ručna stavka bira namirnicu u detaljima; izvedena nema izbor', (
    tester,
  ) async {
    final app = await pumpShopping(
      tester,
      setup: (db) async {
        await seedPlan(db, twoWeeks);
        await seedEggs(db);
      },
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Dodaj stavku'),
      'Domaća jajca',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Domaća jajca'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tapIn(
      tester,
      find.descendant(
        of: tileOf('Domaća jajca'),
        matching: find.byTooltip('Detalji stavke'),
      ),
    );
    final dialog = find.byType(AlertDialog);
    await tapIn(
      tester,
      find.descendant(of: dialog, matching: find.text('Nepotvrđeno')),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Pretraži namirnice'),
      'jaj',
    );
    await tester.pumpAndSettle();
    await tapIn(tester, find.widgetWithText(ListTile, 'jaje'));
    expect(find.descendant(of: dialog, matching: find.text('jaje')), findsOne);
    await tapIn(
      tester,
      find.descendant(of: dialog, matching: button('Sačuvaj')),
    );
    final item = (await app.db.select(app.db.shoppingItems).get()).firstWhere(
      (i) => i.name == 'Domaća jajca',
    );
    expect(item.foodId, 'f_jaje');

    await tapIn(
      tester,
      find.descendant(
        of: tileOf('krompir'),
        matching: find.byTooltip('Detalji stavke'),
      ),
    );
    expect(find.byType(ActionChip), findsNothing);
  });

  testTavli('ručna stavka: brzo dodavanje i brisanje', (tester) async {
    await pumpShopping(tester);
    await tester.enterText(find.byType(TextField), 'Deterdžent');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    // Kategorija može biti ispod početnog prikaza na telefonu.
    await tester.scrollUntilVisible(
      find.text('Ostalo'),
      160,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Ostalo'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Deterdžent'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Deterdžent'), findsOneWidget);

    await tapIn(
      tester,
      find.descendant(
        of: tileOf('Deterdžent'),
        matching: find.byTooltip('Obriši'),
      ),
    );
    expect(find.text('Deterdžent'), findsNothing);
    expect(find.text('Obrisano: Deterdžent'), findsOneWidget);
  });

  testTavli('ceo plan sabira nedelje; kupovina u njemu se vidi u nedelji', (
    tester,
  ) async {
    await pumpShopping(tester);
    expect(find.text('Nedelja 1'), findsOneWidget);
    expect(find.text('Nedelja 2'), findsOneWidget);

    await tapIn(tester, find.text('Ceo plan'));
    expect(
      find.text('2–15. novembar 2026. · zbir svih nedelja'),
      findsOneWidget,
    );
    expect(find.text('14 kg'), findsOneWidget);
    await tapIn(tester, tileOf('krompir'));
    expect(find.text('Kupljeno · 1'), findsOneWidget);
    expect(find.text('kupljeno 14 kg'), findsOneWidget);

    await tapIn(tester, find.text('Nedelja 2'));
    expect(find.text('9–15. novembar 2026.'), findsOneWidget);
    expect(find.text('Kupljeno · 1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('7 kg'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('krompir'), findsOneWidget);
  });

  testTavli('bez plana i bez stavki: prazna nabavka; po receptu radi bez '
      'plana', (tester) async {
    await pumpShopping(tester, setup: (_) async {});
    expect(find.text('Nabavka je prazna'), findsOneWidget);
    expect(find.text('Napravi plan'), findsOneWidget);
  });

  testTavli('po receptu bez plana: pripreme i njihove stavke; uklanjanje '
      'pripreme čuva kupljeno', (tester) async {
    await pumpShopping(
      tester,
      setup: (db) async {
        final scope = await scopeOf(db);
        final shop = ShoppingRepository(
          db,
          scope: scope,
          writer: SyncedWriter(db, accountId: scope.userId),
        );
        await shop.addRecipePreparation(
          snapshot: const RecipeSnapshot(
            title: 'Musaka',
            baseServings: 4,
            ingredients: [
              Ingredient(
                name: 'patlidžan',
                quantity: 2,
                unit: 'kom',
                category: 'voće i povrće',
              ),
              Ingredient(name: 'mleko', quantity: 0.5, unit: 'l'),
            ],
          ),
          servings: 4,
          originKey: 'recipe:musaka',
        );
      },
    );
    expect(find.text('Još nemaš plan'), findsOneWidget);
    await tapIn(tester, find.widgetWithText(OutlinedButton, 'Po receptu'));
    expect(find.text('Recepti u nabavci'), findsOneWidget);
    expect(find.text('4 porcije · 2 sastojka za kupovinu'), findsOneWidget);
    await tapIn(tester, tileOf('patlidžan'));
    await tapIn(tester, find.byTooltip('Za koje obroke').first);
    expect(find.text('Recept · 4 porcije'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tapIn(tester, find.byTooltip('Ukloni iz nabavke'));
    expect(find.text('Recepti u nabavci'), findsNothing);
    expect(find.text('mleko'), findsNothing);
    expect(find.text('patlidžan'), findsOneWidget);
    expect(find.text('Kupljeno · 1'), findsOneWidget);
  });

  for (final size in [const Size(320, 700), wide]) {
    testTavli('${size.width} px, tekst 2×: bez preliva', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpShopping(tester, size: size);
      await tapIn(tester, find.text('Ceo plan'));
      await tapIn(tester, find.text('Po receptu'));
      expect(tester.takeException(), isNull);
    });
  }
}
