import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/food_nutrition_csv.dart';

const mapHeader = 'food_id,fdc_id,usda_description\n';
const foodCsv =
    '"fdc_id","data_type","description","food_category_id","publication_date"\n'
    '"171287","sr_legacy_food","Egg, whole, raw, fresh","100","2019-04-01"\n'
    '"173647","sr_legacy_food","Beverages, water, tap, drinking","1400","2019-04-01"\n'
    '"999999","sr_legacy_food","Nema nutrijenata","1","2019-04-01"\n';
const nutrientCsv =
    '"id","fdc_id","nutrient_id","amount","data_points","derivation_id"\n'
    '"1","171287","1008","143","1","1"\n'
    '"2","171287","1003","12.56","1","1"\n'
    '"3","171287","1004","9.51","1","1"\n'
    '"4","171287","1005","0.72","1","1"\n'
    '"5","171287","1051","76","1","1"\n'
    '"6","173647","1008","0","1","1"\n'
    '"7","173647","1003","0","1","1"\n'
    '"8","173647","1004","0","1","1"\n'
    '"9","173647","1005","0","1","1"\n'
    '"10","999999","1008","10","1","1"\n';
const catalogIds = {'f_jaje', 'f_voda', 'f_nema'};

List<NutritionRow> build(String mapBody) => buildNutritionRows(
  mapCsv: '$mapHeader$mapBody',
  catalogIds: catalogIds,
  usdaFoodCsv: foodCsv,
  usdaFoodNutrientCsv: nutrientCsv,
);

void main() {
  test(
    'pregledano mapiranje ne koristi napitak ili drugo stanje namirnice',
    () {
      final lines = File('supabase/catalog/nutrition_map.csv')
          .readAsLinesSync();
      for (final (food, wrongRef) in [
        ('f_kafa', '171890'),
        ('f_caj', '173227'),
        ('f_kokos', '170169'),
        ('f_prezle', '174924'),
        ('f_lisnato_testo', '172738'),
      ]) {
        expect(
          lines.any((line) => line.startsWith('$food,$wrongRef,')),
          isFalse,
          reason: '$food nema odgovarajuće stanje u USDA zapisu $wrongRef',
        );
      }
    },
  );
  test('vrednosti dolaze iz izvora, bez zaokruživanja', () {
    final rows = build(
      'f_jaje,171287,"Egg, whole, raw, fresh"\n'
      'f_voda,173647,"Beverages, water, tap, drinking"\n',
    );
    expect(rows, hasLength(2));
    expect(rows.first.foodId, 'f_jaje');
    expect(rows.first.fdcId, 171287);
    expect(
      (rows.first.kcal, rows.first.protein, rows.first.fat, rows.first.carbs),
      ('143', '12.56', '9.51', '0.72'),
    );
    expect(rows.last.kcal, '0');
  });

  test('odbija pogrešno zaglavlje', () {
    expect(
      () => buildNutritionRows(
        mapCsv: 'a,b\nf_jaje,1\n',
        catalogIds: catalogIds,
        usdaFoodCsv: foodCsv,
        usdaFoodNutrientCsv: nutrientCsv,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('odbija namirnicu koje nema u katalogu', () {
    expect(
      () => build('f_nepoznata,171287,"Egg, whole, raw, fresh"\n'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('f_nepoznata'),
        ),
      ),
    );
  });

  test('odbija ponovljenu namirnicu', () {
    expect(
      () => build(
        'f_jaje,171287,"Egg, whole, raw, fresh"\n'
        'f_jaje,171287,"Egg, whole, raw, fresh"\n',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('odbija zapis koji ne postoji u USDA fajlu', () {
    expect(() => build('f_jaje,111,"Egg"\n'), throwsA(isA<FormatException>()));
  });

  test('odbija kad se opis ne poklapa sa USDA zapisom (pogrešan id)', () {
    expect(
      () => build('f_jaje,171287,"Milk, whole"\n'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('opis'),
        ),
      ),
    );
  });

  test('odbija zapis kome fali neki od četiri nutrijenta', () {
    expect(
      () => build('f_nema,999999,"Nema nutrijenata"\n'),
      throwsA(isA<FormatException>()),
    );
  });

  test('SQL ažurira samo zajedničku namirnicu bez vrednosti', () {
    final sql = nutritionSeedSql(
      build('f_jaje,171287,"Egg, whole, raw, fresh"\n'),
    );
    expect(sql, contains('update public.foods set'));
    expect(sql, contains('kcal_100 = 143'));
    expect(sql, contains('protein_100 = 12.56'));
    expect(sql, contains('fat_100 = 9.51'));
    expect(sql, contains('carbs_100 = 0.72'));
    expect(sql, contains("nutrition_source = 'usda-sr-legacy-2018-04'"));
    expect(sql, contains("nutrition_ref = '171287'"));
    expect(sql, contains("where id = 'f_jaje'"));
    expect(sql, contains('household_id is null'));
    expect(sql, contains('kcal_100 is null'));
  });
}
