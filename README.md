# Visual Ingredient Scanner with Recipe Generation

> Computer Vision · Master MEI FIB · UPC · Spring 2026
> Team: Pol Plana · Emma Nájera · Houda El Fezzak

Point a phone camera at a fridge or kitchen counter, tap once, and get a list of detected ingredients with estimated weights and three ranked recipe suggestions — all powered by an on-device CV pipeline with two lightweight Gemini API calls.

---

## How it works

```
Camera frame
     │
     ▼
① YOLO11s ──────────────► bounding boxes + class labels   (on-device, ~20 MB TFLite)
     │
     ▼
② Depth Anything V2-S ──► per-pixel depth map in metres   (on-device, ~98 MB ONNX)
     │
     ├── ③ Gemini density call ──► kg/m³ per class (cached) (cloud, once per new class)
     │
     ▼
④ Pinhole model + shape heuristics ──► weight per item (g) (on-device Dart)
     │
     ▼
⑤ Gemini recipe call ──────────────► 3 ranked recipes JSON  (cloud, once per scan)
```

Stages ①②④ run entirely on-device. Stages ③⑤ make a single Gemini 2.0 Flash Lite call each; the density result is cached locally so most scans only need one network call.

---

## Project structure

```
visual-ingredient-scanner/
├── CLAUDE.md                     ← full project guide for Claude sessions
├── README.md                     ← this file
├── requirements.txt              ← Python deps (training + prototype)
├── pubspec.yaml                  ← Flutter deps (mobile app)
│
├── data/
│   ├── classes.yaml              ← unified food class list
│   ├── density_cache.json        ← runtime-updated Gemini density cache
│   └── density_fallback.json     ← static fallback densities (~50 classes)
│
├── datasets/
│   └── roboflow/                 ← Roboflow exports (gitignored)
│
├── models/
│   ├── yolo/
│   │   ├── food_detector.pt      ← fine-tuned YOLO11s checkpoint
│   │   ├── food_detector.tflite  ← INT8 TFLite export (Android)
│   │   └── food_detector.mlmodel ← CoreML export (iOS)
│   └── depth/
│       ├── depth_anything_v2_small.onnx
│       └── depth_anything_v2_small.onnx.data
│
├── pipeline/                     ← Python CV pipeline (Phase 2)
│   ├── detect.py                 ← YOLO11s inference wrapper
│   ├── depth.py                  ← Depth Anything V2-S ONNX wrapper
│   ├── weight.py                 ← pinhole model + shape heuristics
│   ├── density.py                ← Gemini density call + local cache
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
├── evaluation/
│   ├── eval_detection.py         ← per-class mAP on test set
│   ├── eval_depth.py             ← δ₁ accuracy
│   └── eval_weight.py            ← weight estimation error (MAE, MAPE)
│
├── mobile/                       ← Flutter app (Phase 3)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   │   ├── scan_screen.dart
│   │   │   └── result_screen.dart
│   │   └── services/
│   │       ├── detector_service.dart
│   │       ├── depth_service.dart
│   │       ├── weight_service.dart
│   │       ├── density_service.dart
│   │       └── recipe_service.dart
│   └── assets/
│       ├── models/
│       └── density_cache.json
│
├── docs/
│   ├── phase1_definition.pdf
│   ├── phase2_report.md
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

---

## Models

| Model | Size | Where |
|---|---|---|
| YOLO11s (base) | ~40 MB | download via `ultralytics` |
| YOLO11s fine-tuned (`.pt`) | ~40 MB | `models/yolo/food_detector.pt` |
| YOLO11s INT8 TFLite | ~20 MB | `models/yolo/food_detector.tflite` |
| Depth Anything V2-S (ONNX) | ~98 MB | `models/depth/` (already present) |

Model weights > 100 MB are gitignored. To set up locally:

- **Depth Anything V2-S (ONNX):** download `depth_anything_v2_small.onnx` from [Hugging Face](https://huggingface.co/depth-anything/Depth-Anything-V2-Small) and place it in `models/depth/`.
- **YOLO11s fine-tuned:** download `food_detector.pt` from the team's shared Google Drive (link in the course submission) and place it in `models/yolo/`.

---

## Evaluation targets

| Stage | Metric | Target |
|---|---|---|
| Detection | mAP50-95 on food test set | > 40 % |
| Depth | δ₁ accuracy | > 0.75 |
| Weight estimation | MAPE | < 35 % |
| End-to-end latency (phone) | capture → results | < 5 s |

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
- **Depth:** [Depth Anything V2 Small](https://github.com/DepthAnything/Depth-Anything-V2) (Apache 2.0, metric-indoor)
- **LLM:** [Gemini 2.0 Flash Lite](https://ai.google.dev/) — density lookup + recipe generation
- **Training:** PyTorch + Ultralytics on Google Colab (T4)
- **Dataset:** [Roboflow Universe](https://universe.roboflow.com/)
- **Mobile:** Flutter 3.x with `tflite_flutter` + `onnxruntime_flutter`
- **Prototype UI:** Gradio

---

## License

Academic project — Computer Vision course, MEI FIB UPC. Source code MIT.
Model weights follow their respective upstream licences (Apache 2.0 for Depth Anything V2-S).
