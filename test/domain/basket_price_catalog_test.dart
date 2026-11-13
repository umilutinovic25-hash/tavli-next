import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/data/basket_price_catalog.dart';

import '../helpers/fake_adapter.dart';

void main() {
  test('važeći cenovnik, rok akcije i CSV navodnici', () {
    final source = Uri.parse('https://example.com/cene.csv');
    const data =
        'k;n;n;b;b;j;t;d;c;c;s;od;do;p;v\n'
        '1;Mleko;"Mleko; 1l";B;123;kom;Maxi;13-11-2026;120.00;120.00;100.00;12-11-2026;14-11-2026;20;VAZECI_CENOVNIK\n'
        '1;Mleko;Staro;B;123;kom;Maxi;01-10-2026;50.00;50.00;;;;20;MESECNI_PRESEK\n';
    final active = parsePrices(data, source, DateTime(2026, 11, 13));
    expect(active, hasLength(1));
    expect(active.single.name, 'Mleko; 1l');
    expect(active.single.offer.priceInParas, 10000);
    expect(active.single.offer.source, source);
    final expired = parsePrices(data, source, DateTime(2026, 11, 15));
    expect(expired.single.offer.priceInParas, 12000);
    expect(parsePrices(data, source, DateTime(2026, 11, 12)), isEmpty);
  });
  test('sačuvani cenovnici rade bez mreže i čuvaju datum', () async {
    final dir = await Directory.systemTemp.createTemp('tavli-price-cache');
    addTearDown(() => dir.delete(recursive: true));
    const csv =
        'k;n;n;b;b;j;t;d;c;c;s;od;do;p;v\n'
        '1;Mleko;Mleko 1l;B;123;kom;Maxi;01-01-2020;120.00;120.00;;;;20;VAZECI_CENOVNIK\n';
    final online = Dio()
      ..httpClientAdapter = FakeAdapter([(200, csv, {}), (200, csv, {})]);
    final first = await BasketPriceCatalog(
      dio: online,
      cacheDirectory: () async => dir,
    ).fetch();
    expect(first.products.length, 2);
    final offline = Dio()
      ..httpClientAdapter = FakeAdapter([(503, '', {}), (503, '', {})]);
    final second = await BasketPriceCatalog(
      dio: offline,
      cacheDirectory: () async => dir,
    ).fetch();
    expect(second.products.length, 2);
    expect(second.failedSources, ['Delhaize', 'Europrom']);
    expect(
      second.fetchedAt.difference(first.fetchedAt).abs().inSeconds,
      lessThan(2),
    );
  });
}
