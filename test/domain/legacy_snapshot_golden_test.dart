import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/shopping_demand.dart';
import 'package:tavli/domain/shopping_source.dart';

/// 036 SC-002: snimci odobreni pre kataloga (rečnik v0 i v1) daju iste
/// potrebe i zbirove kao pre. Ovaj test se ne menja dok se dodaje v2.
const _snapshots = <String, String>{
  'v0-jaja':
      '{"title":"Omlet","servings":4,"prepMinutes":null,"ingredients":['
      '{"name":"jaja","quantity":3.0,"unit":"kom","category":"mlečni proizvodi i jaja","note":null},'
      '{"name":"jaje","quantity":2.0,"unit":"kom","category":"mlečni proizvodi i jaja","note":null}'
      '],"steps":[],"imagePath":null}',
  'v0-luk':
      '{"title":"Sos","servings":2,"prepMinutes":null,"ingredients":['
      '{"name":"češnjak","quantity":10.0,"unit":"g","category":"voće i povrće","note":null},'
      '{"name":"beli luk","quantity":5.0,"unit":"g","category":"voće i povrće","note":null}'
      '],"steps":[],"imagePath":null}',
  'v1-luk':
      '{"title":"Sos","dictionaryVersion":1,"servings":2,"prepMinutes":null,"ingredients":['
      '{"name":"češnjak","quantity":10.0,"unit":"g","category":"voće i povrće","note":null},'
      '{"name":"beli luk","quantity":5.0,"unit":"g","category":"voće i povrće","note":null}'
      '],"steps":[],"imagePath":null}',
  'v1-brasno':
      '{"title":"Hleb","dictionaryVersion":1,"servings":2,"prepMinutes":null,"ingredients":['
      '{"name":"brašno","quantity":1.0,"unit":"kg","category":"suvi proizvodi","note":null},'
      '{"name":"Brašno","quantity":500.0,"unit":"grama","category":"suvi proizvodi","note":"T-500"}'
      '],"steps":[],"imagePath":null}',
};

/// Porcije u planu po snimku.
const _servings = {'v0-jaja': 2, 'v0-luk': 2, 'v1-luk': 2, 'v1-brasno': 2};

/// (sastojak, grupa, micros, osnovna jedinica) po snimku, redom.
const _expectedLines = {
  'v0-jaja': [
    ('jaja', 'count:kom', 1500000, 'kom'),
    ('jaje', 'count:kom', 1000000, 'kom'),
  ],
  'v0-luk': [
    ('češnjak', 'mass', 10000000, 'g'),
    ('beli luk', 'mass', 5000000, 'g'),
  ],
  'v1-luk': [('v1:beli luk', 'mass', 15000000, 'g')],
  'v1-brasno': [('v1:brašno', 'mass', 1500000000, 'g')],
};

List<DemandLine> _lines(String id) {
  final s = RecipeSnapshot.fromJson(
    jsonDecode(_snapshots[id]!) as Map<String, dynamic>,
  );
  return demandFor(
    DemandSource(
      id: id,
      baseServings: s.baseServings,
      servings: _servings[id]!,
      ingredients: s.ingredients,
      dictionaryVersion: s.dictionaryVersion,
    ),
  );
}

void main() {
  for (final id in _snapshots.keys) {
    test('$id: iste potrebe kao pre kataloga', () {
      expect([
        for (final l in _lines(id))
          (l.key.ingredient, l.key.unitGroup, l.micros, l.baseUnit),
      ], _expectedLines[id]);
    });

    test('$id: JSON snimka se ne menja posle čitanja', () {
      final json = jsonDecode(_snapshots[id]!) as Map<String, dynamic>;
      expect(RecipeSnapshot.fromJson(json).toJson(), json);
    });
  }

  test('zbirovi starih snimaka ostaju isti', () {
    final needs = summarize([for (final id in _snapshots.keys) ..._lines(id)]);
    expect(
      [
        for (final n in needs)
          (n.ingredient, n.unitGroup, n.micros, n.sourceIds.join(',')),
      ],
      [
        ('jaja', 'count:kom', 1500000, 'v0-jaja'),
        ('jaje', 'count:kom', 1000000, 'v0-jaja'),
        ('češnjak', 'mass', 10000000, 'v0-luk'),
        ('beli luk', 'mass', 5000000, 'v0-luk'),
        ('v1:beli luk', 'mass', 15000000, 'v1-luk'),
        ('v1:brašno', 'mass', 1500000000, 'v1-brasno'),
      ],
    );
  });
}
