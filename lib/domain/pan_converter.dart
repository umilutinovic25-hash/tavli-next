import 'dart:math' as math;

enum PanShape { round, rectangular }

class BakingPan {
  const BakingPan({
    required this.shape,
    required this.width,
    required this.height,
    this.length,
  });
  final PanShape shape;
  final double width, height;
  final double? length;

  double get volume {
    if (!width.isFinite ||
        width <= 0 ||
        !height.isFinite ||
        height <= 0 ||
        (shape == PanShape.rectangular &&
            (length == null || !length!.isFinite || length! <= 0))) {
      throw const FormatException(
        'Dimenzije moraju biti pozitivni konačni brojevi.',
      );
    }
    final area = shape == PanShape.round
        ? math.pi * width * width / 4
        : width * length!;
    final result = area * height;
    if (!result.isFinite || result <= 0) {
      throw const FormatException('Neispravna zapremina.');
    }
    return result;
  }
}

double panScale(BakingPan original, BakingPan target) {
  final factor = target.volume / original.volume;
  if (!factor.isFinite || factor <= 0) {
    throw const FormatException('Neispravan faktor.');
  }
  return factor;
}
