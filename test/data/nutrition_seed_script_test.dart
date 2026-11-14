import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixture;
  late String dart;
  final root = Directory.current.absolute.path;
  late File historicalNutrition;
  late File historicalWeights;

  setUp(() {
    final config = File('$root/.dart_tool/package_config.json');
    final packages =
        (jsonDecode(config.readAsStringSync())
                as Map<String, dynamic>)['packages']
            as List<dynamic>;
    final flutterTest = packages.cast<Map<String, dynamic>>().singleWhere(
      (p) => p['name'] == 'flutter_test',
    );
    final sdk = Directory.fromUri(
      config.uri.resolve(flutterTest['rootUri'] as String),
    ).parent.parent;
    dart = '${sdk.path}/bin/cache/dart-sdk/bin/dart';
    fixture = Directory.systemTemp.createTempSync('tavli-nutrition-seed-');
    void put(String name, String content) {
      final file = File('${fixture.path}/$name');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    put(
      'supabase/catalog/foods.csv',
      'id,name,category,base_unit,aliases,conversions,allergens\n'
          'f_jaje,jaje,mlečni proizvodi i jaja,kom,jaja,,eggs\n',
    );
    put(
      'supabase/catalog/nutrition_map.csv',
      'food_id,fdc_id,usda_description\nf_jaje,171287,"Egg, whole, raw, fresh"\n',
    );
    put(
      'supabase/catalog/unit_weights.csv',
      'food_id,fdc_id,usda_portion,volume_ml\nf_jaje,171287,large,\n',
    );
    put(
      'usda/food.csv',
      'fdc_id,data_type,description\n171287,sr_legacy_food,"Egg, whole, raw, fresh"\n',
    );
    put(
      'usda/food_nutrient.csv',
      'id,fdc_id,nutrient_id,amount\n1,171287,1008,143\n'
          '2,171287,1003,12.56\n3,171287,1004,9.51\n4,171287,1005,0.72\n',
    );
    put(
      'usda/food_portion.csv',
      'id,fdc_id,seq_num,amount,measure_unit_id,portion_description,modifier,gram_weight\n'
          '1,171287,1,1,9999,,large,50\n',
    );
    historicalNutrition = File(
      '${fixture.path}/supabase/migrations/20261113190100_food_nutrition_seed.sql',
    );
    historicalWeights = File(
      '${fixture.path}/supabase/migrations/20261113200100_food_unit_weights_seed.sql',
    );
    put(
      'supabase/migrations/20261113190100_food_nutrition_seed.sql',
      'primenjeno nutrition',
    );
    put(
      'supabase/migrations/20261113200100_food_unit_weights_seed.sql',
      'primenjeno weights',
    );
  });
  tearDown(() => fixture.deleteSync(recursive: true));

  Future<ProcessResult> run(List<String> args) => Process.run(dart, [
    '--packages=$root/.dart_tool/package_config.json',
    '$root/scripts/nutrition_seed.dart',
    'usda',
    ...args,
  ], workingDirectory: fixture.path);

  void expectHistoryIntact() {
    expect(historicalNutrition.readAsStringSync(), 'primenjeno nutrition');
    expect(historicalWeights.readAsStringSync(), 'primenjeno weights');
  }

  test('oba izlaza su nova; istorijske migracije ostaju iste', () async {
    final result = await run(['new-nutrition.sql', 'new-weights.sql']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expectHistoryIntact();
    expect(
      File('${fixture.path}/new-nutrition.sql').readAsStringSync(),
      contains('kcal_100 = 143'),
    );
    expect(
      File('${fixture.path}/new-weights.sql').readAsStringSync(),
      contains('unit_grams = 50.0000'),
    );
  });

  test('bez oba eksplicitna izlaza ništa ne piše', () async {
    for (final args in [
      <String>[],
      ['new-nutrition.sql'],
    ]) {
      final result = await run(args);
      expect(result.exitCode, isNot(0));
      expectHistoryIntact();
      expect(File('${fixture.path}/new-nutrition.sql').existsSync(), isFalse);
    }
  });

  test('postojeći drugi izlaz odbija pre pisanja prvog', () async {
    final result = await run([
      'new-nutrition.sql',
      'supabase/migrations/20261113200100_food_unit_weights_seed.sql',
    ]);
    expect(result.exitCode, isNot(0));
    expectHistoryIntact();
    expect(File('${fixture.path}/new-nutrition.sql').existsSync(), isFalse);
  });

  test('neispravna težina ne ostavlja delimičnu migraciju', () async {
    File('${fixture.path}/supabase/catalog/unit_weights.csv').writeAsStringSync(
      'food_id,fdc_id,usda_portion,volume_ml\nf_jaje,171287,missing,\n',
    );
    final result = await run(['new-nutrition.sql', 'new-weights.sql']);
    expect(result.exitCode, isNot(0));
    expect(File('${fixture.path}/new-nutrition.sql').existsSync(), isFalse);
    expect(File('${fixture.path}/new-weights.sql').existsSync(), isFalse);
    expectHistoryIntact();
  });

  test('iste izlazne putanje se odbijaju bez pisanja', () async {
    final result = await run(['same.sql', './same.sql']);
    expect(result.exitCode, isNot(0));
    expect(File('${fixture.path}/same.sql').existsSync(), isFalse);
    expectHistoryIntact();
  });

  test('greška pisanja drugog izlaza uklanja samo nov prvi izlaz', () async {
    final result = await run(['new-nutrition.sql', 'missing/new-weights.sql']);
    expect(result.exitCode, isNot(0));
    expect(File('${fixture.path}/new-nutrition.sql').existsSync(), isFalse);
    expectHistoryIntact();
  });
}
