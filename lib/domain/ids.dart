import 'dart:math';

final _random = Random.secure();

/// Nov id zapisa (UUID v7, RFC 9562). Pravi ga uređaj, pa ponovljeno slanje
/// na server ne pravi duplikate. Prvih 48 bita je unix vreme u milisekundama,
/// pa id-jevi nastali u različitim milisekundama leksikografski prate vreme.
/// Unutar iste milisekunde redosled nije garantovan.
///
/// [clock] i [random] su za testove; bez njih se koristi sistemski sat i
/// kriptografski generator.
String newId({DateTime Function()? clock, Random? random}) {
  final ms = (clock ?? DateTime.now)().millisecondsSinceEpoch;
  final rnd = random ?? _random;
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  for (var i = 0; i < 6; i++) {
    b[i] = (ms >> (40 - 8 * i)) & 0xff; // 48 bita, big-endian
  }
  b[6] = (b[6] & 0x0f) | 0x70; // verzija 7
  b[8] = (b[8] & 0x3f) | 0x80; // varijanta RFC 4122
  final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
