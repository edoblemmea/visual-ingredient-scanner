# Phase 2 Report — Visual Ingredient Scanner with Recipe Generation

**Course:** Computer Vision · Master MEI FIB · UPC · Spring 2026  
**Team:** Pol Plana · Emma Nájera · Houda El Fezzak  
**Deadline:** 26–28 May 2026  

---

## 1. Project Overview

The Visual Ingredient Scanner is an end-to-end application that allows a user to point a phone camera at a fridge or kitchen counter, tap once, and receive a list of detected ingredients with estimated weights and three ranked recipe suggestions.

The system is **serverless and privacy-first**: the computer vision pipeline runs entirely on-device, with only a single lightweight Gemini API call touching the network — recipe generation. Ingredient density is now a static on-device table rather than an API call.

### Pipeline

```
Camera frame
     │
     ▼
① YOLO11s ──────────────► bounding boxes + class labels    (on-device)
     │
     ▼
② Metric3D ViT-Small ───► metric depth map (metres)        (on-device)
     │
     ├── ③ Static density table ──► kg/m³ per class          (on-device, food_densities.json)
     │
     ▼
④ Pinhole model + shape heuristics ──► weight per item (g)  (on-device)
     │
     ▼
⑤ Gemini recipe call ──────────────► 3 ranked recipes JSON  (cloud, once per scan)
```

---

## 2. Phase 2 Status

| Goal | Status |
|---|---|
| Fine-tune YOLO11s on food dataset | ✅ Done — mAP50-95 = **0.554** |
| Metric depth via Metric3D ViT-Small ONNX | ✅ Done (`models/depth/`, fp16 default) |
| Implement full 5-stage Python pipeline | ✅ Done (`pipeline/`) |
| Build working Gradio laptop demo | ✅ Done (`prototype/app.py`) |
| Detection metrics (mAP) | ✅ Recorded — see §6 |
| Weight estimation functional | ✅ Produces plausible gram estimates |
| Phase 2 report | ✅ This document |

---

## 3. Dataset

### 3.1 Strategy

No single public dataset covers all target food classes with sufficient instances. We merged four complementary Roboflow Universe datasets, applying class renames to ensure consistent naming across all pipeline stages.

### 3.2 Source datasets

| Dataset | Roboflow slug | Main contribution |
|---|---|---|
| Ingredient Detection | `yasxhed/ingredient-detection-unorginazed-data` | Core fresh produce, proteins, dairy |
| Veggies and Fruits Balanced | `veggies-and-fruits-balanced-0g1ss` | Fruits, peach, lettuce, exotic fruits |
| Vegetables Dataset | `vegetables-g9p5a` | Zucchini, beet, cauliflower, celery |
| Groceries | `groceries-mts9o` | Packaged goods: milk, cereal, pasta, oil, juice |

### 3.3 Class balance and capping

After merging, dominant classes (e.g., orange: 11,085 instances) were capped at **2,000 instances** using an instance-count–based deletion strategy (images with the most instances of the overrepresented class deleted first) to prevent class imbalance from biasing training.

### 3.4 Final class list — 68 classes

**Fruits (22):** apple, avocado, banana, blackberries, blueberries, cantaloupe, coconut, fig, grapes, grapefruit, kiwi, lemon, lime, mango, orange, peach, pear, pineapple, pomegranate, raspberries, strawberries, watermelon

**Vegetables (28):** artichoke, beet, broccoli, brussels_sprouts, cabbage, carrot, cauliflower, celery, chili, corn, cucumber, eggplant, garlic, ginger, green_beans, lettuce, mushrooms, okra, onion, peas, pepper, potato, pumpkin, radish, spinach, sweet_potato, tomato, zucchini

**Proteins & dairy (12):** beef, butter, cheese, chicken, egg, fish, ham, heavy_cream, pork, shrimp, tofu, yogurt

**Pantry & packaged (21):** bread, cereal, chocolate, coffee, flour, honey, hummus, jam, juice, mayonnaise, milk, nuts, oil, pasta, rice, soda, sugar, tea, tomato_sauce, vinegar, water

### 3.5 Dataset split

| Split | Proportion | Use |
|---|---|---|
| Train | 70 % | YOLO fine-tuning |
| Validation | 20 % | Loss monitoring |
| Test | 10 % | Final mAP evaluation (held-out) |

---

## 4. Model Choices

### 4.1 Stage ① — Object Detection: YOLO11s

| Property | Value |
|---|---|
| Architecture | Ultralytics YOLO11, small variant |
| Parameters | ~9.4 M |
| Base training | COCO (80 classes) |
| Fine-tuning | Food dataset, 68 classes, 25 epochs on Kaggle T4 GPU |
| Export (Android) | INT8 TFLite via `ultralytics export format=tflite int8=True` |
| Export (iOS) | CoreML via `ultralytics export format=coreml` |

YOLO11s was chosen over YOLO11n (accuracy too low) and YOLO11m (too large for on-device). RF-DETR was excluded due to immature mobile export support.

### 4.2 Stage ② — Depth Estimation: Metric3D ViT-Small

| Property | Value |
|---|---|
| Model | Metric3D v2, ViT-Small ([YvanYin/Metric3D](https://github.com/YvanYin/Metric3D), BSD-2) |
| Files | `metric3d-vit-small-fp16.onnx` (~75 MB, **default**), `metric3d-vit-small.onnx` (~150 MB fp32) |
| Runtime | `onnxruntime` CPU (fp16 graph needs `ORT_DISABLE_ALL`, handled automatically) |
| Fine-tuning | None — pretrained checkpoint used as-is |

**Why we switched from Depth Anything V2-S.** Our first depth stage used Depth Anything V2-S (metric-indoor). Empirically it failed to produce usable *absolute* size: the checkpoint was trained on room-scale indoor scenes and is out-of-distribution for hand-held tabletop close-ups, where it **floors out around ~1 m** and its absolute scale drifts with the background. We worked around this with heuristics (scene normalisation, then a per-image rescale anchored to food-class size priors), but those were either scene-dependent or simply returned the prior — i.e. not real measurement.

**Metric3D fixes this by consuming the camera intrinsics.** It is conditioned on the focal length via a *canonical-camera transform*: the input is resized/padded into a canonical 616×1064 frame, run, and the prediction is **de-canonicalised** back to metres with the real focal length — `depth_m = raw × (focal_px × resize_scale / 1000)`. Knowing the field of view is exactly what resolves monocular scale, so Metric3D returns true metric depth with **no calibration constant and no reference object**. On a lemon photographed against a table/floor, it reads 7.5 cm at 0.50 m with no tuning.

`pipeline/depth.py` auto-detects the model family from the ONNX outputs (Metric3D emits `predicted_normal`; Depth Anything does not) and applies the matching preprocessing, so Depth Anything V2-S is retained in `models/depth/` as a selectable baseline.

**Remaining limitation (fundamental).** A featureless-background *extreme* close-up of a single object is scale-ambiguous for any monocular model — there is no pixel cue to fix metric scale. Metric3D over-estimates distance in that case too (an orange filling the frame against a flat cupboard still reads ~25 cm). Mitigation is framing: include some counter/floor context. This is an inherent monocular limit, not an implementation bug.

### 4.3 Stage ③ — Density Lookup: Static Table

- Source: `data/food_densities.json` — curated average bulk densities (kg/m³) for all **109 classes**, packaging weight included for packaged goods.
- `pipeline/density.py` loads the table and returns a density per detected class; unknown classes fall back to a hardcoded **800 kg/m³**.
- **No API, no cache, no network.** Density cannot be inferred from pixels and is effectively constant per class, so a static table is simpler, fully offline, and free — and it removes one of the two original Gemini calls. The table is the single source of truth; edit it to tune any class.

### 4.4 Stage ④ — Weight Estimation: Pinhole Model + Shape Heuristics

```
real_width  = (bbox_width_px  / focal_length_px) × depth_m
real_height = (bbox_height_px / focal_length_px) × depth_m
```

Volume estimated using per-class shape heuristics:

| Shape | Classes (examples) | Formula |
|---|---|---|
| Sphere | apple, orange, tomato, onion, egg | `V = (4/3)π(d/2)³`, d = min(w, h) |
| Cylinder | banana, carrot, cucumber, oil bottle | `V = π(w/2)²·h` |
| Box | bread, cheese, chicken, cereal box | `V = w · h · max(w,h) · 0.5` |

`depth_m` is the **median Metric3D metric depth** inside the bounding box, used directly — no calibration constant or scale anchoring. `focal_length_px` is read from EXIF `FocalLengthIn35mmFilm`, falling back to `image_width × 0.8`; the same focal feeds both this pinhole projection and the Metric3D de-canonicalisation, so it is now load-bearing.  
`weight_g = volume_m³ × density_kg_m³ × 1000`

### 4.5 Stage ⑤ — Recipe Generation: Gemini API

- Model: `gemini-1.5-flash`
- Called once per scan after weight estimation
- Input: detected ingredients + estimated weights in grams
- Output: JSON array of 3 ranked recipes (name, ingredients used, steps, servings)
- Graceful fallback message shown in UI if API is unavailable

---

## 5. Implementation

### 5.1 Repository structure

```
pipeline/
├── detect.py       YOLO11s inference wrapper
├── depth.py        Metric3D / Depth Anything ONNX wrapper (family auto-detected)
├── density.py      Static density lookup (food_densities.json)
├── weight.py       Pinhole model + shape heuristics
├── recipe.py       Gemini recipe generation
└── pipeline.py     End-to-end orchestration

training/
├── train_yolo.py              YOLO11s fine-tuning script
├── export_yolo.py             TFLite + CoreML export
└── export_depth_onnx.py       Depth Anything V2-S → ONNX (baseline)

prototype/
└── app.py          Gradio laptop demo

data/
├── classes.yaml         Class list with shape hints and densities
└── food_densities.json  Static bulk-density table, kg/m³ (109 classes)

models/
├── yolo/                          variant sub-folders (v11s/, v26m/)
│   └── food_detector.pt           Fine-tuned YOLO11s checkpoint (19.2 MB)
└── depth/
    ├── metric3d-vit-small-fp16.onnx   Metric3D fp16 (~75 MB, default)
    ├── metric3d-vit-small.onnx        Metric3D fp32 (~150 MB)
    └── depth_anything_v2_small.onnx   Baseline alternative

notebooks/
└── train_yolo_kaggle.ipynb  Kaggle training notebook (T4 GPU)
```

### 5.2 Running the demo

```bash
# Activate virtual environment
venv\Scripts\activate          # Windows
source venv/bin/activate       # macOS/Linux

# Add Gemini API key to .env
echo GEMINI_API_KEY=your_key > .env

# Launch Gradio demo
python prototype/app.py
# → open http://127.0.0.1:7860
```

### 5.3 Training

Training was executed on **Kaggle** with a T4 GPU using `notebooks/train_yolo_kaggle.ipynb`:

1. Roboflow API key loaded from Kaggle Secrets
2. Merged dataset downloaded from Roboflow (version 2)
3. YOLO11s fine-tuned for **25 epochs** (cosine LR, built-in augmentations, batch=16, imgsz=640)
4. Best checkpoint saved to `/kaggle/working/outputs/best.pt`
5. Model downloaded and placed at `models/yolo/food_detector.pt`

Total training time: **~3.26 hours** (11,754 seconds). Google Colab was initially used but abandoned due to unreliable Drive mounting and ~20 min/epoch training speed. Kaggle provided ~8 min/epoch with persistent output storage.

---

## 6. Results

### 6.1 Detection — YOLO11s mAP

| Metric | Value | Target |
|---|---|---|
| **mAP50-95** | **0.554** | > 0.40 ✅ |
| mAP50 | 0.744 | — |
| Precision | 0.745 | — |
| Recall | 0.699 | — |

The model comfortably exceeds the 40% mAP50-95 target. Training converged smoothly over 25 epochs, with both box loss and class loss decreasing consistently on validation (see training curves in `docs/Download.png`).

![Training curves](Download.png)

**Per-class highlights (selected):**

| Class | mAP50-95 (approx.) | Notes |
|---|---|---|
| ginger | 0.881 | High — very distinctive appearance |
| blackberries | 0.841 | High — unique texture |
| jam | 0.834 | High — consistent label appearance |
| orange | 0.065 | Low — few validation images after capping |
| pomegranate | 0.082 | Low — small validation set |
| garlic | 0.396 | Moderate — visually similar to onion |

Packaged goods (pasta, oil) were frequently missed — varying packaging appearance makes them harder to detect reliably with 25 training epochs.

### 6.2 Weight Estimation

Weight estimation is functional and produces plausible gram estimates. Absolute accuracy now hinges on the metric depth from Metric3D plus the shape heuristic. The table below (lemon, tomato, apple, pomegranate, onion) was recorded with the earlier Depth-Anything-plus-heuristic depth and is kept as a baseline:

| Item | Estimated weight | Typical real weight |
|---|---|---|
| lemon | ~150–250 g | ~100 g |
| onion | ~150–200 g | ~150 g |
| pomegranate | ~350–500 g | ~300 g |
| tomato | ~400–700 g | ~150–250 g |
| apple | ~500–900 g | ~180–250 g |

With Metric3D, **scenes that include background context are now measured to true scale without any tuning** — e.g. a lemon photographed on a table reads 7.5 cm at 0.50 m, giving a realistic ~150–200 g. The dominant remaining error sources are (a) the shape heuristic treating the bounding box as a solid sphere/cylinder/box, which over-estimates volume, and (b) the monocular scale ambiguity on featureless-background extreme close-ups (§4.2). Rounder items with tight bounding boxes remain the most accurate.

### 6.3 Depth Estimation

The δ₁ accuracy metric (% of pixels within 25% of ground truth) has not been evaluated quantitatively at this stage, as it requires a paired RGB+depth ground-truth dataset. Qualitative inspection of the Metric3D depth maps shows physically plausible **metric** values (e.g. a tabletop scene spanning 0.34–4.5 m) with correct relative ordering, validated against ruler measurements of known objects.

---

## 7. Known Limitations

1. **Monocular scale ambiguity on context-free close-ups** — Metric3D returns true metric depth when the frame contains scene context, but a featureless-background *extreme* close-up of a single object has no cue to fix metric scale, so distance (and therefore size) is over-estimated. This is a fundamental monocular limit, not a bug; mitigation is framing guidance (include some counter/floor).

2. **Weight accuracy varies by item shape** — The shape heuristic treats the bounding box as a solid sphere/cylinder/box, over-estimating volume for irregular items and loose crops. Round items with tight boxes are most accurate. A per-shape fill factor is a candidate refinement for the ±30% target.

3. **Packaged goods detection is weak** — Classes like pasta, oil, and juice are rarely detected with sufficient confidence. Packaging varies widely; more training data or a dedicated packaging detector would be needed.

4. **Depth model size** — The Metric3D ONNX is 75 MB (fp16) / 150 MB (fp32), heavier than the YOLO detector. Acceptable for the laptop prototype; mobile deployment will want further quantisation. The fp16 graph also requires ONNX Runtime graph optimisations disabled (handled automatically in `depth.py`).

5. **Low-instance classes** — `mayonnaise` (42 instances) and `hummus` (109 instances) are below ideal threshold. Detection recall for these classes is lower than average.

---

## 8. Next Steps (Phase 3 — due 15–17 June 2026)

- Run `evaluation/eval_weight.py` with Metric3D to measure MAPE on held-out items
- Add a per-shape volume fill factor to reduce the solid-shape over-estimation
- Validate the Metric3D ONNX on Android via `onnxruntime_flutter`; quantise further for mobile
- Build Flutter mobile app (screens and services in `mobile/`)
- Export trained YOLO11s to TFLite INT8 and integrate into Flutter app
- Measure end-to-end latency on a physical Android phone (target < 5 s)
- Final report, presentation slides, and live demo video
