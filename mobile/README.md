# Foodie Lens Mobile

Flutter app for on-device ingredient detection, metric depth estimation, weight
estimation, and recipe generation.

## Run

```bash
flutter pub get
flutter run
```

## Bundled Models

Models are bundled as Flutter assets under `assets/models/`.

| Model | Asset |
|---|---|
| YOLO v26m epoch30 | `assets/models/epoch30.onnx` |
| YOLO v26m epoch40 (default) | `assets/models/epoch40.onnx` |
| YOLO v26m best | `assets/models/food_detector_v26m_best.onnx` |
| Metric3D ViT-S fp16 (default depth) | `assets/models/metric3d-vit-small-fp16.onnx` |
| Depth Anything V2-S metric indoor | `assets/models/depth_anything_v2_small.onnx` plus `.onnx.data` |

Depth Anything uses ONNX external data, so both
`depth_anything_v2_small.onnx` and `depth_anything_v2_small.onnx.data` must stay
beside each other in the asset bundle.
