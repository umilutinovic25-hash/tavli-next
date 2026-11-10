import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/domain/pan_converter.dart';

void main() {
  test('20 cm u 30 cm iste visine daje faktor 2,25', () {
    const a = BakingPan(shape: PanShape.round, width: 20, height: 4);
    const b = BakingPan(shape: PanShape.round, width: 30, height: 4);
    expect(panScale(a, b), closeTo(2.25, 1e-10));
  });
  test('pravougaoni kalupi i visina daju poznat faktor', () {
    const a = BakingPan(
      shape: PanShape.rectangular,
      width: 20,
      length: 30,
      height: 2,
    );
    const b = BakingPan(
      shape: PanShape.rectangular,
      width: 10,
      length: 30,
      height: 4,
    );
    expect(panScale(a, b), closeTo(1, 1e-10));
  });
  test('nula, negativne, nedostajuće i nekonačne dimenzije se odbijaju', () {
    const good = BakingPan(shape: PanShape.round, width: 20, height: 4);
    for (final bad in [
      const BakingPan(shape: PanShape.round, width: 0, height: 1),
      const BakingPan(shape: PanShape.round, width: double.infinity, height: 1),
      const BakingPan(shape: PanShape.round, width: 1, height: -1),
      const BakingPan(shape: PanShape.rectangular, width: 1, height: 1),
    ]) {
      expect(() => panScale(good, bad), throwsFormatException);
    }
  });
}
