import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/food_nutrition.dart';

void main() {
  test('čuva vrednosti na 100 g i poreklo reference', () {
    final nutrition = FoodNutrition(
      kcalPer100g: 77,
      proteinGramsPer100g: 2,
      fatGramsPer100g: 0.1,
      carbsGramsPer100g: 17,
      source: 'USDA FoodData Central',
      sourceVersion: 'SR Legacy 2018-04',
      sourceRef: 'FDC 170026',
    );

    expect(nutrition.kcalPer100g, 77);
    expect(nutrition.proteinGramsPer100g, 2);
    expect(nutrition.fatGramsPer100g, 0.1);
    expect(nutrition.carbsGramsPer100g, 17);
    expect(nutrition.source, 'USDA FoodData Central');
    expect(nutrition.sourceVersion, 'SR Legacy 2018-04');
    expect(nutrition.sourceRef, 'FDC 170026');
  });

  test('nepoznate vrednosti ostaju null, ne postaju nule', () {
    final nutrition = FoodNutrition(
      source: 'USDA FoodData Central',
      sourceVersion: 'SR Legacy 2018-04',
      sourceRef: 'FDC 170026',
    );

    expect(nutrition.kcalPer100g, isNull);
    expect(nutrition.proteinGramsPer100g, isNull);
    expect(nutrition.fatGramsPer100g, isNull);
    expect(nutrition.carbsGramsPer100g, isNull);
  });

  test('odbacuje negativne i neograničene nutritivne vrednosti', () {
    expect(
      () => FoodNutrition(
        kcalPer100g: -1,
        source: 'USDA',
        sourceVersion: '2018',
        sourceRef: 'FDC 1',
      ),
      throwsArgumentError,
    );
    expect(
      () => FoodNutrition(
        proteinGramsPer100g: double.infinity,
        source: 'USDA',
        sourceVersion: '2018',
        sourceRef: 'FDC 1',
      ),
      throwsArgumentError,
    );
  });
}
