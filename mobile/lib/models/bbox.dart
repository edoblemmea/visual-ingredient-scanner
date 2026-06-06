/// Axis-aligned bounding box in **original-image pixel** coordinates.
///
/// Doubles (not ints like the Python `bbox_xyxy` tuple) so the same type covers
/// both detector output and user-drawn manual boxes (FR7), which come from
/// fractional touch coordinates.
class BBox {
  const BBox(this.x1, this.y1, this.x2, this.y2);

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  double get width => x2 - x1;
  double get height => y2 - y1;

  factory BBox.fromList(List<num> v) =>
      BBox(v[0].toDouble(), v[1].toDouble(), v[2].toDouble(), v[3].toDouble());

  List<double> toList() => [x1, y1, x2, y2];

  BBox clampTo(int imageWidth, int imageHeight) => BBox(
        x1.clamp(0, imageWidth.toDouble()),
        y1.clamp(0, imageHeight.toDouble()),
        x2.clamp(0, imageWidth.toDouble()),
        y2.clamp(0, imageHeight.toDouble()),
      );
}
