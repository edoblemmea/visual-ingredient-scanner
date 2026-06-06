/// The pair of models a scan should run with — resolved from settings/registry
/// and handed to the scan orchestration. Value equality lets services detect a
/// change and reload their ONNX session only when the selection actually differs.
class ModelChoice {
  const ModelChoice({required this.detectorId, required this.depthId});

  final String detectorId;
  final String depthId;

  ModelChoice copyWith({String? detectorId, String? depthId}) => ModelChoice(
        detectorId: detectorId ?? this.detectorId,
        depthId: depthId ?? this.depthId,
      );

  @override
  bool operator ==(Object other) =>
      other is ModelChoice &&
      other.detectorId == detectorId &&
      other.depthId == depthId;

  @override
  int get hashCode => Object.hash(detectorId, depthId);

  @override
  String toString() => 'ModelChoice($detectorId, $depthId)';
}
