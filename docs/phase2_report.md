# Phase 2 Report — Visual Ingredient Scanner with Recipe Generation

**Course:** Computer Vision · Master MEI FIB · UPC · Spring 2026  
**Team:** Pol Plana · Emma Nájera · Houda El Fezzak  
**Deadline:** 26–28 May 2026  

---

## 1. Project Overview

The Visual Ingredient Scanner is an end-to-end mobile application that allows a user to point a phone camera at a fridge or kitchen counter, tap once, and receive a list of detected ingredients with estimated weights and three ranked recipe suggestions.

The system is designed to be **serverless and privacy-first**: the computer vision pipeline runs entirely on-device, with only two lightweight Gemini API calls touching the network — one for ingredient density lookup (cached after the first call) and one for recipe generation.

### Pipeline at a glance

```
Camera frame
     │
     ▼
① YOLO11s ──────────────► bounding boxes + class labels   (on-device)
     │
     ▼
② Depth Anything V2-S ──► per-pixel depth map in metres   (on-device)
     │
     ├── ③ Gemini density call ──► kg/m³ per class (cached) (cloud, once per new class)
     │
     ▼
④ Pinhole model + shape heuristics ──► weight per item (g) (on-device)
     │
     ▼
⑤ Gemini recipe call ──────────────► 3 ranked recipes JSON  (cloud, once per scan)
```

---

## 2. Phase 2 Goals

| Goal | Status |
|---|---|
| Fine-tune YOLO11s on food dataset | ⏳ Dataset prepared — training pending |
| Export Depth Anything V2-S to ONNX | ✅ Done (`models/depth/`) |
| Implement full 5-stage Python pipeline | ✅ Done (`pipeline/`) |
| Build working Gradio laptop demo | ✅ Done (`prototype/app.py`) |
| Preliminary mAP, depth δ₁, weight MAPE metrics | ⏳ Pending trained model |
| Phase 2 report | ✅ This document |

---

## 3. Dataset

### 3.1 Strategy

No single public dataset covers all target food classes with sufficient instances. We merged four complementary Roboflow Universe datasets into a single Roboflow project, applying class renames to ensure consistent naming across all pipeline stages.

### 3.2 Source datasets

| Dataset | Roboflow slug | Main contribution |
|---|---|---|
| Ingredient Detection | `yasxhed/ingredient-detection-unorginazed-data` | Core fresh produce, proteins, dairy |
| Veggies and Fruits Balanced | `veggies-and-fruits-balanced-0g1ss` | Fruits, peach, lettuce, exotic fruits |
| Vegetables Dataset | `vegetables-g9p5a` | Zucchini (via vegetable marrow), beet, cauliflower, celery |
| Groceries | `groceries-mts9o` | Packaged goods: milk, cereal, pasta, chocolate, oil, juice, etc. |

### 3.3 Class rename mapping applied in Roboflow

| Original name | Renamed to | Dataset |
|---|---|---|
| `Salad` | `lettuce` | veggies-and-fruits |
| `Bell pepper` / `Bell Pepper` | `pepper` | veggies-and-fruits, vegetables |
| `Common fig` | `fig` | veggies-and-fruits |
| `vegetable marrow` | `zucchini` | vegetables |
| `brus capusta` | `brussels_sprouts` | vegetables |
| `cayliflower` | `cauliflower` | vegetables |
| `rediska` | `radish` | vegetables |
| `redka` | `radish` | vegetables |
| `fasol` | `beans` | vegetables |
| `chilli` / `hot pepper` | `chili` | vegetables |
| `salad` | `lettuce` | vegetables |
| `mayonaise` | `mayonnaise` | ingredient-detection |
| `humus` | `hummus` | ingredient-detection |
| `green beans` | `green_beans` | ingredient-detection |
| `goat_cheese` / `mozzarella cheese` | `cheese` | ingredient-detection |
| `cereal` | `cereal` | groceries |
| `milk` | `milk` | groceries |
| `pasta` | `pasta` | groceries |

### 3.4 Classes excluded

| Class | Reason |
|---|---|
| `Winter melon` | Only 74 instances — below threshold |
| `banana_pacche` | Ambiguous class definition |
| `squash-patisson` | Patty pan squash, mistaken for zucchini |
| `Burger` | Not a raw ingredient (5 instances) |
| `Lettuce` (capital L) | Only 1 instance |
| `meat` | Too generic |
| `bittergourd`, `chayote` | Uncommon in western kitchens |
| `cake`, `candy`, `chips`, `spices` | Not useful as recipe ingredients |

### 3.5 Final class list — 68 classes

**Fruits (22):**  
apple, avocado, banana, blackberries, blueberries, cantaloupe, coconut, fig, grapes, grapefruit, kiwi, lemon, lime, mango, orange, peach, pear, pineapple, pomegranate, raspberries, strawberries, watermelon

**Vegetables (28):**  
artichoke, beet, broccoli, brussels_sprouts, cabbage, carrot, cauliflower, celery, chili, corn, cucumber, eggplant, garlic, ginger, green_beans, lettuce, mushrooms, okra, onion, peas, pepper, potato, pumpkin, radish, spinach, sweet_potato, tomato, zucchini

**Proteins & dairy (12):**  
beef, butter, cheese, chicken, egg, fish, ham, heavy_cream, pork, shrimp, tofu, yogurt

**Pantry & packaged (21):**  
bread, cereal, chocolate, coffee, flour, honey, hummus, jam, juice, mayonnaise, milk, nuts, oil, pasta, rice, soda, sugar, tea, tomato_sauce, vinegar, water

### 3.6 Dataset split

Roboflow automatically splits the merged dataset as follows:

| Split | Proportion | Use |
|---|---|---|
| Train | 70% | YOLO fine-tuning |
| Validation | 20% | Loss monitoring during training |
| Test | 10% | Final mAP evaluation (held-out) |

---

## 4. Model Choices

### 4.1 Stage ① — Object Detection: YOLO11s

| Property | Value |
|---|---|
| Architecture | Ultralytics YOLO11, small variant |
| Parameters | ~9.4 M |
| Base training | COCO (80 classes) |
| Fine-tuning | Food dataset (68 classes, see §3) |
| Export (Android) | INT8 TFLite via `ultralytics export format=tflite int8=True` |
| Export (iOS) | CoreML via `ultralytics export format=coreml` |

YOLO11s was chosen over YOLO11n (accuracy too low) and YOLO11m (too large for on-device). RF-DETR was excluded due to immature mobile export support.

### 4.2 Stage ② — Depth Estimation: Depth Anything V2-S

| Property | Value |
|---|---|
| Checkpoint | `depth-anything/Depth-Anything-V2-Small` (metric indoor, Hypersim fine-tune) |
| Licence | Apache 2.0 — the only variant suitable for academic/commercial deployment |
| Output | Per-pixel depth in metres |
| Export | ONNX via `torch.onnx.export`, opset 17 |
| Runtime | `onnxruntime` CPU (laptop), `onnxruntime_flutter` (mobile) |
| Fine-tuning | None — pretrained metric-indoor checkpoint used as-is |

V2-Base and V2-Large were excluded due to CC-BY-NC licence restrictions.

### 4.3 Stage ③ — Density Lookup: Gemini 2.0 Flash Lite

- Called **once per scan** for any class whose density is not already cached
- All new classes are batched into a single API call
- Results cached in `data/density_cache.json`; never re-queried for cached classes
- Fallback to `data/density_fallback.json` (68 static entries) when API is unavailable

### 4.4 Stage ④ — Weight Estimation: Pinhole Model + Shape Heuristics

Real-world dimensions are derived from the bounding box and depth:

```
real_width  = (bbox_width_px  / focal_length_px) × depth_m
real_height = (bbox_height_px / focal_length_px) × depth_m
```

Volume is estimated using per-class shape heuristics:

| Shape | Classes (examples) | Formula |
|---|---|---|
| Sphere | apple, orange, tomato, egg, onion... | `V = (4/3)π(d/2)³`, d = min(w, h) |
| Cylinder | banana, carrot, cucumber, oil, soda... | `V = π(w/2)²·h` |
| Box | bread, cheese, chicken, cereal... | `V = w·h·max(w,h)·0.5` |

`focal_length_px` is read from EXIF `FocalLengthIn35mmFilm`; falls back to `image_width × 0.8`.

`weight_g = volume_m³ × density_kg_m³ × 1000`

### 4.5 Stage ⑤ — Recipe Generation: Gemini 2.0 Flash Lite

- Called once per scan after weight estimation
- Input: detected ingredients with estimated weights in grams
- Output: JSON array of 3 ranked recipes, each with name, ingredients used, steps, and servings
- Model adapts recipe quantities to the detected amounts

---

## 5. Implementation

### 5.1 Repository structure

```
pipeline/
├── detect.py       YOLO11s inference wrapper
├── depth.py        Depth Anything V2-S ONNX wrapper
├── density.py      Gemini density call + local cache
├── weight.py       Pinhole model + shape heuristics
├── recipe.py       Gemini recipe generation
└── pipeline.py     End-to-end orchestration

training/
├── train_yolo.py         YOLO11s fine-tuning (Google Colab T4)
├── export_yolo.py        TFLite + CoreML export
└── export_depth_onnx.py  Depth Anything V2-S → ONNX

prototype/
└── app.py          Gradio laptop demo

data/
├── classes.yaml          68 classes with shape hints and densities
├── density_fallback.json Static density table (68 entries)
└── density_cache.json    Runtime Gemini density cache

models/
└── depth/
    └── depth_anything_v2_small.onnx  ✅ present

notebooks/
└── train_yolo_colab.ipynb  Step-by-step Colab training notebook
```

### 5.2 Running the pipeline

```bash
# Activate virtual environment
venv\Scripts\activate        # Windows
source venv/bin/activate     # macOS/Linux

# Set Gemini API key
echo GEMINI_API_KEY=your_key > .env

# Run full pipeline on an image
python -m pipeline.pipeline --image path/to/fridge.jpg

# Launch Gradio demo
python prototype/app.py
```

### 5.3 Training (Google Colab)

Training is executed on Google Colab with a T4 GPU using `notebooks/train_yolo_colab.ipynb`. The notebook covers:

1. Installing `ultralytics` and `roboflow`
2. Verifying GPU availability
3. Downloading the merged dataset from Roboflow
4. Training YOLO11s for 50 epochs (cosine LR, built-in augmentations, batch=16, imgsz=640)
5. Evaluating mAP50-95 on the held-out test split
6. Exporting to INT8 TFLite and CoreML
7. Saving all outputs to Google Drive

---

## 6. Evaluation Targets

| Stage | Metric | Target | Status |
|---|---|---|---|
| Detection | mAP50-95 on food test set | > 40% | ⏳ Pending training |
| Depth | δ₁ accuracy (% pixels within 25% of GT) | > 0.75 | ⏳ Pending eval |
| Weight estimation | MAPE on held-out items | < 35% | ⏳ Pending eval |
| End-to-end latency (phone) | Capture → results | < 5 s | Phase 3 |

---

## 7. Known Limitations

1. **Weight estimation accuracy** — The ±30% target is achievable but not guaranteed for all shapes. Packaged goods (boxes, cartons) are harder to estimate than round fruit due to the 2D projection factor. This is documented as an expected limitation.

2. **Low-instance classes** — `mayonnaise` (42 instances) and `hummus` (109 instances) are below the ideal threshold of 150+. Detection accuracy for these classes will be lower than for well-represented classes. Additional training data can be added before Phase 3.

3. **Depth model on non-indoor scenes** — Depth Anything V2-S is fine-tuned on the Hypersim indoor dataset. Performance may degrade on outdoor or studio-lit kitchen photos. Validated on CPU only at this stage.

4. **Gemini API dependency** — Stages ③ and ⑤ require a network connection and a valid API key. A static fallback (`density_fallback.json`) is in place for density lookups; recipe generation is unavailable offline.

5. **ONNX operator compatibility** — The Depth Anything V2-S ONNX export uses opset 17 with ViT-based operators. Compatibility with `onnxruntime_flutter` on mobile will be validated in Phase 3. If issues arise, INT8 quantisation via `onnxruntime.quantization` will be applied as a fallback.

---

## 8. Next Steps (Phase 3 — due 15–17 June 2026)

- Complete YOLO11s training on Colab and record final mAP metrics
- Run `evaluation/eval_depth.py` and `evaluation/eval_weight.py` against test data
- Build Flutter mobile app (all screens and services in `mobile/`)
- Validate ONNX model on Android via `onnxruntime_flutter`
- Export trained YOLO11s to TFLite INT8 and bundle into Flutter app
- Full end-to-end latency measurement on a physical phone
- Final report, presentation slides, and demo video
