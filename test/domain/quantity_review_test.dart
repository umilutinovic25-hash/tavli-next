import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/quantity_review.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/recipe_format.dart';

void main() {
  test('pregled čuva preciznost količine umesto prikaza 0 g za 0,001 g', () {
    expect(
      ingredientLine(
        const Ingredient(name: 'šafran', quantity: 0.001, unit: 'g'),
        preservePrecision: true,
      ),
      '0,001 g šafran',
    );
    expect(formatQuantity(250, preservePrecision: true), '250');
    expect(formatQuantity(250.5, preservePrecision: true), '250,5');
  });

  test('nedostajuća i nečitljiva količina ostaju za proveru, bez procene', () {
    for (final raw in [null, '', 'po ukusu', '1/0', 'nečitko']) {
      final ingredient = Ingredient.fromJson({'name': 'so', 'quantity': raw});
      expect(quantityReviewIssue(ingredient), QuantityReviewIssue.unknown);
      expect(ingredient.quantity, isNull);
    }
  });
  test(
    'nula, negativno i nekonačno su neispravni, ne postaju procenjene mere',
    () {
      for (final q in [
        0.0,
        -1.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          quantityReviewIssue(Ingredient(name: 'so', quantity: q)),
          QuantityReviewIssue.invalid,
        );
      }
    },
  );
  test(
    'pozitivan konačan broj, decimalni zarez i razlomak nisu upozorenje',
    () {
      for (final raw in [0.001, 250, '0,5', '1/2']) {
        expect(
          quantityReviewIssue(
            Ingredient.fromJson({'name': 'brašno', 'quantity': raw}),
          ),
          isNull,
        );
      }
    },
  );
}
