import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visual_ingredient_scanner/services/focal.dart';

void main() {
  test('falls back to width * 0.8 with no EXIF focal', () {
    final image = img.Image(width: 1000, height: 750);
    expect(focalPxFor(image), 800.0);
  });

  test('converts 35mm-equivalent focal to pixels', () {
    // 30 mm equiv on a 1200 px-wide image -> 30/36 * 1200 = 1000
    expect(focalPxFromFocal35mm(30, 1200), closeTo(1000.0, 1e-6));
  });
}
