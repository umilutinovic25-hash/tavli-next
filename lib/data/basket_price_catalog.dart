import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/basket_comparison.dart';

class PriceProduct {
  const PriceProduct({required this.name, required this.offer});
  final String name;
  final BasketOffer offer;
}

class PriceCatalog {
  const PriceCatalog(this.products, this.failedSources, this.fetchedAt);
  final List<PriceProduct> products;
  final List<String> failedSources;
  final DateTime fetchedAt;
}

/// Samo fiksni javni izvori. Korisnikova korpa se ne šalje trgovcima.
class BasketPriceCatalog {
  BasketPriceCatalog({Dio? dio, Future<Directory> Function()? cacheDirectory})
    : _dio = dio ?? Dio(),
      _cacheDirectory = cacheDirectory ?? getApplicationSupportDirectory;
  final Dio _dio;
  final Future<Directory> Function() _cacheDirectory;
  static final sources = <String, Uri>{
    'Delhaize': Uri.parse(
      'https://tsmdelhaizeserbia.delhaize.rs/PublicDoc/cene_proizvoda_Delhaize.csv',
    ),
    'Europrom': Uri.parse(
      'https://api.nitsolutions.rs/api/v1/external/cenovnik/00fc017c-0f22-40c2-9e38-50f4c4a66f80.csv',
    ),
  };

  Future<PriceCatalog> fetch() async {
    final products = <PriceProduct>[];
    final failed = <String>[];
    final timestamps = <DateTime>[];
    Directory? directory;
    try {
      directory = await _cacheDirectory();
      await directory.create(recursive: true);
    } on Exception {
      directory = null;
    }
    for (final entry in sources.entries) {
      final file = directory == null
          ? null
          : File('${directory.path}/tavli_prices_${entry.key}.csv');
      List<PriceProduct>? parsed;
      DateTime? fetchedAt;
      try {
        final response = await _dio.getUri<List<int>>(
          entry.value,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 15),
          ),
        );
        final bytes = response.data;
        if (bytes == null || bytes.length > 40 * 1024 * 1024) {
          throw const FormatException();
        }
        parsed = await Isolate.run(
          () => parsePrices(
            utf8.decode(bytes, allowMalformed: false),
            entry.value,
            DateTime.now(),
          ),
        );
        if (parsed?.isEmpty ?? true) throw const FormatException();
        fetchedAt = DateTime.now();
        if (file != null) {
          try {
            final temp = File('${file.path}.tmp');
            await temp.writeAsBytes(bytes, flush: true);
            await temp.rename(file.path);
          } on Exception {
            // Rezultat ostaje dostupan za ovu sesiju i ako nema mesta za keš.
          }
        }
      } on Exception {
        failed.add(entry.key);
        try {
          if (file != null &&
              await file.exists() &&
              await file.length() <= 40 * 1024 * 1024) {
            final bytes = await file.readAsBytes();
            parsed = await Isolate.run(
              () => parsePrices(
                utf8.decode(bytes, allowMalformed: false),
                entry.value,
                DateTime.now(),
              ),
            );
            if (parsed?.isEmpty ?? true) parsed = null;
            fetchedAt = await file.lastModified();
          }
        } on Exception {
          parsed = null;
        }
      }
      if (parsed != null && fetchedAt != null) {
        products.addAll(parsed);
        timestamps.add(fetchedAt);
      }
    }
    timestamps.sort();
    return PriceCatalog(
      products,
      failed,
      timestamps.isEmpty ? DateTime.now() : timestamps.first,
    );
  }
}

/// CSV sa navodnicima i novim redovima unutar polja.
Iterable<List<String>> csvRows(String text) sync* {
  final row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && (c == ';' || c == '\n' || c == '\r')) {
      row.add(field.toString());
      field.clear();
      if (c != ';') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        yield List.of(row);
        row.clear();
      }
    } else {
      field.write(c);
    }
  }
  if (quoted) throw const FormatException('Nepotpun CSV');
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    yield row;
  }
}

DateTime? _date(String value) {
  final m = RegExp(r'^(\d{2})[.\-/](\d{2})[.\-/](\d{4})\.?$')
      .firstMatch(value.trim());
  if (m == null) return null;
  final day = int.parse(m[1]!);
  final month = int.parse(m[2]!);
  final year = int.parse(m[3]!);
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

int? _money(String value) {
  final match = RegExp(r'^(\d+)[.,](\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  return int.parse(match[1]!) * 100 + int.parse(match[2]!);
}

List<PriceProduct> parsePrices(String text, Uri source, DateTime now) {
  final result = <PriceProduct>[];
  final today = DateTime(now.year, now.month, now.day);
  for (final r in csvRows(text)) {
    if (r.length < 15 || r[14].trim().toUpperCase() != 'VAZECI_CENOVNIK') {
      continue;
    }
    final date = _date(r[7]);
    final regular = _money(r[8]);
    final barcode = r[4].trim();
    final store = r[6].trim();
    final name = r[2].trim();
    if (date == null ||
        date.isAfter(today) ||
        regular == null ||
        regular <= 0 ||
        barcode.isEmpty ||
        store.isEmpty ||
        name.isEmpty) {
      continue;
    }
    final from = _date(r[11]);
    final to = _date(r[12]);
    final reduced = _money(r[10]);
    final discountValid =
        reduced != null &&
        reduced > 0 &&
        from != null &&
        to != null &&
        !today.isBefore(from) &&
        !today.isAfter(to);
    result.add(
      PriceProduct(
        name: name,
        offer: BasketOffer(
          store: store,
          barcode: barcode,
          priceInParas: discountValid ? reduced : regular,
          priceDate: date,
          source: source,
        ),
      ),
    );
  }
  return result;
}
