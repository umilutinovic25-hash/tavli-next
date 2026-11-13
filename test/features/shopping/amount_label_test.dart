import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/features/shopping/shopping_list_view.dart';

void main() {
  test('približna količina dobija znak ~ ispred', () {
    expect(amountLabel(350, 'ml', approximate: true), '~350 ml');
  });

  test('tačna količina nema znak ~', () {
    expect(amountLabel(1.5, 'kg'), '1,5 kg');
  });

  test('nepoznata količina je null i kad je označena približnom', () {
    expect(amountLabel(null, 'ml', approximate: true), isNull);
  });
}
