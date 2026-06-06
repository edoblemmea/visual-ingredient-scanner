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

const _androidAdaptiveForegrounds = {
  'android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png': 108,
  'android/app/src/main/res/mipmap-hdpi/ic_launcher_foreground.png': 162,
  'android/app/src/main/res/mipmap-xhdpi/ic_launcher_foreground.png': 216,
  'android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png': 324,
  'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png': 432,
};

const _androidLaunchImages = {
  'android/app/src/main/res/mipmap-mdpi/launch_image.png': 128,
  'android/app/src/main/res/mipmap-hdpi/launch_image.png': 192,
  'android/app/src/main/res/mipmap-xhdpi/launch_image.png': 256,
  'android/app/src/main/res/mipmap-xxhdpi/launch_image.png': 384,
  'android/app/src/main/res/mipmap-xxxhdpi/launch_image.png': 512,
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
  final branding = _drawIconForeground();
  final launchImage = _drawIconForeground(contentScale: 0.68);
  final foreground = _drawAdaptiveForeground();

  _writePng(
    'assets/branding/app_icon.png',
    img.copyResize(branding, width: 512),
  );

  for (final entry in {..._androidIcons, ..._iosIcons}.entries) {
    _writePng(entry.key, img.copyResize(source, width: entry.value));
  }
  for (final entry in _androidAdaptiveForegrounds.entries) {
    _writePng(entry.key, img.copyResize(foreground, width: entry.value));
  }
  for (final entry in _androidLaunchImages.entries) {
    _writePng(entry.key, img.copyResize(launchImage, width: entry.value));
  }
}

img.Image _drawIcon() {
  final image = img.Image(width: _canvas, height: _canvas);
  _paintBackground(image);
  _drawPan(image, withShadow: true);
  return _downsample(image);
}

img.Image _drawIconForeground({double contentScale = 1}) {
  final raw = img.Image(width: _canvas, height: _canvas, numChannels: 4);
  img.fill(raw, color: _rgba(0, 0, 0, 0));
  _drawPan(raw, withShadow: true);

  if (contentScale == 1) {
    return _downsample(raw);
  }

  final image = img.Image(width: _canvas, height: _canvas, numChannels: 4);
  img.fill(image, color: _rgba(0, 0, 0, 0));
  final scaled = img.copyResize(
    raw,
    width: (_canvas * contentScale).round(),
    height: (_canvas * contentScale).round(),
    interpolation: img.Interpolation.average,
  );
  img.compositeImage(
    image,
    scaled,
    dstX: (image.width - scaled.width) ~/ 2,
    dstY: (image.height - scaled.height) ~/ 2,
  );
  return _downsample(image);
}

img.Image _drawAdaptiveForeground() {
  final raw = img.Image(width: _canvas, height: _canvas, numChannels: 4);
  img.fill(raw, color: _rgba(0, 0, 0, 0));
  _drawPan(raw, withShadow: true);

  final image = img.Image(width: _canvas, height: _canvas, numChannels: 4);
  img.fill(image, color: _rgba(0, 0, 0, 0));
  final safeForeground = img.copyResize(
    raw,
    width: (_canvas * 0.56).round(),
    height: (_canvas * 0.56).round(),
    interpolation: img.Interpolation.average,
  );
  img.compositeImage(
    image,
    safeForeground,
    dstX: (image.width - safeForeground.width) ~/ 2,
    dstY: (image.height - safeForeground.height) ~/ 2,
  );
  return _downsample(image);
}

void _drawPan(img.Image image, {required bool withShadow}) {
  final s = _scale;
  final shadow = _rgba(0, 0, 0, 58);
  final panOuter = _rgb(18, 53, 52);
  final panInner = _rgb(47, 78, 74);
  final panInset = _rgb(67, 94, 88);
  final highlight = _rgba(255, 255, 255, 72);
  final handleAccent = _rgb(28, 119, 102);

  if (withShadow) {
    img.fillCircle(
      image,
      x: 442 * s,
      y: 482 * s,
      radius: 342 * s,
      color: shadow,
    );
    img.drawLine(
      image,
      x1: 606 * s,
      y1: 636 * s,
      x2: 862 * s,
      y2: 892 * s,
      color: shadow,
      thickness: 118 * s,
    );
  }

  img.drawLine(
    image,
    x1: 574 * s,
    y1: 604 * s,
    x2: 834 * s,
    y2: 864 * s,
    color: panOuter,
    thickness: 108 * s,
  );
  img.drawLine(
    image,
    x1: 603 * s,
    y1: 633 * s,
    x2: 805 * s,
    y2: 835 * s,
    color: handleAccent,
    thickness: 46 * s,
  );
  img.fillCircle(
    image,
    x: 798 * s,
    y: 828 * s,
    radius: 22 * s,
    color: _rgba(246, 239, 213, 128),
  );

  img.fillCircle(
    image,
    x: 408 * s,
    y: 420 * s,
    radius: 326 * s,
    color: panOuter,
  );
  img.fillCircle(
    image,
    x: 408 * s,
    y: 420 * s,
    radius: 260 * s,
    color: panInner,
  );
  img.fillCircle(
    image,
    x: 408 * s,
    y: 420 * s,
    radius: 218 * s,
    color: panInset,
  );
  img.fillCircle(
    image,
    x: 288 * s,
    y: 276 * s,
    radius: 54 * s,
    color: highlight,
  );

  _drawEgg(image);
  _drawTomato(image);
  _drawLeaf(image);
}

void _drawEgg(img.Image image) {
  final s = _scale;
  _fillRotatedEllipse(
    image,
    cx: 410 * s,
    cy: 428 * s,
    rx: 140 * s,
    ry: 102 * s,
    angle: -0.18,
    color: _rgb(252, 246, 219),
  );
  img.fillCircle(
    image,
    x: 452 * s,
    y: 438 * s,
    radius: 52 * s,
    color: _rgb(250, 182, 64),
  );
  img.fillCircle(
    image,
    x: 434 * s,
    y: 412 * s,
    radius: 14 * s,
    color: _rgba(255, 238, 160, 160),
  );
}

void _drawTomato(img.Image image) {
  final s = _scale;
  final tomato = _rgb(239, 86, 70);
  final stem = _rgb(69, 163, 86);

  img.fillCircle(image, x: 302 * s, y: 348 * s, radius: 62 * s, color: tomato);
  img.fillCircle(
    image,
    x: 280 * s,
    y: 326 * s,
    radius: 17 * s,
    color: _rgba(255, 221, 199, 135),
  );
  img.drawLine(
    image,
    x1: 300 * s,
    y1: 284 * s,
    x2: 318 * s,
    y2: 334 * s,
    color: stem,
    thickness: 18 * s,
  );
  img.drawLine(
    image,
    x1: 270 * s,
    y1: 334 * s,
    x2: 336 * s,
    y2: 322 * s,
    color: stem,
    thickness: 13 * s,
  );
}

void _drawLeaf(img.Image image) {
  final s = _scale;
  _fillRotatedEllipse(
    image,
    cx: 542 * s,
    cy: 514 * s,
    rx: 112 * s,
    ry: 58 * s,
    angle: -0.64,
    color: _rgb(91, 191, 111),
  );
  img.drawLine(
    image,
    x1: 474 * s,
    y1: 580 * s,
    x2: 612 * s,
    y2: 450 * s,
    color: _rgb(20, 128, 83),
    thickness: 15 * s,
  );
}

void _paintBackground(img.Image image) {
  final top = (r: 22, g: 117, b: 97);
  final bottom = (r: 94, g: 176, b: 105);

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
  img.fillCircle(
    image,
    x: 118 * s,
    y: 132 * s,
    radius: 210 * s,
    color: _rgba(255, 194, 89, 66),
  );
  img.fillCircle(
    image,
    x: 900 * s,
    y: 144 * s,
    radius: 156 * s,
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

img.Image _downsample(img.Image image) => img.copyResize(
  image,
  width: _size,
  interpolation: img.Interpolation.average,
);

void _writePng(String path, img.Image image) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
}

int _mix(int a, int b, double t) => (a + (b - a) * t).round();

img.ColorRgb8 _rgb(int r, int g, int b) => img.ColorRgb8(r, g, b);

img.ColorRgba8 _rgba(int r, int g, int b, int a) => img.ColorRgba8(r, g, b, a);
