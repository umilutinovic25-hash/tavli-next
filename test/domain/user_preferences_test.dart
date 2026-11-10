import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/user_preferences.dart';

void main() {
  group('normalizeItems', () {
    test('seče razmake, spušta na mala slova, bez praznih i ponavljanja', () {
      expect(normalizeItems(['  Kikiriki ', 'kikiriki', '', '   ', 'Lešnik']), [
        'kikiriki',
        'lešnik',
      ]);
    });

    test('zadržava prvo pojavljivanje redosled', () {
      expect(normalizeItems(['luk', 'biber', 'LUK', 'kupus']), [
        'luk',
        'biber',
        'kupus',
      ]);
    });

    test('stavka duža od 40 znakova je greška', () {
      expect(() => normalizeItems(['a' * 41]), throwsArgumentError);
      expect(normalizeItems(['a' * 40]), ['a' * 40]);
    });

    test('više od 30 stavki je greška, a duplikati se ne broje', () {
      expect(
        () => normalizeItems([for (var i = 0; i < 31; i++) 'namirnica $i']),
        throwsArgumentError,
      );
      // 31 pojava, ali samo 30 različitih: prolazi.
      expect(
        normalizeItems([for (var i = 0; i < 31; i++) 'namirnica ${i % 30}']),
        hasLength(30),
      );
    });
  });

  group('UserPreferences', () {
    test('podrazumevano: nema unosa, dve osobe', () {
      final p = UserPreferences.defaults;
      expect(p.isEmpty, isTrue);
      expect(p.servings, 2);
      expect(p.diet, isEmpty);
    });

    test('bilo koji unos ga čini nepraznim', () {
      expect(UserPreferences(diet: const [FoodDiet.vegan]).isEmpty, isFalse);
      expect(UserPreferences(allergies: const ['orasi']).isEmpty, isFalse);
      expect(UserPreferences(dislikes: const ['pasulj']).isEmpty, isFalse);
      expect(UserPreferences(servings: 4).isEmpty, isFalse);
    });

    test('broj osoba mora biti između 1 i 20', () {
      expect(() => UserPreferences(servings: 0), throwsArgumentError);
      expect(() => UserPreferences(servings: 21), throwsArgumentError);
      expect(UserPreferences(servings: 1).servings, 1);
      expect(UserPreferences(servings: 20).servings, 20);
    });

    test('liste se normalizuju pri pravljenju', () {
      final p = UserPreferences(
        dislikes: const [' Pasulj ', 'pasulj'],
        allergies: const ['ORASI'],
      );
      expect(p.dislikes, ['pasulj']);
      expect(p.allergies, ['orasi']);
    });

    test('jednakost ne zavisi od redosleda ishrane', () {
      expect(
        UserPreferences(diet: const [FoodDiet.vegan, FoodDiet.glutenFree]),
        UserPreferences(diet: const [FoodDiet.glutenFree, FoodDiet.vegan]),
      );
    });

    test('copyWith menja samo zadato polje', () {
      final p = UserPreferences(allergies: const ['orasi'], servings: 3);
      final next = p.copyWith(servings: 5);
      expect(next.servings, 5);
      expect(next.allergies, ['orasi']);
    });
  });
}
