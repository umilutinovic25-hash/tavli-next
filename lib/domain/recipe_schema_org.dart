import 'dart:convert';

import 'recipe.dart';
import 'recipe_format.dart';

/// Tavli kopija strukturisanih sastojaka (kategorija, količina, jedinica).
/// Druge aplikacije je zanemaruju; pri povratnom uvozu vraća recept bez
/// gubitka, ali samo dok se poklapa sa tekstom u `recipeIngredient`.
const _tavliIngredients = 'tavliIngredients';

/// Polja koja uvoz koristi; ostala se navode u izveštaju kao zanemarena.
const _usedFields = {
  '@context',
  '@type',
  '@id',
  'name',
  'recipeYield',
  'totalTime',
  'prepTime',
  'cookTime',
  'recipeIngredient',
  'ingredients',
  'recipeInstructions',
  'dateCreated',
  _tavliIngredients,
};

/// Recept u schema.org/Recipe JSON-LD obliku.
Map<String, dynamic> recipeToSchemaOrg(Recipe r) => {
  '@context': 'https://schema.org',
  '@type': 'Recipe',
  'name': r.title,
  'recipeYield': '${r.servings}',
  if (r.prepMinutes case final m?) 'totalTime': _isoDuration(m),
  'recipeIngredient': [for (final i in r.ingredients) ingredientLine(i)],
  'recipeInstructions': [
    for (final s in r.steps) {'@type': 'HowToStep', 'text': s},
  ],
  'dateCreated': r.createdAt.toUtc().toIso8601String(),
  _tavliIngredients: [for (final i in r.ingredients) i.toJson()],
};

/// Jedan recept kao objekat, više njih kao niz.
String encodeSchemaOrgRecipes(List<Recipe> recipes) =>
    const JsonEncoder.withIndent('  ').convert(
      recipes.length == 1
          ? recipeToSchemaOrg(recipes.single)
          : [for (final r in recipes) recipeToSchemaOrg(r)],
    );

/// Recept koji nije uvezen i zašto.
class SkippedRecipe {
  const SkippedRecipe(this.title, this.reason);

  final String? title;
  final String reason;
}

/// Izveštaj o uvozu: novi recepti, preskočeni i polja koja Tavli ne čuva.
class SchemaOrgImport {
  const SchemaOrgImport({
    required this.recipes,
    required this.skipped,
    required this.ignoredFields,
  });

  final List<Recipe> recipes;
  final List<SkippedRecipe> skipped;

  /// Polja uvezenih recepata koja se ne čuvaju, abecedno.
  final List<String> ignoredFields;
}

/// Čita schema.org/Recipe JSON (objekat, niz ili `@graph`). Baca
/// [FormatException] kad tekst nije JSON. Recepti čiji se naziv već nalazi
/// u [existing] ili ranije u fajlu preskaču se kao duplikati.
SchemaOrgImport parseSchemaOrgRecipes(
  String text, {
  required List<Recipe> existing,
  required String Function() newId,
  required DateTime now,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException('Fajl nije ispravan JSON');
  }
  final seen = {for (final r in existing) normalizeForSearch(r.title)};
  final inFile = <String>{};
  final recipes = <Recipe>[];
  final skipped = <SkippedRecipe>[];
  final ignored = <String>{};

  for (final node in _recipeNodes(decoded)) {
    final title = _text(node['name']);
    if (title == null) {
      skipped.add(const SkippedRecipe(null, 'nema naziv'));
      continue;
    }
    final ingredients = _ingredients(node);
    if (ingredients.isEmpty) {
      skipped.add(SkippedRecipe(title, 'nema sastojke'));
      continue;
    }
    final key = normalizeForSearch(title);
    if (seen.contains(key)) {
      skipped.add(SkippedRecipe(title, 'već postoji u receptima'));
      continue;
    }
    if (!inFile.add(key)) {
      skipped.add(SkippedRecipe(title, 'ponavlja se u fajlu'));
      continue;
    }
    ignored.addAll(node.keys.where((k) => !_usedFields.contains(k)));
    recipes.add(
      Recipe(
        id: newId(),
        title: title,
        servings: _servings(node['recipeYield']) ?? 2,
        prepMinutes: _minutes(node),
        ingredients: ingredients,
        steps: _steps(node['recipeInstructions']),
        source: RecipeSource.manual,
        createdAt: now,
      ),
    );
  }
  return SchemaOrgImport(
    recipes: recipes,
    skipped: skipped,
    ignoredFields: ignored.toList()..sort(),
  );
}

Iterable<Map<String, dynamic>> _recipeNodes(Object? node) sync* {
  if (node is List) {
    for (final n in node) {
      yield* _recipeNodes(n);
    }
  } else if (node is Map<String, dynamic>) {
    final type = node['@type'];
    final isRecipe =
        type == 'Recipe' || (type is List && type.contains('Recipe'));
    if (isRecipe) yield node;
    if (node['@graph'] case final List<dynamic> graph) {
      yield* _recipeNodes(graph);
    }
  }
}

List<Ingredient> _ingredients(Map<String, dynamic> node) {
  final raw = node['recipeIngredient'] ?? node['ingredients'];
  final lines = <String>[
    if (raw is String) ?_text(raw),
    if (raw is List)
      for (final l in raw) ?_text(l),
  ];
  final structured = _structured(node[_tavliIngredients]);
  if (structured != null &&
      structured.length == lines.length &&
      [for (final i in structured) ingredientLine(i)].join('\n') ==
          lines.join('\n')) {
    return structured;
  }
  return [for (final l in lines) parseIngredientLine(l)];
}

List<Ingredient>? _structured(Object? raw) {
  if (raw is! List) return null;
  try {
    return [
      for (final i in raw) Ingredient.fromJson(i as Map<String, dynamic>),
    ];
  } on Object {
    return null;
  }
}

const _units = {
  'g',
  'gr',
  'kg',
  'mg',
  'ml',
  'dl',
  'dcl',
  'l',
  'kašika',
  'kašike',
  'kašičica',
  'kašičice',
  'šolja',
  'šolje',
  'čaša',
  'čaše',
  'glavica',
  'glavice',
  'čen',
  'čena',
  'komad',
  'komada',
  'kom',
  'prstohvat',
  'pakovanje',
  'pakovanja',
  'kesica',
  'kesice',
  'konzerva',
  'konzerve',
  'veza',
  'tbsp',
  'tsp',
  'cup',
  'cups',
  'oz',
  'lb',
};

final _lineRe = RegExp(
  r'^(\d+\s*/\s*\d+|\d+(?:[.,]\d+)?)?\s*(.*?)(?:\s*\(([^()]*)\))?$',
);

/// "0,5 kg mleveno meso" → količina, jedinica, naziv; "(…)" na kraju je
/// napomena. Jedinica se prepoznaje samo sa spiska, ostalo je naziv.
Ingredient parseIngredientLine(String line) {
  final m = _lineRe.firstMatch(line.trim())!;
  var rest = m.group(2)!.trim();
  String? unit;
  final firstSpace = rest.indexOf(' ');
  if (m.group(1) != null && firstSpace > 0) {
    final word = rest.substring(0, firstSpace);
    if (_units.contains(word.toLowerCase())) {
      unit = word;
      rest = rest.substring(firstSpace + 1).trim();
    }
  }
  if (rest.isEmpty) return Ingredient(name: line.trim());
  return Ingredient.fromJson({
    'name': rest,
    'quantity': m.group(1)?.replaceAll(' ', ''),
    'unit': unit,
    'note': m.group(3),
  });
}

List<String> _steps(Object? raw) => switch (raw) {
  final String s => _lines(s),
  final List<dynamic> list => [for (final item in list) ..._steps(item)],
  final Map<String, dynamic> m when m['itemListElement'] != null => _steps(
    m['itemListElement'],
  ),
  final Map<String, dynamic> m => [?_text(m['text']) ?? _text(m['name'])],
  _ => const [],
};

List<String> _lines(String s) => [
  for (final l in s.split('\n'))
    if (l.trim().isNotEmpty) l.trim(),
];

int? _servings(Object? raw) => switch (raw) {
  final num n when n > 0 => n.round(),
  final String s => switch (RegExp(r'\d+').firstMatch(s)) {
    final m? when int.parse(m.group(0)!) > 0 => int.parse(m.group(0)!),
    _ => null,
  },
  final List<dynamic> list => list.map(_servings).nonNulls.firstOrNull,
  _ => null,
};

int? _minutes(Map<String, dynamic> node) {
  final total = _durationMinutes(node['totalTime']);
  if (total != null) return total;
  final prep = _durationMinutes(node['prepTime']);
  final cook = _durationMinutes(node['cookTime']);
  if (prep == null && cook == null) return null;
  return (prep ?? 0) + (cook ?? 0);
}

final _durationRe = RegExp(
  r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
);

int? _durationMinutes(Object? raw) {
  if (raw is! String) return null;
  final m = _durationRe.firstMatch(raw.trim().toUpperCase());
  if (m == null || raw.trim().length < 3) return null;
  int part(int g) => int.tryParse(m.group(g) ?? '') ?? 0;
  final seconds = double.tryParse(m.group(4) ?? '') ?? 0;
  final minutes =
      part(1) * 24 * 60 + part(2) * 60 + part(3) + (seconds / 60).round();
  return minutes > 0 ? minutes : null;
}

String _isoDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return 'PT${h > 0 ? '${h}H' : ''}${m > 0 || h == 0 ? '${m}M' : ''}';
}

String? _text(Object? v) {
  final s = v is String ? v.trim() : null;
  return (s == null || s.isEmpty) ? null : s;
}
