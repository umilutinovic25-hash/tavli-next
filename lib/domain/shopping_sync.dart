import 'recipe.dart';

/// Ključ po kome se sastojak recepta poredi sa stavkom u kupovini.
String ingredientKey(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Šta treba promeniti u kupovini za jedan recept.
class ShoppingSyncPlan {
  const ShoppingSyncPlan({required this.toAdd, required this.toRemove});

  /// Nedostajući sastojci kojih iz ovog recepta još nema u kupovini.
  final List<Ingredient> toAdd;

  /// Ključevi stavki ovog recepta koje korisnik ipak ima (a nisu kupljene).
  final List<String> toRemove;
}

/// Stavka kupovine za poređenje: tekst, namirnica (036) i da li je kupljena.
typedef ListedItem = ({String name, String? foodId, bool bought});

/// Isti sastojak (036): po namirnici kad je obe strane imaju, inače po
/// tekstu kao pre kataloga.
bool sameIngredient(String aName, String? aFood, String bName, String? bFood) =>
    aFood != null && bFood != null
    ? aFood == bFood
    : ingredientKey(aName) == ingredientKey(bName);

/// Štiklirano = imam (ne ide u kupovinu). "Dodaj u kupovinu" dodaje samo
/// razliku: neštiklirane kojih još nema u kupovini iz ovog recepta, pa
/// ponovni klik ništa ne duplira. Stavka koju korisnik naknadno označi kao
/// "imam", a nije kupljena, izlazi iz kupovine.
ShoppingSyncPlan planRecipeShopping({
  required List<Ingredient> missing,
  required List<Ingredient> have,
  required List<ListedItem> listed,
}) {
  bool inList(Ingredient i) =>
      listed.any((l) => sameIngredient(i.name, i.foodId, l.name, l.foodId));
  final toAdd = <Ingredient>[];
  for (final i in missing) {
    if (inList(i) ||
        toAdd.any((a) => sameIngredient(i.name, i.foodId, a.name, a.foodId))) {
      continue;
    }
    toAdd.add(i);
  }
  return ShoppingSyncPlan(
    toAdd: toAdd,
    toRemove: {
      for (final i in have)
        for (final l in listed)
          if (!l.bought && sameIngredient(i.name, i.foodId, l.name, l.foodId))
            ingredientKey(l.name),
    }.toList(),
  );
}
