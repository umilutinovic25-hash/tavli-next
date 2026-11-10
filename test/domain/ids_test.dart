import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/ids.dart';

final _uuidV7 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Uvek vraća iste bajtove, pa su rezultati predvidivi.
class _ZeroRandom implements Random {
  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

void main() {
  test('newId bez argumenata je UUID v7 (format, verzija, varijanta)', () {
    final id = newId();
    expect(id, matches(_uuidV7));
    expect(id[14], '7');
    expect('89ab'.contains(id[19]), isTrue);
  });

  test('newId koristi mala slova i crtice na mestima 8-4-4-4-12', () {
    final id = newId();
    expect(id.length, 36);
    expect([
      for (final i in [8, 13, 18, 23]) id[i],
    ], everyElement('-'));
    expect(id, equals(id.toLowerCase()));
  });

  test('prvih 48 bita su unix milisekunde (fiksni sat)', () {
    final ms = DateTime.utc(
      2026,
      11,
      10,
      12,
      30,
      45,
      123,
    ).millisecondsSinceEpoch;
    final id = newId(
      clock: () => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
    );
    expect(
      id.replaceAll('-', '').substring(0, 12),
      ms.toRadixString(16).padLeft(12, '0'),
    );
    expect(id, matches(_uuidV7));
  });

  test('poznati vektor: zero nasumični bitovi daju tačno očekivani id', () {
    // 0x017F22E279B0 = 1645557742000 ms
    final id = newId(
      clock: () =>
          DateTime.fromMillisecondsSinceEpoch(0x017F22E279B0, isUtc: true),
      random: _ZeroRandom(),
    );
    expect(id, '017f22e2-79b0-7000-8000-000000000000');
  });

  test('id-jevi iz različitih milisekundi leksikografski prate vreme', () {
    var now = DateTime.utc(2026).millisecondsSinceEpoch;
    final random = Random(42);
    final created = <String>[];
    final times = <int>[];
    for (var i = 0; i < 2000; i++) {
      // Korak od 1 ms do ~3 s, a ponekad isti ms (korak 0) da se proveri
      // samo da različite milisekunde daju ispravan poredak.
      final step = random.nextInt(4) == 0 ? 0 : 1 + random.nextInt(3000);
      now += step;
      times.add(now);
      created.add(
        newId(
          clock: () => DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
          random: random,
        ),
      );
    }
    for (var i = 1; i < created.length; i++) {
      if (times[i] > times[i - 1]) {
        expect(
          created[i].compareTo(created[i - 1]),
          greaterThan(0),
          reason: 'id $i (${times[i]} ms) mora biti posle id-a ${i - 1}',
        );
      } else {
        // Ista milisekunda: samo prefiks sa vremenom mora biti isti.
        expect(
          created[i].substring(0, 8) == created[i - 1].substring(0, 8),
          isTrue,
        );
      }
    }
  });

  test(
    'sortiranje stringova = sortiranje po vremenu (fiksni sat, različiti ms)',
    () {
      final base = DateTime.utc(2026, 6).millisecondsSinceEpoch;
      final offsets = [0, 1, 999, 1000, 60000, 3600000, 86400000, 2 * 86400000];
      final random = Random(7);
      final ids = [
        for (final o in offsets.reversed)
          newId(
            clock: () =>
                DateTime.fromMillisecondsSinceEpoch(base + o, isUtc: true),
            random: random,
          ),
      ];
      final sorted = [...ids]..sort();
      expect(sorted, orderedEquals(ids.reversed));
    },
  );

  test('10 000 id-jeva sa pravim izvorom nasumičnosti nema duplikata', () {
    final ids = {for (var i = 0; i < 10000; i++) newId()};
    expect(ids, hasLength(10000));
  });

  test('10 000 id-jeva u istoj milisekundi nema duplikata', () {
    final fixed = DateTime.utc(2026, 11, 10).millisecondsSinceEpoch;
    DateTime clock() => DateTime.fromMillisecondsSinceEpoch(fixed, isUtc: true);
    final ids = {for (var i = 0; i < 10000; i++) newId(clock: clock)};
    expect(ids, hasLength(10000));
    expect(ids, everyElement(matches(_uuidV7)));
  });
}
