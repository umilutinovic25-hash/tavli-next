enum RecipeSource { photo, ai, manual, url }

/// `summary` = naziv i sastojci (dovoljno za plan i listu za kupovinu),
/// `full` = i koraci pripreme.
enum DetailLevel { summary, full }

/// Kategorije redom kojim se obično ide kroz prodavnicu.
const ingredientCategories = [
  'voće i povrće',
  'meso i riba',
  'mlečni proizvodi i jaja',
  'pekara',
  'suvi proizvodi',
  'začini i sosovi',
  'konzerve i tegle',
  'zamrznuto',
  'pića',
  'ostalo',
];

class Ingredient {
  const Ingredient({
    required this.name,
    this.quantity,
    this.unit,
    this.category = 'ostalo',
    this.note,
  });

  final String name;
  final double? quantity;
  final String? unit;
  final String category;
  final String? note;

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) throw const FormatException('Sastojak bez naziva');
    final category = (json['category'] as String?)?.trim().toLowerCase();
    return Ingredient(
      name: name,
      quantity: _parseQuantity(json['quantity']),
      unit: _blankToNull(json['unit']),
      category: ingredientCategories.contains(category) ? category! : 'ostalo',
      note: _blankToNull(json['note']),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'quantity': quantity,
    'unit': unit,
    'category': category,
    'note': note,
  };
}

class Recipe {
  const Recipe({
    required this.id,
    required this.title,
    required this.servings,
    required this.ingredients,
    required this.source,
    required this.createdAt,
    this.steps = const [],
    this.prepMinutes,
    this.imagePath,
    this.answeredBy,
    this.sourceUrl,
  });

  final String id;
  final String title;
  final int servings;
  final int? prepMinutes;
  final List<Ingredient> ingredients;
  final List<String> steps;
  final RecipeSource source;
  final String? imagePath;
  final String? sourceUrl;

  /// Oznaka modela koji je napravio ili poslednji izmenio recept.
  final String? answeredBy;
  final DateTime createdAt;

  DetailLevel get detailLevel =>
      steps.isEmpty ? DetailLevel.summary : DetailLevel.full;

  /// Pravi recept iz AI odgovora. Baca [FormatException] kad odgovor
  /// ne odgovara šemi, pa router može da pita ponovo.
  factory Recipe.fromAiJson(
    Map<String, dynamic> json, {
    required String id,
    required RecipeSource source,
    required DateTime createdAt,
    String? answeredBy,
    String? imagePath,
    String? sourceUrl,
  }) {
    final title = (json['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) throw const FormatException('Recept nema naziv');
    final rawIngredients = json['ingredients'];
    if (rawIngredients is! List || rawIngredients.isEmpty) {
      throw const FormatException('Recept nema sastojke');
    }
    final rawSteps = json['steps'];
    return Recipe(
      id: id,
      title: title,
      servings: _parseQuantity(json['servings'])?.round() ?? 2,
      prepMinutes: _parseQuantity(json['prepMinutes'])?.round(),
      ingredients: [
        for (final i in rawIngredients)
          Ingredient.fromJson(i as Map<String, dynamic>),
      ],
      steps: rawSteps is List
          ? [
              for (final s in rawSteps)
                if (s.toString().trim().isNotEmpty) s.toString().trim(),
            ]
          : const [],
      source: source,
      createdAt: createdAt,
      answeredBy: answeredBy,
      imagePath: imagePath,
      sourceUrl: sourceUrl,
    );
  }

  Recipe copyWith({
    String? title,
    int? servings,
    int? prepMinutes,
    bool clearPrepMinutes = false,
    List<Ingredient>? ingredients,
    List<String>? steps,
    String? imagePath,
    String? answeredBy,
  }) => Recipe(
    id: id,
    title: title ?? this.title,
    servings: servings ?? this.servings,
    prepMinutes: clearPrepMinutes ? null : (prepMinutes ?? this.prepMinutes),
    ingredients: ingredients ?? this.ingredients,
    steps: steps ?? this.steps,
    source: source,
    imagePath: imagePath ?? this.imagePath,
    sourceUrl: sourceUrl,
    answeredBy: answeredBy ?? this.answeredBy,
    createdAt: createdAt,
  );

  /// Ceo recept za čuvanje (npr. prethodne verzije u bazi).
  Map<String, dynamic> toJson() => {
    'id': id,
    ...toAiJson(),
    'source': source.name,
    'imagePath': imagePath,
    'sourceUrl': sourceUrl,
    'answeredBy': answeredBy,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  /// Čita oblik iz [toJson]. Baca [FormatException] na pokvaren zapis.
  factory Recipe.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final source = RecipeSource.values.asNameMap()[json['source']];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (id is! String || source == null || createdAt == null) {
      throw const FormatException('Pokvaren zapis recepta');
    }
    return Recipe.fromAiJson(
      json,
      id: id,
      source: source,
      createdAt: createdAt,
      answeredBy: json['answeredBy'] as String?,
      imagePath: json['imagePath'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
    );
  }

  /// Oblik koji se šalje AI-ju pri izmenama recepta.
  Map<String, dynamic> toAiJson() => {
    'title': title,
    'servings': servings,
    'prepMinutes': prepMinutes,
    'ingredients': [for (final i in ingredients) i.toJson()],
    'steps': steps,
  };
}

double? _parseQuantity(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) {
    final s = v.trim().replaceAll(',', '.');
    final fraction = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(s);
    if (fraction != null) {
      final d = int.parse(fraction.group(2)!);
      return d == 0 ? null : int.parse(fraction.group(1)!) / d;
    }
    return double.tryParse(s);
  }
  return null;
}

String? _blankToNull(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}
