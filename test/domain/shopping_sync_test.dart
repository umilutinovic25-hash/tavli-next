import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/recipe.dart';
import 'package:tavli/domain/shopping_sync.dart';

const krompir = Ingredient(name: 'Krompir');
const meso = Ingredient(name: 'Mleveno meso');
const luk = Ingredient(name: 'Crni luk');

void main() {
  test('ključ sastojka ne zavisi od velikih slova i razmaka', () {
    expect(ingredientKey('  Crni Luk '), ingredientKey('crni luk'));
  });

  test('dodaje samo nedostajuće kojih još nema u kupovini', () {
    final plan = planRecipeShopping(
      missing: const [krompir, luk],
      have: const [meso],
      listed: const [(name: 'krompir', foodId: null, bought: false)],
    );
    expect(plan.toAdd.map((i) => i.name), ['Crni luk']);
    expect(plan.toRemove, isEmpty);
  });

  test('"imam" za stavku koju je recept već dodao (nekupljenu) je uklanja', () {
    final plan = planRecipeShopping(
      missing: const [krompir],
      have: const [meso, luk],
      listed: const [
        (name: 'krompir', foodId: null, bought: false),
        (name: 'crni luk', foodId: null, bought: false),
      ],
    );
    expect(plan.toAdd, isEmpty);
    expect(plan.toRemove, [ingredientKey('crni luk')]);
  });

  test('kupljena stavka se ne uklanja', () {
    final plan = planRecipeShopping(
      missing: const [],
      have: const [luk],
      listed: const [(name: 'crni luk', foodId: null, bought: true)],
    );
    expect(plan.toRemove, isEmpty);
  });

  test('isti sastojak dvaput u receptu se dodaje jednom', () {
    final plan = planRecipeShopping(
      missing: const [
        luk,
        Ingredient(name: 'crni luk'),
      ],
      have: const [],
      listed: const [],
    );
    expect(plan.toAdd, hasLength(1));
  });

  test('036: isti sastojak po namirnici samo kad obe strane imaju id', () {
    expect(sameIngredient('jaja', 'f_jaje', 'Jajce', 'f_jaje'), isTrue);
    expect(sameIngredient('jaja', 'f_jaje', 'jaja', 'own-1'), isFalse);
    expect(sameIngredient('jaja', 'f_jaje', ' Jaja', null), isTrue);
    expect(sameIngredient('jaja', null, 'jajce', 'f_jaje'), isFalse);
    expect(sameIngredient('jaja', null, 'JAJA', null), isTrue);
  });

  test('036: stavka „jajce“ (f_jaje) je već u kupovini za „jaja“', () {
    final plan = planRecipeShopping(
      missing: const [
        Ingredient(name: 'jaja', foodId: 'f_jaje'),
        Ingredient(name: 'jaje', foodId: 'f_jaje'),
      ],
      have: const [Ingredient(name: 'jaja', foodId: 'f_jaje')],
      listed: const [(name: 'jajce', foodId: 'f_jaje', bought: false)],
    );
    expect(plan.toAdd, isEmpty);
    expect(plan.toRemove, ['jajce']);
  });
}
