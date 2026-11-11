import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/food.dart';
import 'package:tavli/domain/food_catalog_csv.dart';

const _header = 'id,name,category,base_unit,aliases,conversions,allergens';

String _csv(List<String> rows) => [_header, ...rows].join('\n');

Matcher _errorAt(int row, String part) => throwsA(
  isA<FormatException>().having(
    (e) => e.message,
    'message',
    allOf(contains('red $row'), contains(part)),
  ),
);

void main() {
  test('ispravan red daje namirnicu, aliase, konverzije i alergene', () {
    final entries = parseCatalogCsv(
      _csv([
        'f_jaje,jaje,mlečni proizvodi i jaja,kom,jaja|jajce,,eggs',
        'f_beli_luk,beli luk,voće i povrće,g,češnjak,čen=5000000,',
      ]),
    );
    expect(entries, hasLength(2));
    final jaje = entries.first;
    expect(jaje.food.id, 'f_jaje');
    expect(jaje.food.baseUnit, BaseUnit.kom);
    expect(jaje.food.isShared, isTrue);
    expect(jaje.aliases, ['jaje', 'jaja', 'jajce']);
    expect(jaje.allergens, ['eggs']);
    expect(jaje.conversions, isEmpty);
    final luk = entries.last;
    expect(luk.conversions.single.unit, 'čen');
    expect(luk.conversions.single.factorMicros, 5000000);
    expect(luk.conversions.single.foodId, 'f_beli_luk');
  });

  test('polje pod navodnicima sme da ima zarez; prazni redovi se preskaču', () {
    final entries = parseCatalogCsv(
      '$_header\n\n"f_so","so",začini i sosovi,g,"so za jelo",,\n',
    );
    expect(entries.single.aliases, ['so', 'so za jelo']);
    final quoted = parseCatalogCsv(
      _csv(['f_mix,mešavina,"začini i sosovi",g,"a, b",,']),
    );
    expect(quoted.single.aliases, ['mešavina', 'a, b']);
  });

  test('gustina: ml za namirnicu u g je dozvoljena', () {
    final e = parseCatalogCsv(_csv(['f_med,med,ostalo,g,,ml=1400000,'])).single;
    expect(e.conversions.single.unit, 'ml');
  });

  group('odbija', () {
    test('pogrešno zaglavlje', () {
      expect(() => parseCatalogCsv('id,name\nf_a,a'), throwsFormatException);
    });
    test('loš id', () {
      expect(
        () => parseCatalogCsv(_csv(['jaje,jaje,ostalo,kom,,,'])),
        _errorAt(2, 'id'),
      );
    });
    test('dupli id', () {
      expect(
        () => parseCatalogCsv(
          _csv(['f_a,a,ostalo,kom,,,', 'f_a,b,ostalo,kom,,,']),
        ),
        _errorAt(3, 'id'),
      );
    });
    test('dupli alias između redova (i naziv)', () {
      expect(
        () => parseCatalogCsv(
          _csv(['f_a,jaje,ostalo,kom,,,', 'f_b,jaja,ostalo,kom,jaje,,']),
        ),
        _errorAt(3, 'alias'),
      );
    });
    test('alias koji nije normalizovan', () {
      expect(
        () => parseCatalogCsv(_csv(['f_a,a,ostalo,kom,Jaja,,'])),
        _errorAt(2, 'alias'),
      );
    });
    test('naziv koji nije normalizovan', () {
      expect(
        () => parseCatalogCsv(_csv(['f_a,Jaje,ostalo,kom,,,'])),
        _errorAt(2, 'naziv'),
      );
    });
    test('nepoznata kategorija', () {
      expect(
        () => parseCatalogCsv(_csv(['f_a,a,egzotika,kom,,,'])),
        _errorAt(2, 'kategorija'),
      );
    });
    test('nepoznata jedinica', () {
      expect(
        () => parseCatalogCsv(_csv(['f_a,a,ostalo,kg,,,'])),
        _errorAt(2, 'jedinica'),
      );
    });
    test('nepoznat alergen', () {
      expect(
        () => parseCatalogCsv(_csv(['f_a,a,ostalo,kom,,,orasi'])),
        _errorAt(2, 'alergen'),
      );
    });
    for (final unit in ['g', 'kg', 'gr', 'l', 'kom']) {
      test('konverzija za već pokrivenu jedinicu $unit', () {
        expect(
          () => parseCatalogCsv(_csv(['f_a,a,ostalo,g,,$unit=1000000,'])),
          _errorAt(2, 'konverzija'),
        );
      });
    }
    test('konverzija bez pozitivnog celog faktora', () {
      expect(
        () => parseCatalogCsv(_csv(['f_a,a,ostalo,g,,čen=0,'])),
        _errorAt(2, 'konverzija'),
      );
      expect(
        () => parseCatalogCsv(_csv(['f_a,a,ostalo,g,,čen=5g,'])),
        _errorAt(2, 'konverzija'),
      );
    });
    test('pogrešan broj kolona', () {
      expect(
        () => parseCatalogCsv(_csv(['f_a,a,ostalo,kom'])),
        _errorAt(2, 'kolon'),
      );
    });
  });
}
