import 'package:flutter_test/flutter_test.dart';
import 'package:visual_ingredient_scanner/services/ort_float16.dart';

void main() {
  group('Float16.fromDouble bit patterns', () {
    test('exact IEEE-754 binary16 encodings', () {
      expect(Float16.fromDouble(0.0), 0x0000);
      expect(Float16.fromDouble(1.0), 0x3C00);
      expect(Float16.fromDouble(2.0), 0x4000);
      expect(Float16.fromDouble(0.5), 0x3800);
      expect(Float16.fromDouble(-2.0), 0xC000);
      expect(Float16.fromDouble(-1.0), 0xBC00);
    });
  });

  group('Float16.toDouble', () {
    test('decodes known patterns exactly', () {
      expect(Float16.toDouble(0x0000), 0.0);
      expect(Float16.toDouble(0x3C00), 1.0);
      expect(Float16.toDouble(0x4000), 2.0);
      expect(Float16.toDouble(0x3800), 0.5);
      expect(Float16.toDouble(0xC000), -2.0);
    });
  });

  test('round-trips representable values exactly', () {
    for (final v in [0.0, 1.0, -1.0, 2.0, 0.5, 0.25, -3.0, 10.0, 0.125]) {
      expect(Float16.toDouble(Float16.fromDouble(v)), v, reason: 'value $v');
    }
  });

  test('round-trips arbitrary values within half precision', () {
    for (final v in [0.55, 3.14159, 123.4, 0.001]) {
      final back = Float16.toDouble(Float16.fromDouble(v));
      // half precision ~ 3 decimal digits; allow ~0.1% relative error.
      expect(back, closeTo(v, v.abs() * 1e-3 + 1e-4), reason: 'value $v');
    }
  });
}
