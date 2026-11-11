import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/account/auth_controller.dart';
import 'package:tavli/data/database.dart';
import 'package:tavli/features/foods/food_chip.dart';
import 'package:tavli/features/foods/food_picker.dart';
import 'package:tavli/providers.dart';
import 'package:tavli/sync/synced_writer.dart';

const _scope = AccountScope(userId: 'u1', householdId: 'h1');

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    Future<void> food(String id, String name, String category, String unit) =>
        db
            .into(db.foods)
            .insert(
              FoodsCompanion.insert(
                id: id,
                name: name,
                category: category,
                baseUnit: unit,
              ),
            );
    Future<void> alias(String foodId, String alias) => db
        .into(db.foodAliases)
        .insert(
          FoodAliasesCompanion.insert(
            id: '$foodId:$alias',
            foodId: foodId,
            alias: alias,
          ),
        );
    await food('f_jaje', 'jaje', 'mlečni proizvodi i jaja', 'kom');
    await alias('f_jaje', 'jaje');
    await alias('f_jaje', 'jajce');
    await food('f_beli_luk', 'beli luk', 'voće i povrće', 'g');
    await alias('f_beli_luk', 'beli luk');
    await alias('f_beli_luk', 'češnjak');
  });

  tearDown(() => db.close());

  /// Na kraju skida stablo, da drift tokovi i riverpod zatvore tajmere.
  void testFoods(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  /// Dugme otvara izbor; vraćen id se prikazuje u tekstu `izbor: …`.
  Future<void> pump(
    WidgetTester tester, {
    required String text,
    String category = 'ostalo',
    String? unit,
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? picked;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          accountScopeProvider.overrideWithValue(_scope),
          syncedWriterProvider.overrideWithValue(
            SyncedWriter(db, accountId: 'u1'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  FilledButton(
                    onPressed: () async {
                      final id = await pickFood(
                        context,
                        text: text,
                        category: category,
                        unit: unit,
                      );
                      setState(() => picked = id);
                    },
                    child: const Text('otvori'),
                  ),
                  Text('izbor: $picked'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('otvori'));
    await tester.pumpAndSettle();
  }

  Future<int> foodCount() async => (await db.select(db.foods).get()).length;

  testFoods('pretraga po aliasu nalazi namirnicu i vraća njen id', (
    tester,
  ) async {
    await pump(tester, text: 'Bijeli luk');
    expect(find.text('Izaberi namirnicu'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Pretraži namirnice'),
      'češnj',
    );
    await tester.pumpAndSettle();
    expect(find.text('jaje'), findsNothing);
    await tester.tap(find.text('beli luk'));
    await tester.pumpAndSettle();
    expect(find.text('izbor: f_beli_luk'), findsOneWidget);
  });

  testFoods('„Nova namirnica“ nudi upisani tekst i čuva ga kao alias', (
    tester,
  ) async {
    await pump(
      tester,
      text: 'Pitaja ',
      category: 'voće i povrće',
      unit: 'kašika',
    );
    await tester.tap(find.text('Nova namirnica'));
    await tester.pumpAndSettle();
    final name = find.widgetWithText(TextField, 'Naziv namirnice');
    expect(tester.widget<TextField>(name).controller!.text, 'Pitaja');
    expect(find.text('Kategorija'), findsOneWidget);
    expect(find.text('Osnovna jedinica'), findsOneWidget);
    await tester.enterText(name, 'Zmajevo voće');
    // Jedinica „kašika“ nije osnovna: osoba bira, dugme čeka izbor.
    final save = find.widgetWithText(
      FilledButton,
      'Sačuvaj kao moju namirnicu',
    );
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(find.text('g'));
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final own = await (db.select(
      db.foods,
    )..where((f) => f.householdId.equals('h1'))).getSingle();
    expect(own.name, 'zmajevo voće');
    expect(own.category, 'voće i povrće');
    expect(own.baseUnit, 'g');
    final aliases = await (db.select(
      db.foodAliases,
    )..where((a) => a.foodId.equals(own.id))).map((a) => a.alias).get();
    expect(aliases.toSet(), {'zmajevo voće', 'pitaja'});
    expect(find.text('izbor: ${own.id}'), findsOneWidget);
  });

  testFoods('zauzet alias → poruka, bez upisa', (tester) async {
    await pump(tester, text: 'Jajce', unit: 'kom');
    await tester.tap(find.text('Nova namirnica'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Sačuvaj kao moju namirnicu'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ova namirnica već postoji u katalogu.'), findsOneWidget);
    expect(await foodCount(), 2);
    // Forma ostaje otvorena, ništa nije izabrano.
    expect(find.text('Naziv namirnice'), findsOneWidget);
  });

  testFoods('sheet na uskoj, dijalog na širokoj širini', (tester) async {
    await pump(tester, text: 'x');
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    Navigator.of(tester.element(find.text('Izaberi namirnicu'))).pop();
    await tester.pumpAndSettle();

    await pump(tester, text: 'x', size: const Size(1200, 800));
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  group('FoodChip', () {
    Future<void> chip(WidgetTester tester, String? foodId) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            accountScopeProvider.overrideWithValue(_scope),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: FoodChip(foodId: foodId, onPressed: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testFoods('bez namirnice → „Nepotvrđeno“', (tester) async {
      await chip(tester, null);
      expect(find.text('Nepotvrđeno'), findsOneWidget);
    });

    testFoods('sa namirnicom → njen naziv', (tester) async {
      await chip(tester, 'f_jaje');
      expect(find.text('jaje'), findsOneWidget);
      expect(find.text('Nepotvrđeno'), findsNothing);
    });
  });
}
