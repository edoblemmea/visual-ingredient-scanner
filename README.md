# Visual Ingredient Scanner with Recipe Generation

> Computer Vision · Master MEI FIB · UPC · Spring 2026
> Team: Pol Plana · Emma Nájera · Houda El Fezzak

Point a phone camera at a fridge or kitchen counter, scan once, and get a list of detected ingredients with estimated weights and three ranked recipe suggestions. The mobile app also supports manual item annotation, relabelling, density overrides, distance/scale correction, and optional developer visualisations.

---

## How it works

```
Camera frame
     │
     ▼
① YOLO v26m ONNX ───────► bounding boxes + class labels   (on-device, ~78 MB)
     │
     ▼
② Metric3D ViT-Small ───► metric depth map in metres      (on-device, ~75 MB fp16 ONNX)
     │
     ├── ③ Static density table ──► kg/m³ per class         (on-device, data/food_densities.json)
     │
     ▼
④ Pinhole model + shape heuristics ──► weight per item (g) (on-device)
     │
     ▼
⑤ Gemini recipe call ──────────────► 3 ranked recipes JSON  (cloud, once per scan)
```

Stages ①–④ run entirely on-device — including density lookup, which is now a static curated table rather than an API call. Only stage ⑤ (recipe generation) touches the network, with a single Gemini call per scan when an API key is configured.

**Why Metric3D?** Absolute distance is what turns bounding-box pixels into real-world size. Earlier we used Depth Anything V2-S (metric-indoor), but that checkpoint was trained on room-scale scenes and is out-of-distribution for hand-held tabletop close-ups — it floors out around ~1 m and its absolute scale drifts with the background. Metric3D instead consumes the camera's **focal length** (from EXIF, or an `image_width × 0.8` fallback) through a canonical-camera transform, recovering true metric depth with no per-image calibration and no reference object. See [docs/phase2_report.md](docs/phase2_report.md) §4.2 for the full comparison and the one remaining limitation (featureless-background extreme close-ups).

---

## Project structure

```
visual-ingredient-scanner/
├── CLAUDE.md                     ← full project guide for Claude sessions
├── README.md                     ← this file
├── requirements.txt              ← Python deps (training + prototype)
│
├── data/
│   ├── classes.yaml              ← unified food class list
│   └── food_densities.json       ← static bulk densities, kg/m³ (109 classes)
│
├── datasets/
│   └── roboflow/                 ← Roboflow exports (gitignored)
│
├── models/
│   ├── yolo/                     ← variant sub-folders (v11s/, v26m/)
│   │   ├── food_detector.pt      ← fine-tuned YOLO11s checkpoint
│   │   ├── food_detector.tflite  ← INT8 TFLite export (Android)
│   │   └── food_detector.mlmodel ← CoreML export (iOS)
│   └── depth/
│       ├── metric3d-vit-small-fp16.onnx  ← Metric3D, fp16 (~75 MB, default)
│       ├── metric3d-vit-small.onnx       ← Metric3D, fp32 (~150 MB)
│       └── depth_anything_v2_small.onnx  ← alternative (selectable)
│
├── pipeline/                     ← Python CV pipeline (Phase 2)
│   ├── detect.py                 ← YOLO11s inference wrapper
│   ├── depth.py                  ← Metric3D / Depth Anything ONNX wrapper (auto-detected)
│   ├── weight.py                 ← pinhole model + shape heuristics
│   ├── density.py                ← static density lookup (food_densities.json)
│   ├── recipe.py                 ← Gemini recipe generation
│   └── pipeline.py               ← end-to-end orchestration
│
├── training/
│   ├── train_yolo.py             ← YOLO11s fine-tuning (Google Colab)
│   ├── export_yolo.py            ← export to TFLite + CoreML
│   └── export_depth_onnx.py      ← export Depth Anything V2-S to ONNX
│
├── prototype/
│   └── app.py                    ← Gradio laptop demo (Phase 2 deliverable)
│
├── mobile/                       ← Flutter app (Phase 3)
│   ├── pubspec.yaml              ← Flutter deps
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   │   ├── scan_screen.dart
│   │   │   ├── annotate_screen.dart
│   │   │   └── result_screen.dart
│   │   └── services/
│   │       ├── detector_service.dart
│   │       ├── depth_service.dart
│   │       ├── weight_service.dart
│   │       ├── density_service.dart
│   │       └── recipe_service.dart
│   └── assets/
│       ├── models/
│       └── food_densities.json
│
├── docs/
│   ├── phase1_definition.pdf
│   ├── phase2_report.md
│   ├── phase3_prd.md
│   └── phase3_report.md
│
└── notebooks/
    ├── dataset_exploration.ipynb
    └── pipeline_demo.ipynb
```

---

## Setup

### Python environment (pipeline, training, evaluation)

```bash
python -m venv venv
# Windows
venv\Scripts\activate
# macOS / Linux
source venv/bin/activate

pip install -r requirements.txt
```

Run the full pipeline on a single image:

```bash
python -m pipeline.pipeline --image path/to/fridge.jpg
```

Launch the Gradio prototype:

```bash
python prototype/app.py
```

### Environment variables

Create a `.env` file at the repo root (gitignored):

```
GEMINI_API_KEY=your_key_here
```

### Flutter app

```bash
cd mobile
flutter pub get
flutter run
```

#### Bundled models

The app compiles its CV models in as Flutter assets under `mobile/assets/`.

| Asset | Size | In git? |
|---|---|---|
| `assets/models/epoch30.onnx` (YOLO v26m) | ~78 MB | ✅ committed |
| `assets/models/epoch40.onnx` (YOLO v26m, default detector) | ~78 MB | ✅ committed |
| `assets/models/food_detector_v26m_best.onnx` (YOLO v26m best) | ~78 MB | ✅ committed |
| `assets/models/metric3d-vit-small-fp16.onnx` (default depth) | ~76 MB | ✅ committed |
| `assets/models/depth_anything_v2_small.onnx` (Depth Anything V2-S metric indoor graph) | ~2 MB | ✅ committed |
| `assets/models/depth_anything_v2_small.onnx.data` (Depth Anything V2-S metric indoor weights) | ~99 MB | ✅ committed |

#### Current mobile features

- On-device detection, depth, density lookup, and weight estimation.
- Camera capture plus bundled sample-image fallback.
- Editable density table, model selection, confidence threshold, Gemini key/model settings.
- Manual scale correction using a known camera-to-object distance.
- Manual annotation, smart lasso boxes, relabelling, and removing detections.
- Optional developer views for bounding boxes, depth maps, scan timing, detection counts, and active scale.
- Graceful error, empty-result, and no-recipe fallback states.

#### Run on an Android emulator

Requires Android Studio with the Android SDK + an AVD (virtual device) installed. List the
emulators Flutter can see, launch one, confirm it's connected, then run the app:

```bash
# 1. List available emulators (AVDs)
flutter emulators
# e.g. ->  Pixel_9_Pro • Pixel 9 Pro • Google • android

# 2. Launch one by its id (creates a default Pixel AVD if you have none:
#    flutter emulators --create  then re-list)
flutter emulators --launch Pixel_9_Pro

# 3. Wait for it to boot, then confirm the device is connected
flutter devices            # should now list e.g. sdk gphone64 arm64 (emulator-5554)

# 4. Build + install + run the app on the emulator
cd mobile
flutter pub get
flutter run -d emulator-5554     # or: flutter run -d android
```

While running, press `r` for hot reload, `R` for hot restart, and `q` to quit. The first
Android build is slow (Gradle downloads its dependencies) and the ~235 MB of bundled model
assets make the install step take a while; subsequent runs are fast.

---

## Models

| Model | Size | Where |
|---|---|---|
| YOLO11s (base) | ~40 MB | download via `ultralytics` |
| YOLO11s fine-tuned (`.pt`) | ~40 MB | `models/yolo/v11s/food_detector.pt` |
| YOLO11s INT8 TFLite | ~20 MB | `models/yolo/food_detector.tflite` |
| **Metric3D ViT-Small fp16 (ONNX)** | **~75 MB** | `models/depth/metric3d-vit-small-fp16.onnx` (**default**) |
| Metric3D ViT-Small fp32 (ONNX) | ~150 MB | `models/depth/metric3d-vit-small.onnx` |
| Depth Anything V2-S (ONNX) | ~98 MB | `models/depth/` (alternative) |

The depth stage auto-selects its preprocessing from the chosen ONNX, so any of the three can be picked from the prototype's dropdown. Model weights > 100 MB are gitignored. To set up locally:

- **Metric3D ViT-Small (ONNX):** export/download from [Metric3D](https://github.com/YvanYin/Metric3D) (BSD-2) and place the `.onnx` in `models/depth/`. The fp16 build is the default for its smaller footprint; the fp32 build is available if your runtime rejects the fp16 graph.
- **Depth Anything V2-S (ONNX):** export with `python training/export_depth_onnx.py` (metric-indoor checkpoint) into `models/depth/`.
- **YOLO11s fine-tuned:** download `food_detector.pt` from the team's shared Google Drive (link in the course submission) and place it in `models/yolo/v11s/`.

---

## Evaluation status

| Goal | Target | Current state |
|---|---|---|
| G1 latency | Capture → CV results < 10 s | 7 s average on Pixel 9 simulator |
| G2 detection | mAP50-95 > 40 % | 0.552 from `docs/results.csv` epoch 25 |

---

## Timeline

| Phase | Deadline | Status |
|---|---|---|
| Phase 1 — Definition | May 2026 | done |
| Phase 2 — 50 % checkpoint | 26–28 May 2026 | in progress |
| Phase 3 — Final delivery | 15–17 June 2026 | upcoming |
| Phase 3 — Presentation | 16–18 June 2026 | upcoming |
| Phase 4 — Peer evaluation | 22 June 2026 | upcoming |

---

## Tech stack

- **Detection:** [Ultralytics YOLO11s](https://docs.ultralytics.com/)
- **Depth:** [Metric3D ViT-Small](https://github.com/YvanYin/Metric3D) (BSD-2, intrinsics-conditioned metric depth) — Depth Anything V2-S retained as an alternative
- **Density:** static curated table (`data/food_densities.json`, 109 classes) — no API
- **LLM:** [Gemini 2.0 Flash Lite](https://ai.google.dev/) — recipe generation only
- **Training:** PyTorch + Ultralytics on Google Colab / Kaggle (T4)
- **Dataset:** [Roboflow Universe](https://universe.roboflow.com/)
- **Mobile:** Flutter 3.x with `flutter_onnxruntime` (ORT 1.22, on-device detection + depth)
- **Prototype UI:** Gradio

---

## License

Academic project — Computer Vision course, MEI FIB UPC. Source code MIT.
Model weights follow their respective upstream licences (BSD-2 for Metric3D, Apache 2.0 for Depth Anything V2-S).
