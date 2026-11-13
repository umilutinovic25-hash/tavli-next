import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/food_nutrition_csv.dart';

const header = 'food_id,fdc_id,usda_portion,volume_ml\n';
const portions =
    '"id","fdc_id","seq_num","amount","measure_unit_id","portion_description","modifier","gram_weight","data_points","footnote","min_year_acquired"\n'
    '"1","171287","1","1","9999","","large","50","","",""\n'
    '"2","171287","2","1","9999","","extra large","56","","",""\n'
    '"3","171265","1","1","9999","","cup","244","","",""\n'
    '"4","171265","2","1","9999","","fl oz","30.5","","",""\n'
    '"5","170000","1","0.5","9999","","half","30","","",""\n'
    '"6","171000","1","1","9999","","bad","abc","","",""\n';
const baseUnits = {
  'f_jaje': 'kom',
  'f_mleko': 'ml',
  'f_krompir': 'g',
  'f_pola': 'kom',
  'f_lose': 'kom',
};

List<UnitWeightRow> build(String body) => buildUnitWeightRows(
  weightsCsv: '$header$body',
  baseUnits: baseUnits,
  usdaPortionCsv: portions,
);

void main() {
  test('komad: gram težina iz izvora, bez zaokruživanja viška', () {
    final rows = build('f_jaje,171287,large,\n');
    expect(rows.single.foodId, 'f_jaje');
    expect(rows.single.gramsPerUnit, '50.0000');
    expect(rows.single.portion, 'large');
  });

  test('ml: gustina iz težine i zapremine reda', () {
    final rows = build('f_mleko,171265,fl oz,29.5735\n');
    expect(rows.single.gramsPerUnit, '1.0313');
  });

  test('količina u redu se deli (pola komada)', () {
    final rows = build('f_pola,170000,half,\n');
    expect(rows.single.gramsPerUnit, '60.0000');
  });

  test('odbija zaglavlje, nepoznatu i ponovljenu namirnicu', () {
    expect(
      () => buildUnitWeightRows(
        weightsCsv: 'a,b\n',
        baseUnits: baseUnits,
        usdaPortionCsv: portions,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => build('f_nepoznata,171287,large,\n'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => build('f_jaje,171287,large,\nf_jaje,171287,large,\n'),
      throwsA(isA<FormatException>()),
    );
  });

  test('g-namirnica nema težinu po jedinici (1 g je 1 g)', () {
    expect(
      () => build('f_krompir,171287,large,\n'),
      throwsA(isA<FormatException>()),
    );
  });

  test('komad ne sme da ima zapreminu, ml mora da je ima', () {
    expect(
      () => build('f_jaje,171287,large,29.5735\n'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => build('f_mleko,171265,fl oz,\n'),
      throwsA(isA<FormatException>()),
    );
  });

  test('odbija red koji ne postoji u izvoru ili nema ispravnu težinu', () {
    expect(
      () => build('f_jaje,171287,medium,\n'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => build('f_lose,171000,bad,\n'),
      throwsA(isA<FormatException>()),
    );
  });

  test('SQL ažurira samo zajedničku namirnicu bez težine', () {
    final sql = unitWeightSeedSql(build('f_jaje,171287,large,\n'));
    expect(sql, contains('update public.foods set unit_grams = 50.0000'));
    expect(
      sql,
      contains("unit_grams_source = 'usda-sr-legacy-2018-04:171287:large'"),
    );
    expect(sql, contains("where id = 'f_jaje'"));
    expect(sql, contains('household_id is null'));
    expect(sql, contains('unit_grams is null'));
  });
}
