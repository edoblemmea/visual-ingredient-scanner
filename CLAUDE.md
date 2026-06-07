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
The full CV pipeline runs on-device; only one lightweight Gemini API call (recipe generation) touches the network.

---

## Phased delivery schedule

| Phase | Deadline | Goal |
|---|---|---|
| Phase 1 | done | Project definition, repo setup, dataset plan |
| Phase 2 | 26–28 May 2026 | Working laptop pipeline + YOLO trained + preliminary metrics |
| Phase 3 | 15–17 June 2026 | Flutter mobile app, full evaluation, report, slides, demo video |
| Phase 3 presentation | 16–18 June 2026 | Live phone demo |
| Phase 4 peer eval | 22 June 2026 | Peer grading |

**Current priority (Phase 3 close-out):** the Flutter mobile app is feature-complete
through S17. Keep docs, tests, demo notes, and evaluation claims aligned with the
shipped mobile state.

---

## Five-stage CV pipeline

```
① YOLO v26m ONNX   → bounding boxes + class labels        (on-device)
② Metric3D ViT-Small → metric depth map in m              (on-device)
③ Static density table → kg/m³ per class (JSON)           (on-device, no network)
④ Pinhole + shape heuristics → weight per item in grams   (on-device Dart)
⑤ Gemini recipe call → 3 ranked recipes (JSON)            (cloud, once per scan)
```

> **Pipeline evolution — read before editing stages ②–④.** Two decisions changed
> from the original plan after empirical testing:
> 1. **Depth: Depth Anything V2-S → Metric3D ViT-Small.** The metric-indoor Depth
>    Anything checkpoint is out-of-distribution for hand-held tabletop close-ups
>    (it floors near ~1 m and its absolute scale tracks the background), so it
>    could not drive real-world size. Metric3D consumes the camera focal length
>    and returns true metric depth. See stage ②.
> 2. **Density: Gemini call → static `data/food_densities.json`.** Density can't be
>    inferred from pixels and doesn't change, so a curated static table is simpler,
>    offline, and free. Stage ⑤ is now the only cloud call.

### Stage ① — YOLO v26m ONNX

- Mobile model family: YOLO v26m ONNX, with epoch30, epoch40, and best checkpoints
  available for on-demand download; epoch40 is the default detector.
- Flutter runtime: `flutter_onnxruntime`
- Phase 2 YOLO11s artifacts are retained under `models/yolo/v11s/` for prototype
  history, but the shipped mobile app uses the v26m ONNX assets.
- Training: fine-tune on a curated food dataset assembled on Roboflow Universe
- Training environment: Google Colab, T4 GPU, PyTorch + Ultralytics

**Do not use** RF-DETR (too large, immature mobile export). Do not use YOLO11n
(accuracy too low) or YOLO11m (too large for on-device first pass).

### Stage ② — Metric3D ViT-Small (metric depth)

- Model: Metric3D v2, ViT-Small variant — [github.com/YvanYin/Metric3D](https://github.com/YvanYin/Metric3D)
- Licence: BSD-2 — permissive, deployable commercially/academically
- **Why this over Depth Anything:** Metric3D is conditioned on the camera focal
  length, so it produces *true metric* depth that holds up on hand-held tabletop
  shots. Depth Anything V2-S (metric-indoor) is room-scale OOD for close-ups — it
  floors near ~1 m and its absolute scale drifts with the background. Depth Anything
  is kept in `models/depth/` only as a selectable alternative.
- Model files in `models/depth/`:
  - `metric3d-vit-small-fp16.onnx` (~75 MB, fp16) — **default**
  - `metric3d-vit-small.onnx` (~150 MB, fp32) — use if the runtime rejects the fp16 graph
- Runtime: `onnxruntime` CPU. `pipeline/depth.py` **auto-detects** the model family
  from the ONNX outputs (Metric3D emits `predicted_normal`; Depth Anything does not)
  and applies the matching preprocessing. fp16 graphs need `ORT_DISABLE_ALL`
  optimisations — `depth.py` retries with that automatically.
- **Metric3D canonical-camera recipe** (do not change without re-validating): resize
  keeping aspect to fit 616×1064, centre-pad with the ImageNet mean, normalise in
  0–255 scale, run, un-pad, resize back, then **de-canonicalise**:
  `depth_m = raw_depth × (focal_px × resize_scale / 1000)` where `1000` is the
  canonical focal the model was trained with. The focal makes this metric — feed
  EXIF focal when available.
- No fine-tuning; use the pretrained checkpoint as-is.
- **Known limitation:** a featureless-background extreme close-up of a single object
  is scale-ambiguous for *any* monocular model — Metric3D over-estimates distance
  there. Including some scene context (counter/floor) in frame fixes it. Documented
  in `docs/phase2_report.md` §4.2.

### Stage ③ — Static density lookup (no network)

- Source: `data/food_densities.json` — curated average bulk densities (kg/m³) for all
  109 classes, including packaging weight for packaged goods.
- `pipeline/density.py` loads the table and returns a density per requested class;
  unknown classes fall back to a hardcoded `800 kg/m³`.
- **No Gemini call, no cache, no fallback file.** Density can't be inferred from
  pixels and is effectively constant per class, so a static table is simpler and
  fully offline. Edit the JSON to tune any class — keep it consistent with
  `classes.yaml`.

### Stage ④ — Weight estimation (pinhole model + shape heuristics)

```
real_width  = (bbox_width_px  / focal_length_px) × depth_m
real_height = (bbox_height_px / focal_length_px) × depth_m
```

- Uses Metric3D's metric depth **directly** — no calibration constant, no per-image
  scale anchoring, no size priors. The model output is the source of absolute scale.
- `focal_length_px`: read from EXIF `FocalLengthIn35mmFilm` converted to pixels;
  fallback = `image_width_px × 0.8`. (Now load-bearing: the same focal feeds both the
  Metric3D de-canonicalisation in stage ② and this pinhole projection.)
- Depth value: median of depth pixels inside the bounding box (clamped to [0.1, 10] m
  as a sanity guard)
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
│
├── data/
│   ├── food_densities.json    ← static bulk densities, kg/m³ (109 classes)
│   └── classes.yaml           ← unified class list (food categories)
│
├── datasets/
│   └── roboflow/              ← downloaded Roboflow exports (gitignored)
│
├── models/
│   ├── yolo/                  ← variant sub-folders (v11s/, v26m/)
│   │   ├── yolo11s.pt         ← base checkpoint (gitignored if >100 MB)
│   │   ├── food_detector.pt   ← fine-tuned checkpoint
│   │   └── v26m/...           ← shipped mobile detector checkpoints/exports
│   └── depth/
│       ├── metric3d-vit-small-fp16.onnx  ← Metric3D fp16 (~75 MB, default)
│       ├── metric3d-vit-small.onnx       ← Metric3D fp32 (~150 MB)
│       └── depth_anything_v2_small.onnx  ← alternative (selectable)
│
├── pipeline/                  ← Python CV pipeline (Phase 2 prototype)
│   ├── __init__.py
│   ├── detect.py              ← YOLO11s inference wrapper
│   ├── depth.py               ← Metric3D / Depth Anything ONNX wrapper (auto-detected)
│   ├── weight.py              ← pinhole model + shape heuristics
│   ├── density.py             ← static density lookup (food_densities.json)
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
├── mobile/                    ← Flutter app (Phase 3)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   │   ├── home_screen.dart
│   │   │   ├── scan_screen.dart
│   │   │   ├── annotate_screen.dart
│   │   │   ├── result_screen.dart
│   │   │   ├── settings_screen.dart
│   │   │   ├── model_download_screen.dart  ← first-launch / banner download UI
│   │   │   └── model_manager_screen.dart   ← per-model download / delete
│   │   ├── services/
│   │   │   ├── detector_service.dart       ← ONNX Runtime wrapper (loads from disk)
│   │   │   ├── depth_service.dart          ← ONNX Runtime wrapper (Metric3D/Depth Anything)
│   │   │   ├── weight_service.dart         ← pinhole + heuristics in Dart
│   │   │   ├── density_service.dart        ← static food_densities.json lookup
│   │   │   ├── recipe_service.dart         ← Gemini recipe call
│   │   │   └── model_download_service.dart ← HTTP streaming download + disk management
│   │   ├── state/
│   │   │   ├── scan_controller.dart
│   │   │   ├── settings_provider.dart
│   │   │   └── model_manager_provider.dart ← download state, auto-select callbacks
│   │   └── models/
│   │       ├── detection_result.dart
│   │       └── recipe.dart
│   ├── assets/
│   │   ├── model_registry.json   ← model metadata + download URLs (no .onnx files here)
│   │   ├── data/                 ← food_densities.json, labels.txt (bundled)
│   │   ├── samples/              ← bundled demo images
│   │   └── branding/             ← app icon
│   ├── android/
│   ├── ios/
│   └── pubspec.yaml
│
├── docs/
│   ├── phase1_definition.pdf  ← submitted Phase 1 document
│   ├── phase2_report.md
│   ├── phase3_prd.md
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
- API key stored in `flutter_secure_storage` (Keychain/Keystore) — never bundled in the app
- Model downloads via `http` package (streaming with progress); stored in `path_provider` app-docs dir
- Models are **not** Flutter assets — they are downloaded on demand and loaded with `fromFile()`

### Gemini API
- Only stage ⑤ (recipe generation) uses Gemini — density is now a static table (stage ③).
- Use `gemini-2.0-flash-lite` (or the current Flash Lite model string from the API reference)
- Always request JSON output; validate the response schema before use

---

## Data and classes

- Dataset sourced from Roboflow Universe; merged and augmented in a Roboflow workspace
- Class list defined in `data/classes.yaml`; keep it consistent across YOLO training config,
  `data/food_densities.json`, and shape-heuristic mappings
- Each class entry in `classes.yaml` must include: `name`, `shape_hint` (sphere/cylinder/box), `typical_density_kg_m3`
- Augmentations applied in Roboflow: horizontal flip, ±15° rotation, brightness ±20%, mosaic

---

## Evaluation targets

| Stage | Metric | Target |
|---|---|---|
| Detection | mAP50-95 on food test set | > 40 % |
| Depth | δ₁ (% pixels within 25 % of GT) | > 0.75 |
| End-to-end latency (Pixel 9 simulator / demo device) | Wall-clock from capture to CV results | < 10 s (7 s avg measured) |

---

## Known risks and mitigations

1. **ONNX operator compatibility:** validate the ONNX export on `onnxruntime` CPU before Phase 2 deadline.
   If a ViT operator fails, try INT8 quantisation (`onnxruntime.quantization`) or fall back to Chaquopy.
2. **Weight noise:** explicitly documented as a known limitation in the report; ±30 % is acceptable for recipe use.
3. **Gemini tier changes:** only recipe generation depends on Gemini; the model string is a single
   config constant. Density is fully offline (`data/food_densities.json`); a recipe outage degrades
   gracefully to "no recipes" while detection + weights still work.
4. **Monocular scale ambiguity:** Metric3D over-estimates distance for featureless-background extreme
   close-ups (no scene context to anchor scale). Mitigation: keep some counter/background in frame;
   documented as a known limitation.

---

## What NOT to do

- Do not add authentication, user accounts, or a backend server — the app is intentionally serverless
- Do not use RF-DETR; do not use Depth Anything V2-Base or V2-Large (CC-BY-NC licence issue)
- Do not fine-tune the depth model; use the pretrained Metric3D checkpoint as-is
- Do not reintroduce the Gemini density call, depth calibration constants, or food-size priors —
  density is a static table and absolute scale comes from Metric3D's metric depth directly
- Do not add ML model abstractions beyond the five pipeline stages described above
- Do not create placeholder files or stub implementations — only write code that actually runs
- Do not add comments that merely restate what the code does; only add comments for non-obvious constraints
