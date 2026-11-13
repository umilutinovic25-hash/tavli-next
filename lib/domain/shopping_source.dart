import 'dart:convert';

import 'food.dart';
import 'plan_calendar.dart';
import 'recipe.dart';
import 'shopping_demand.dart';
import 'step_links.dart';

/// Odakle dolazi potražnja u kupovini.
enum ShoppingSourceKind {
  /// Planirani obrok: recept i porcije čita iz unosa plana.
  planEntry,

  /// Samostalna priprema recepta bez plana: ima svoj zamrznut recept.
  recipePreparation,
}

/// Recept kakav je odobren za obrok ili pripremu. Izmena recepta u
/// biblioteci ga ne menja; sažetak može biti bez koraka.
class RecipeSnapshot {
  const RecipeSnapshot({
    required this.title,
    required this.baseServings,
    required this.ingredients,
    this.steps = const [],
    this.prepMinutes,
    this.imagePath,
    this.dictionaryVersion = 0,
    this.stepUses = const [],
    this.activeMinutes,
    this.totalMinutes,
    this.conversions = const {},
  });

  factory RecipeSnapshot.fromRecipe(Recipe r) => RecipeSnapshot(
    title: r.title,
    baseServings: r.servings,
    ingredients: r.ingredients,
    steps: r.steps,
    prepMinutes: r.prepMinutes,
    imagePath: r.imagePath,
    stepUses: r.stepUses,
    activeMinutes: r.activeMinutes,
    totalMinutes: r.totalMinutes,
  );

  /// Čita oblik iz [toJson]. Baca [FormatException] na pokvaren zapis.
  factory RecipeSnapshot.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) throw const FormatException('Obrok nema naziv');
    final servings = json['servings'];
    if (servings is! int || servings < minServings) {
      throw const FormatException('Obrok nema porcije');
    }
    final ingredients = json['ingredients'] ?? const <Object?>[];
    final steps = json['steps'] ?? const <Object?>[];
    if (ingredients is! List || steps is! List) {
      throw const FormatException('Pokvaren zapis obroka');
    }
    return RecipeSnapshot(
      title: title,
      baseServings: servings,
      ingredients: [
        for (final i in ingredients)
          Ingredient.fromJson(i as Map<String, dynamic>),
      ],
      steps: [for (final s in steps) s.toString()],
      stepUses: readStepLinks([
        for (final s in steps) s.toString(),
      ], json['stepLinks']),
      prepMinutes: json['prepMinutes'] as int?,
      imagePath: json['imagePath'] as String?,
      dictionaryVersion: json['dictionaryVersion'] as int? ?? 0,
      activeMinutes: json['activeMinutes'] as int?,
      totalMinutes: json['totalMinutes'] as int?,
      conversions: _readConversions(json['conversions']),
    );
  }

  final int dictionaryVersion;

  /// Konverzije namirnica zamrznute pri potvrdi (v2, 036), po
  /// `conversionKey`; kasnija ispravka kataloga ih ne menja.
  final Map<String, FrozenConversion> conversions;
  final String title;
  final int baseServings;
  final List<Ingredient> ingredients;
  final List<String> steps;
  final int? prepMinutes;
  final String? imagePath;

  /// Sastojci po koracima, poravnati sa [steps].
  final List<List<StepUse>> stepUses;

  /// Potvrđeno aktivno i ukupno vreme (minuti) u trenutku planiranja.
  final int? activeMinutes;
  final int? totalMinutes;

  /// Isti recept sa drugim sastojcima (npr. samo onima koji fale).
  RecipeSnapshot withIngredients(List<Ingredient> ingredients) =>
      RecipeSnapshot(
        title: title,
        baseServings: baseServings,
        ingredients: ingredients,
        steps: steps,
        prepMinutes: prepMinutes,
        imagePath: imagePath,
        dictionaryVersion: dictionaryVersion,
        stepUses: stepUses,
        activeMinutes: activeMinutes,
        totalMinutes: totalMinutes,
        conversions: conversions,
      );

  /// Version is frozen at approval; legacy snapshots are not rewritten.
  /// V2 (036): a missing food id is filled by an exact alias from [catalog]
  /// (a person's choice is kept) and the food conversions in use are frozen.
  RecipeSnapshot withCurrentDictionary([FoodCatalog? catalog]) {
    final confirmed = [
      for (final i in ingredients)
        i.foodId != null || catalog == null
            ? i
            : i.withFood(catalog.match(i.name)),
    ];
    final frozen = <String, FrozenConversion>{};
    for (final i in confirmed) {
      final foodId = i.foodId, unit = i.unit;
      if (catalog == null || foodId == null || unit == null) continue;
      final food = catalog.byId(foodId);
      final c = catalog.conversion(foodId, unit);
      if (food == null || c == null) continue;
      frozen[conversionKey(foodId, unit)] = (
        factorMicros: c.factorMicros,
        baseUnit: food.baseUnit.name,
      );
    }
    return RecipeSnapshot(
      title: title,
      baseServings: baseServings,
      ingredients: confirmed,
      steps: steps,
      prepMinutes: prepMinutes,
      imagePath: imagePath,
      dictionaryVersion: 3,
      stepUses: stepUses,
      activeMinutes: activeMinutes,
      totalMinutes: totalMinutes,
      conversions: frozen,
    );
  }

  /// Isti ključevi kao recept u bazi (`Recipe.toAiJson`) i kao zapis koji
  /// migracija v5 pravi od postojećih obroka.
  Map<String, dynamic> toJson() => {
    'title': title,
    if (dictionaryVersion != 0) 'dictionaryVersion': dictionaryVersion,
    'servings': baseServings,
    'prepMinutes': prepMinutes,
    'ingredients': [for (final i in ingredients) i.toJson()],
    'steps': steps,
    'imagePath': imagePath,
    'stepLinks': ?writeStepLinks(steps, stepUses),
    'activeMinutes': ?activeMinutes,
    'totalMinutes': ?totalMinutes,
    if (conversions.isNotEmpty)
      'conversions': {
        for (final MapEntry(:key, :value) in conversions.entries)
          key: {'factorMicros': value.factorMicros, 'baseUnit': value.baseUnit},
      },
  };
}

Map<String, FrozenConversion> _readConversions(Object? json) {
  if (json == null) return const {};
  if (json is! Map<String, dynamic>) {
    throw const FormatException('Pokvarene konverzije obroka');
  }
  return {
    for (final MapEntry(:key, :value) in json.entries)
      if (value
          case {'factorMicros': final int factor, 'baseUnit': final String base}
          when factor > 0)
        key: (factorMicros: factor, baseUnit: base)
      else
        key: throw const FormatException('Pokvarena konverzija obroka'),
  };
}

/// Redosled vrsta obroka u danu (za raspodelu zalihe).
int mealOrder(String mealType) => switch (mealType) {
  'breakfast' => 0,
  'lunch' => 1,
  'dinner' => 2,
  _ => 3,
};

/// Obrok ili priprema za koju je stavka nabavke: prikazuje se uz stavku, a
/// pri kupovini se zamrzava u poreklu kupovine.
class ItemSource {
  const ItemSource({
    required this.title,
    this.kind,
    this.servings,
    this.date,
    this.mealType,
  });

  /// Čita oblik iz [toJson]; raniji zapis je samo naziv.
  factory ItemSource.fromJson(Object? json) {
    if (json is String) return ItemSource(title: json);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Pokvareno poreklo kupovine');
    }
    final date = json['date'];
    return ItemSource(
      title: (json['title'] as String?) ?? '',
      kind: ShoppingSourceKind.values.asNameMap()[json['kind']],
      servings: json['servings'] as int?,
      date: date is String ? CivilDate.parse(date) : null,
      mealType: json['mealType'] as String?,
    );
  }

  final String title;
  final ShoppingSourceKind? kind;
  final int? servings;

  /// Samo planirani obrok: dan i vrsta obroka (`MealType.name`).
  final CivilDate? date;
  final String? mealType;

  Map<String, dynamic> toJson() => {
    'title': title,
    'kind': kind?.name,
    'servings': servings,
    'date': date?.toString(),
    'mealType': mealType,
  };
}

/// Poreklo kupovine (`purchaseProvenanceJson`): izvori u trenutku kupovine.
List<ItemSource> provenanceSources(String? json) {
  if (json == null) return const [];
  try {
    final decoded = jsonDecode(json);
    final sources = decoded is Map<String, dynamic> ? decoded['sources'] : null;
    if (sources is! List) return const [];
    return [for (final s in sources) ItemSource.fromJson(s)];
  } on FormatException {
    return const [];
  }
}

String provenanceJson(List<ItemSource> sources) => jsonEncode({
  'sources': [for (final s in sources) s.toJson()],
});
