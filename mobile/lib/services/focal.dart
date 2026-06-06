import 'package:image/image.dart' as img;

/// Fallback focal: `image_width × 0.8` when EXIF has no 35 mm focal length.
/// Matches `_DEFAULT_FOCAL_RATIO` in `pipeline/weight.py`.
const double kDefaultFocalRatio = 0.8;

/// EXIF tag FocalLengthIn35mmFilm.
const int _focalLengthIn35mmFilmTag = 0xA405;

/// Converts a 35 mm-equivalent focal length to pixels for an image of the given
/// width (35 mm full-frame sensor width = 36 mm).
double focalPxFromFocal35mm(double focal35mm, int imageWidth) =>
    (focal35mm / 36.0) * imageWidth;

/// Focal length in pixels, load-bearing for both the Metric3D de-canonicalisation
/// and the pinhole projection. Reads EXIF `FocalLengthIn35mmFilm`; falls back to
/// `width × 0.8`.
double focalPxFor(img.Image image) {
  try {
    final value = image.exif.exifIfd[_focalLengthIn35mmFilmTag];
    if (value != null) {
      final focal35mm = value.toDouble();
      if (focal35mm > 0) return focalPxFromFocal35mm(focal35mm, image.width);
    }
  } catch (_) {
    // Fall through to the width-ratio default.
  }
  return image.width * kDefaultFocalRatio;
}
