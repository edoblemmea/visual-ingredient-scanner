# Foodie Lens Mobile

Flutter app for on-device ingredient detection, metric depth estimation, weight
estimation, manual correction, and recipe generation.

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

## Feature Status

| Feature | Status |
|---|---|
| Camera capture and bundled sample images | Done |
| ONNX detector/depth inference off the UI thread | Done |
| Weight estimation from depth, focal length, shape, and density | Done |
| Settings persistence, model selection, confidence threshold | Done |
| Editable density table with live recompute | Done |
| Bounding boxes on by default; depth map off by default | Done |
| Manual distance/scale correction | Done |
| Manual annotation, smart lasso boxes, relabel/remove | Done |
| Confirm ingredients, then generate recipes with one Gemini call | Done |
| Swipeable recipe view, saving, and My recipes history | Done |
| S17 error/empty-state polish and scan timing | Done |

The result screen is the ingredient-confirmation step. It shows the scanned image
with boxes, the weighed items, optional scale adjustment, and then a Get recipes
button. Recipe generation happens only after that confirmation.
