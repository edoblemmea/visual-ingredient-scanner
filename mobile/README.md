# Foodie Lens Mobile

Flutter app for on-device ingredient detection, metric depth estimation, weight
estimation, manual correction, and recipe generation.

## Run

```bash
flutter pub get
flutter run
```

## On-Demand Model Downloads

Models are **not bundled** in the app. They are downloaded on first use from the
project's public GitHub repository and stored in the device's app-documents directory.

On first launch the home screen shows a download banner. Tapping it opens a dedicated
download screen where the user starts the download. Nothing downloads automatically.
Once a detector model and a depth model are on disk the Scan button becomes active.

Additional models can be downloaded or deleted at any time via **Settings → Manage models**.
When the currently selected model is deleted the app automatically switches to the next
available model of that type.

| Model | Size |
|---|---|
| YOLO v26m epoch40 (default detector) | ~78 MB |
| YOLO v26m epoch30 | ~78 MB |
| YOLO v26m best | ~78 MB |
| Metric3D ViT-S fp16 (default depth) | ~76 MB |
| Depth Anything V2-S metric indoor | ~101 MB (graph + weights) |

## Feature Status

| Feature | Status |
|---|---|
| On-demand model downloads with per-model progress | Done |
| Model management: download / delete individual models | Done |
| Auto-select first downloaded model of each type | Done |
| Auto-reselect on model deletion | Done |
| Camera capture and bundled sample images | Done |
| ONNX detector/depth inference off the UI thread | Done |
| Optional parallel inference (detector + depth concurrently) | Done |
| Weight estimation from depth, focal length, shape, and density | Done |
| Settings persistence, model selection, confidence threshold | Done |
| Editable density table with live recompute | Done |
| Bounding boxes on by default; depth map off by default | Done |
| Manual distance/scale correction | Done |
| Manual annotation, smart lasso boxes, relabel/remove | Done |
| Confirm ingredients, then generate recipes with one Gemini call | Done |
| Swipeable recipe view, saving, sharing, and My recipes history | Done |
| Multi-select delete in saved recipes | Done |
| S17 error/empty-state polish and scan timing | Done |

The result screen is the ingredient-confirmation step. It shows the scanned image
with boxes, the weighed items, optional scale adjustment, and then a Get recipes
button. Recipe generation happens only after that confirmation.
