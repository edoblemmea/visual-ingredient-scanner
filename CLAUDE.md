# CLAUDE.md — Visual Ingredient Scanner

This file is the authoritative guide for any Claude session working in this repository.
Read it fully before making any changes. Follow every constraint and preference recorded here.

---

## Project identity

**Name:** Visual Ingredient Scanner with Recipe Generation
**Course:** Computer Vision · Master MEI FIB · UPC · Spring 2026
**Team:** Pol Plana, Emma Nájera, Houda El Fezzak
**Type:** Productivity — deployable end-to-end mobile pipeline

The app lets a user point a phone camera at a fridge or kitchen counter, tap once, and receive
a list of detected ingredients with estimated weights and three ranked recipe suggestions.
The full CV pipeline runs on-device; only two lightweight Gemini API calls touch the network.

---

## Phased delivery schedule

| Phase | Deadline | Goal |
|---|---|---|
| Phase 1 | done | Project definition, repo setup, dataset plan |
| Phase 2 | 26–28 May 2026 | Working laptop pipeline + YOLO trained + preliminary metrics |
| Phase 3 | 15–17 June 2026 | Flutter mobile app, full evaluation, report, slides, demo video |
| Phase 3 presentation | 16–18 June 2026 | Live phone demo |
| Phase 4 peer eval | 22 June 2026 | Peer grading |

**Current priority (Phase 2):** fine-tune YOLO11s, export Depth Anything V2-S to ONNX,
implement weight estimation in Python, build a Gradio laptop prototype end-to-end.

---

## Five-stage CV pipeline

```
① YOLO11s          → bounding boxes + class labels        (on-device)
② Depth Anything V2-S (metric indoor) → depth map in m   (on-device)
③ Gemini density call → kg/m³ per class (JSON, cached)    (cloud, once per class)
④ Pinhole + shape heuristics → weight per item in grams   (on-device Dart)
⑤ Gemini recipe call → 3 ranked recipes (JSON)            (cloud, once per scan)
```

### Stage ① — YOLO11s

- Model family: Ultralytics YOLO11, small variant (YOLO11s)
- ~9.4 M params, ~20 MB after INT8 quantisation, 47.0 mAP50-95 on COCO
- Export targets: TFLite (Android) via `ultralytics export format=tflite int8=True`,
  CoreML (iOS) via `ultralytics export format=coreml`
- Flutter plugin: `tflite_flutter`
- Training: fine-tune on a curated food dataset assembled on Roboflow Universe
- Training environment: Google Colab, T4 GPU, PyTorch + Ultralytics

**Do not use** RF-DETR (too large, immature mobile export). Do not use YOLO11n
(accuracy too low) or YOLO11m (too large for on-device first pass).

### Stage ② — Depth Anything V2-S (metric indoor)

- Checkpoint: `depth-anything/Depth-Anything-V2-Small` (metric, Hypersim fine-tune)
- Licence: Apache 2.0 — the only variant deployable commercially/academically
- **Do not use** V2-Base or V2-Large (CC-BY-NC, cannot deploy)
- Export: ONNX via `torch.onnx.export`, validated with `onnxruntime` on CPU
- Flutter plugin: `onnxruntime_flutter`
- Model file lives at `models/depth/depth_anything_v2_small.onnx`
- No fine-tuning; use the pretrained metric-indoor checkpoint as-is

### Stage ③ — Gemini density lookup

- Model: `gemini-2.0-flash-lite` (or current equivalent Flash Lite alias)
- Called **once per scan** for any class whose density is not cached locally
- Prompt template (batch all unseen classes):

  ```
  Return only a JSON object mapping each food class name to its average bulk density
  in kg/m³. Classes: {class_list}. Include packaging weight for packaged goods.
  No explanation, only JSON.
  ```

- Cache responses in `assets/density_cache.json` (Flutter) or `data/density_cache.json`
  (Python prototype); never re-query for a cached class
- If Gemini is unavailable, fall back to `data/density_fallback.json` (static table of ~50 common foods)

### Stage ④ — Weight estimation (pinhole model + shape heuristics)

```
real_width  = (bbox_width_px  / focal_length_px) × depth_m
real_height = (bbox_height_px / focal_length_px) × depth_m
```

- `focal_length_px`: read from EXIF `FocalLengthIn35mmFilm` converted to pixels;
  fallback = `image_width_px × 0.8`
- Depth value: median of depth pixels inside the bounding box
- Shape heuristics (volume from bbox dimensions):
  - **Sphere** (apple, orange, tomato, lemon, lime, peach, plum): `V = (4/3)π(d/2)³`  where `d = min(real_width, real_height)`
  - **Cylinder** (carrot, cucumber, zucchini, bottle, can): `V = π(r)²h` where `r = real_width/2`, `h = real_height`
  - **Box** (packaged goods, carton, jar, box): `V = real_width × real_height × depth_m × 0.5`
    (0.5 factor accounts for the bbox being a 2-D projection of a 3-D object)
- `weight_g = volume_m³ × density_kg_m3 × 1000`
- Target accuracy: ±30 % (sufficient for recipe-quantity guidance)

### Stage ⑤ — Recipe generation

- Model: `gemini-2.0-flash-lite`
- Called once per scan after weight estimation
- Returns a JSON array of 3 recipe objects:
  ```json
  [
    {
      "name": "Recipe name",
      "ingredients_used": ["tomato 200g", "onion 100g"],
      "steps": ["Step 1", "Step 2"],
      "servings": 2
    }
  ]
  ```
- Pass detected ingredients + estimated weights in the prompt; instruct the model
  to adapt suggestions to the available quantities

---

## Repository layout

```
visual-ingredient-scanner/
├── CLAUDE.md                  ← this file
├── README.md
├── .gitignore
├── requirements.txt           ← Python (training + prototype)
├── pubspec.yaml               ← Flutter (mobile app)
│
├── data/
│   ├── density_cache.json     ← runtime density cache (auto-updated)
│   ├── density_fallback.json  ← static fallback densities (~50 classes)
│   └── classes.yaml           ← unified class list (food categories)
│
├── datasets/
│   └── roboflow/              ← downloaded Roboflow exports (gitignored)
│
├── models/
│   ├── yolo/
│   │   ├── yolo11s.pt         ← base checkpoint (gitignored if >100 MB)
│   │   ├── food_detector.pt   ← fine-tuned checkpoint
│   │   ├── food_detector.tflite  ← INT8 export for Android
│   │   └── food_detector.mlmodel ← CoreML export for iOS
│   └── depth/
│       ├── depth_anything_v2_small.onnx
│       └── depth_anything_v2_small.onnx.data
│
├── pipeline/                  ← Python CV pipeline (Phase 2 prototype)
│   ├── __init__.py
│   ├── detect.py              ← YOLO11s inference wrapper
│   ├── depth.py               ← Depth Anything V2-S ONNX inference wrapper
│   ├── weight.py              ← pinhole model + shape heuristics
│   ├── density.py             ← Gemini density API + local cache
│   ├── recipe.py              ← Gemini recipe generation API
│   └── pipeline.py            ← orchestrates all stages end-to-end
│
├── training/
│   ├── train_yolo.py          ← YOLO11s fine-tuning script (runs on Colab)
│   ├── export_yolo.py         ← export to TFLite + CoreML
│   └── export_depth_onnx.py   ← export Depth Anything V2-S to ONNX
│
├── prototype/
│   └── app.py                 ← Gradio laptop demo (Phase 2 deliverable)
│
├── evaluation/
│   ├── eval_detection.py      ← per-class mAP on held-out test set
│   ├── eval_depth.py          ← δ₁ accuracy on indoor scenes
│   └── eval_weight.py         ← weight estimation error analysis (MAE, MAPE)
│
├── mobile/                    ← Flutter app (Phase 3)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   │   ├── scan_screen.dart
│   │   │   └── result_screen.dart
│   │   ├── services/
│   │   │   ├── detector_service.dart   ← tflite_flutter wrapper
│   │   │   ├── depth_service.dart      ← onnxruntime_flutter wrapper
│   │   │   ├── weight_service.dart     ← pinhole + heuristics in Dart
│   │   │   ├── density_service.dart    ← Gemini density call + cache
│   │   │   └── recipe_service.dart     ← Gemini recipe call
│   │   └── models/
│   │       ├── detection_result.dart
│   │       └── recipe.dart
│   ├── assets/
│   │   ├── models/
│   │   │   ├── food_detector.tflite
│   │   │   └── depth_anything_v2_small.onnx
│   │   └── density_cache.json
│   ├── android/
│   ├── ios/
│   └── pubspec.yaml
│
├── docs/
│   ├── phase1_definition.pdf  ← submitted Phase 1 document
│   ├── phase2_report.md
│   └── phase3_report.md
│
└── notebooks/
    ├── dataset_exploration.ipynb
    └── pipeline_demo.ipynb
```

---

## Language and tooling conventions

### Python (pipeline, training, evaluation)
- Python 3.11 inside the `venv/` virtual environment
- Formatter: `black`; linter: `ruff`; type hints required on all function signatures
- Key dependencies: `ultralytics`, `onnxruntime`, `torch`, `Pillow`, `numpy`, `google-generativeai`, `gradio`
- All scripts must be runnable from the repo root: `python -m pipeline.detect --image path/to/img.jpg`
- Do not commit model weights > 100 MB to git; add to `.gitignore` and document download instructions
- Colab training scripts: include a `!pip install` cell at the top so they run standalone

### Dart / Flutter (mobile app)
- Flutter stable channel, Dart 3.x
- Inference on a background `Isolate` — never block the UI thread
- State management: `provider` or plain `ChangeNotifier` (no Riverpod/Bloc — keep it simple)
- Gemini calls via `google_generative_ai` Dart package
- API key stored in `.env` (gitignored), loaded via `flutter_dotenv`

### Gemini API
- Use `gemini-2.0-flash-lite` (or the current Flash Lite model string from the API reference)
- Always request JSON output; validate the response schema before use
- Density call: batch all new classes in one call; cache immediately
- Never call Gemini for classes already in the local cache

---

## Data and classes

- Dataset sourced from Roboflow Universe; merged and augmented in a Roboflow workspace
- Class list defined in `data/classes.yaml`; keep it consistent across YOLO training config,
  Gemini prompts, and shape-heuristic mappings
- Each class entry in `classes.yaml` must include: `name`, `shape_hint` (sphere/cylinder/box), `typical_density_kg_m3`
- Augmentations applied in Roboflow: horizontal flip, ±15° rotation, brightness ±20%, mosaic

---

## Evaluation targets

| Stage | Metric | Target |
|---|---|---|
| Detection | mAP50-95 on food test set | > 40 % |
| Depth | δ₁ (% pixels within 25 % of GT) | > 0.75 |
| Weight estimation | MAPE on held-out items | < 35 % |
| End-to-end latency (phone) | Wall-clock from capture to results | < 5 s |

---

## Known risks and mitigations

1. **ONNX operator compatibility:** validate the ONNX export on `onnxruntime` CPU before Phase 2 deadline.
   If a ViT operator fails, try INT8 quantisation (`onnxruntime.quantization`) or fall back to Chaquopy.
2. **Weight noise:** explicitly documented as a known limitation in the report; ±30 % is acceptable for recipe use.
3. **Gemini tier changes:** model string is a single config constant; fallback = local `density_fallback.json`
   + offline SQLite recipe corpus.

---

## What NOT to do

- Do not add authentication, user accounts, or a backend server — the app is intentionally serverless
- Do not use RF-DETR; do not use Depth Anything V2-Base or V2-Large (licence issue)
- Do not fine-tune Depth Anything V2-S; use the pretrained metric-indoor checkpoint as-is
- Do not add ML model abstractions beyond the five pipeline stages described above
- Do not create placeholder files or stub implementations — only write code that actually runs
- Do not add comments that merely restate what the code does; only add comments for non-obvious constraints
