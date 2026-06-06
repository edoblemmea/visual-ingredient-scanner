import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _size = 1024;
const _scale = 4;
const _canvas = _size * _scale;

const _androidIcons = {
  'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
  'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
  'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
  'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
  'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
};

const _iosIcons = {
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png': 20,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png': 40,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png': 60,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png': 29,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png': 58,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png': 87,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png': 40,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png': 80,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png': 120,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png': 120,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png': 180,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png': 76,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png': 152,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png':
      167,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png':
      1024,
};

void main() {
  final source = _drawIcon();
  _writePng('assets/branding/app_icon.png', img.copyResize(source, width: 512));

  for (final entry in {..._androidIcons, ..._iosIcons}.entries) {
    _writePng(entry.key, img.copyResize(source, width: entry.value));
  }
}

img.Image _drawIcon() {
  final image = img.Image(width: _canvas, height: _canvas);
  _paintBackground(image);

  final shadow = _rgba(0, 0, 0, 46);
  final teal = _rgb(12, 75, 68);
  final cream = _rgb(250, 245, 225);
  final leaf = _rgb(89, 184, 111);
  final leafDark = _rgb(20, 128, 83);
  final tomato = _rgb(239, 88, 70);
  final tomatoStem = _rgb(37, 132, 77);
  final shine = _rgba(255, 255, 255, 110);

  final s = _scale;

  img.fillCircle(image, x: 524 * s, y: 554 * s, radius: 318 * s, color: shadow);
  img.drawLine(
    image,
    x1: 666 * s,
    y1: 692 * s,
    x2: 836 * s,
    y2: 862 * s,
    color: shadow,
    thickness: 96 * s,
  );

  img.drawLine(
    image,
    x1: 642 * s,
    y1: 664 * s,
    x2: 812 * s,
    y2: 834 * s,
    color: teal,
    thickness: 92 * s,
  );
  img.drawLine(
    image,
    x1: 646 * s,
    y1: 668 * s,
    x2: 794 * s,
    y2: 816 * s,
    color: _rgb(30, 116, 99),
    thickness: 46 * s,
  );

  img.fillCircle(image, x: 486 * s, y: 500 * s, radius: 302 * s, color: teal);
  img.fillCircle(image, x: 486 * s, y: 500 * s, radius: 246 * s, color: cream);
  img.fillCircle(image, x: 430 * s, y: 392 * s, radius: 54 * s, color: shine);

  _fillRotatedEllipse(
    image,
    cx: 476 * s,
    cy: 512 * s,
    rx: 156 * s,
    ry: 86 * s,
    angle: -0.72,
    color: leaf,
  );
  _fillRotatedEllipse(
    image,
    cx: 529 * s,
    cy: 456 * s,
    rx: 96 * s,
    ry: 56 * s,
    angle: -0.72,
    color: _rgb(117, 207, 133),
  );
  img.drawLine(
    image,
    x1: 356 * s,
    y1: 594 * s,
    x2: 601 * s,
    y2: 409 * s,
    color: leafDark,
    thickness: 18 * s,
  );
  img.drawLine(
    image,
    x1: 426 * s,
    y1: 540 * s,
    x2: 405 * s,
    y2: 468 * s,
    color: _rgb(226, 244, 205),
    thickness: 12 * s,
  );

  img.fillCircle(image, x: 638 * s, y: 340 * s, radius: 70 * s, color: tomato);
  img.fillCircle(
    image,
    x: 610 * s,
    y: 312 * s,
    radius: 20 * s,
    color: _rgba(255, 227, 204, 125),
  );
  img.drawLine(
    image,
    x1: 636 * s,
    y1: 272 * s,
    x2: 654 * s,
    y2: 318 * s,
    color: tomatoStem,
    thickness: 16 * s,
  );
  img.drawLine(
    image,
    x1: 608 * s,
    y1: 314 * s,
    x2: 676 * s,
    y2: 304 * s,
    color: tomatoStem,
    thickness: 12 * s,
  );

  return img.copyResize(
    image,
    width: _size,
    interpolation: img.Interpolation.average,
  );
}

void _paintBackground(img.Image image) {
  final top = (r: 21, g: 105, b: 91);
  final bottom = (r: 86, g: 170, b: 104);
  final accent = _rgba(255, 196, 93, 56);

  for (var y = 0; y < image.height; y++) {
    final t = y / (image.height - 1);
    final color = img.ColorRgb8(
      _mix(top.r, bottom.r, t),
      _mix(top.g, bottom.g, t),
      _mix(top.b, bottom.b, t),
    );
    for (var x = 0; x < image.width; x++) {
      image.setPixel(x, y, color);
    }
  }

  final s = _scale;
  img.fillCircle(image, x: 160 * s, y: 130 * s, radius: 210 * s, color: accent);
  img.fillCircle(
    image,
    x: 900 * s,
    y: 180 * s,
    radius: 152 * s,
    color: _rgba(255, 255, 255, 32),
  );
}

void _fillRotatedEllipse(
  img.Image image, {
  required int cx,
  required int cy,
  required int rx,
  required int ry,
  required double angle,
  required img.Color color,
}) {
  final cosA = math.cos(angle);
  final sinA = math.sin(angle);
  final radius = math.max(rx, ry);
  final left = math.max(0, cx - radius);
  final right = math.min(image.width - 1, cx + radius);
  final top = math.max(0, cy - radius);
  final bottom = math.min(image.height - 1, cy + radius);

  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final px = dx * cosA + dy * sinA;
      final py = -dx * sinA + dy * cosA;
      if ((px * px) / (rx * rx) + (py * py) / (ry * ry) <= 1) {
        image.setPixel(x, y, color);
      }
    }
  }
}

void _writePng(String path, img.Image image) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
}

int _mix(int a, int b, double t) => (a + (b - a) * t).round();

img.ColorRgb8 _rgb(int r, int g, int b) => img.ColorRgb8(r, g, b);

img.ColorRgba8 _rgba(int r, int g, int b, int a) => img.ColorRgba8(r, g, b, a);
