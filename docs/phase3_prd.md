# PRD — Visual Ingredient Scanner · Flutter Mobile App (Phase 3)

**Status:** Draft for Phase 3 (Flutter app, 15–17 June 2026)
**Owners:** Pol Plana, Emma Nájera, Houda El Fezzak
**Scope:** **Mobile app only.** Port the validated Phase 2 Python pipeline to an on-device
Flutter app, with all CV models **compiled into the app bundle**, the detector and depth
models **selectable at runtime**, an **editable density table**, **persistence**, depth/box
**visualisations**, a **manual distance correction**, and **manual annotation of undetected
food**.

This is the build spec. It assumes the five-stage pipeline, runtime stack, and constraints
already fixed in [CLAUDE.md](../CLAUDE.md). Read that first.

---

## 1. Goal & success criteria

Point a phone at a fridge/counter → tap → on-device detection + metric depth + weight
estimation → one Gemini call → 3 recipes. The user can change which models run, correct
scale, and fix detections — all on-device.

| # | Criterion | Target |
|---|---|---|
| G1 | End-to-end latency, capture → results (mid-range phone) | < 5 s |
| G2 | Detection mAP50-95 on food test set (shipped model) | > 40 % |
| G3 | Weight MAPE on held-out items | < 35 % |
| G4 | Model / density / setting changes survive an app restart | persisted |
| G5 | Model selection takes effect on next scan | no rebuild |
| G6 | App runs fully offline except the single Gemini recipe call | — |
| G7 | Distance correction & manual boxes recompute weights **without re-running the models** | reuse cached depth map |

---

## 2. Models bundled in the app

Only **ONNX** assets are shipped — both stages run through `flutter_onnxruntime` (ORT 1.22) on device, giving a
single inference code path for detector and depth.

### 2.1 Detector models (YOLO, selectable)
Ship **only** the two correctly-exported NMS-baked ONNX detectors:

| id | File | Source | I/O |
|---|---|---|---|
| `v26m_e30` (default) | `assets/models/epoch30.onnx` | `models/yolo/v26m/v26m_v7/epoch30.onnx` (~78 MB) | in `images[1,3,640,640]` → out `output0[1,300,6]` |
| `v26m_e40` | `assets/models/epoch40.onnx` | `models/yolo/v26m/v26m_v7/epoch40.onnx` (~78 MB) | same as above |

- `output0[1,300,6]` rows are `[x1, y1, x2, y2, score, class_id]` in 640×640 space — **NMS is
  already baked in**. No manual NMS in Dart; just threshold on `score` and rescale boxes to the
  original image.
- ✅ Both `epoch30.onnx` and `epoch40.onnx` exist on disk and share the verified I/O above. All
  other `.pt` / older variants are **excluded**.

### 2.2 Depth models (selectable — the "scale" model)
| id | File | family | size | role |
|---|---|---|---|---|
| `metric3d` (default) | `assets/models/metric3d-vit-small-fp16.onnx` | `metric3d` | 72 MB | true metric depth |
| `depthanything` | `assets/models/depth_anything_v2_small.onnx` (+`.data`) | `depthanything` | ~96 MB | relative-depth alternative |

`family` selects the preprocessing branch (mirrors [depth.py](../pipeline/depth.py): Metric3D →
canonical 616×1064 + de-canonicalise with focal; Depth Anything → 518×518). On mobile we key off
`family` explicitly instead of sniffing ONNX outputs.

### 2.3 Density data (editable, not a model)
- `assets/data/food_densities.json` — bundled baseline ([data/food_densities.json](../data/food_densities.json)).
- `assets/data/labels.txt` — class list from [data/classes.yaml](../data/classes.yaml) (86 classes),
  in detector output-index order. App asserts length 86 at load.
- User edits to densities are stored as a **persisted override map** merged over the baseline.

### 2.4 Model registry (drives the pickers)
`assets/model_registry.json`:
```json
{
  "detectors": [
    {"id":"v26m_e30","label":"YOLO v26m · epoch30 (default)","asset":"models/epoch30.onnx","inputSize":640,"default":true},
    {"id":"v26m_e40","label":"YOLO v26m · epoch40","asset":"models/epoch40.onnx","inputSize":640}
  ],
  "depth": [
    {"id":"metric3d","label":"Metric3D ViT-S (metric)","asset":"models/metric3d-vit-small-fp16.onnx","family":"metric3d","default":true},
    {"id":"depthanything","label":"Depth Anything V2-S (relative)","asset":"models/depth_anything_v2_small.onnx","family":"depthanything"}
  ]
}
```

---

## 3. Architecture

```
ScanScreen (camera) ──capture──> ScanController  (orchestrates, runs models on an Isolate)
   │                                  │  caches: detections + raw depth map + focal_px
   ├─ DetectorService  ← flutter_onnxruntime  │
   ├─ DepthService     ← flutter_onnxruntime  │
   ├─ DensityService   ← food_densities.json + user overrides
   ├─ WeightService    ← pure Dart (pinhole + shapes)  ◄── re-run cheaply on corrections (G7)
   └─ RecipeService    ← Gemini (single network call)
   │
   ├─ ResultScreen  (ingredients + weights + recipes; optional bbox & depth overlays;
   │                 distance-correction slider; "add missing item" tool)
   └─ SettingsScreen (detector picker · depth picker · density editor · toggles · API key)

SettingsRepository (shared_preferences + local JSON file) ── persists everything (G4)
```

- All model inference on a background **Isolate** — never block the UI (CLAUDE.md).
- State via `provider` / `ChangeNotifier` (no Riverpod/Bloc).
- **Recompute path (G7):** corrections (distance anchor, manual box, density edit, threshold)
  reuse the **cached depth map + detections** and only re-run `WeightService` — no model
  re-inference.

---

## 4. Functional requirements

### FR1 — Scan & results
Live camera → single capture (EXIF/focal retained) → Isolate runs detector + depth → density
lookup → weights → Gemini recipes. ResultScreen lists ingredients with grams + 3 recipe cards.

### FR2 — Model selection (Settings)
- **Detector model** radio picker (from registry `detectors`).
- **Depth model** radio picker (from registry `depth`).
- Selection persisted; applied on the **next scan** (G5), no restart.

### FR3 — Density table editor (Settings)
- Searchable list of all 86 classes with current kg/m³ (baseline or override).
- Edit any value; "reset to default" per row and globally.
- Overrides persisted (G4) and merged over the baseline by `DensityService`.
- Editing a value used in the current scan **recomputes** weights live (G7).

### FR4 — Persistence
`SettingsRepository` persists: selected detector id, depth id, confidence threshold, density
overrides, visualisation toggles, and Gemini API key. Restored on launch (G4).

### FR5 — Visualisations (hidden by default)
- **Bounding-box overlay**: detected boxes + labels drawn over the captured frame.
- **Depth-map view**: colour-mapped depth (e.g. turbo/viridis) of the cached depth map.
- Both **off by default**; toggled from a "Developer / debug view" section (ResultScreen
  expander and/or Settings). Toggle state persisted.

### FR6 — Distance correction (manual scale anchor)
- On ResultScreen, the user picks one detected (or manual) object and sets the **real
  camera-to-object distance** with a slider (e.g. 0.1–2.0 m).
- The app computes `scale = user_distance / median_depth_of_that_object`, multiplies the
  **cached depth map** by `scale`, and **recomputes all** real dimensions, volumes and weights
  (G7) — no model re-run. A "reset" restores the model's original depth.
- Purpose: correct Metric3D's known scale ambiguity on featureless close-ups.

### FR7 — Manual annotation of undetected food
- "Add missing item" tool: the user **draws a rectangle** on the captured image and **picks a
  class** from the density list (the food_densities classes).
- The box becomes a synthetic detection (default confidence), runs through depth sampling +
  `WeightService`, and joins the results + recipe input. Editable/removable.

### FR8 — Recipes
`RecipeService` via `google_generative_ai`, `gemini-2.0-flash-lite`, JSON-validated 3 recipes,
degrades to a "Recipe service not available right now. Try again later." state offline.
**API key is per-user**: entered in Settings and stored in `flutter_secure_storage`
(Keychain/Keystore) — never bundled in the app and never written to the plaintext prefs blob, so
there is no shared secret to extract by reverse-engineering. (No `.env` in the app: a bundled key
is always extractable; the serverless design rules out a backend proxy, so per-user keys are the
secure option.)

---

## 5. One-off prerequisite (before app integration) — ✅ DONE

Both detectors are exported to the NMS-baked ONNX format and I/O-verified
(`images[1,3,640,640]` → `output0[1,300,6]`): `epoch30.onnx` and `epoch40.onnx` (~78 MB each)
under `models/yolo/v26m/v26m_v7/`. Remaining check for S8: confirm both depth ONNX files load
under the mobile ORT build (the Metric3D fp16 graph needs reduced graph optimisation — see
[depth.py](../pipeline/depth.py:38)).

---

## 6. Dart port reference (port faithfully — do not redesign the math)

| Service | Ports from | Must preserve |
|---|---|---|
| `DetectorService` | [detect.py](../pipeline/detect.py) | letterbox to 640; decode `[1,300,6]`; threshold on score (default 0.10); rescale xyxy to original px |
| `DepthService` | [depth.py](../pipeline/depth.py) | **Metric3D recipe exactly:** keep-aspect resize into 616×1064, centre-pad with ImageNet mean (0–255), normalise, run, un-pad, resize back, then `depth_m = raw × (focal_px × resize_scale / 1000)`. Depth Anything: 518×518, ImageNet norm 0–1 |
| `WeightService` | [weight.py](../pipeline/weight.py) | pinhole `real=(bbox_px/focal_px)×depth_m`; depth = **median** of bbox ROI clamped [0.1,10] m; sphere/cylinder/box volume + box ×0.5; `weight_g=vol×density×1000`; sphere/cylinder class sets identical to Python |
| `DensityService` | [density.py](../pipeline/density.py) | baseline JSON + user overrides; unknown class → 800 kg/m³ |
| `RecipeService` | [recipe.py](../pipeline/recipe.py) | `gemini-2.0-flash-lite`; JSON; graceful degradation |

**Focal length (load-bearing — feeds both depth de-canonicalisation and the pinhole model):**
EXIF `FocalLengthIn35mmFilm` (0xA405) → `focal_px=(focal_35mm/36)×image_width_px`; fallback
`focal_px=image_width_px×0.8`. The capture path must retain EXIF or read focal from camera
metadata.

---

## 7. Implementation steps (sequential — implement & commit one after another)

Each step is a single self-contained commit. Do them in order; later steps assume earlier ones.

**S0 — Export `epoch40.onnx`** (§5). ✅ **DONE** — `epoch30.onnx` and `epoch40.onnx` exist and
are I/O-verified.

**S1 — Flutter scaffold.** ✅ **DONE.** Created `mobile/` via
`flutter create --org edu.upc.fib.cv --project-name visual_ingredient_scanner --platforms=android,ios`
(Flutter 3.41.9 / Dart 3.11.5). Folder layout `lib/{screens,services,models,widgets}`; deps added
(`camera`, `image`, `flutter_onnxruntime`, `google_generative_ai`, `flutter_secure_storage`, `provider`,
`shared_preferences`, `path_provider`); `analysis_options.yaml` (flutter_lints) in place. App boots
to `HomeScreen` with a route into a `SettingsScreen` placeholder. `flutter analyze` clean; smoke
test passes.
> commit: `feat(mobile): flutter scaffold + dependencies`

**S2 — Bundle assets + registry.** ✅ **DONE.** Copied both detector ONNX, the default depth ONNX,
the Depth Anything graph, `food_densities.json`, generated `labels.txt` (86 classes from
`classes.yaml`), and `model_registry.json` under `mobile/assets/`; declared `assets/` directories
in `pubspec.yaml`. **GitHub 100 MB limit:** the four files < 100 MB are committed; the ~99 MB
`depth_anything_v2_small.onnx.data` external-data blob is gitignored and documented for manual
download in the README (default Metric3D path works without it). `AssetCatalog`/`AppCatalog`
([asset_catalog.dart](../mobile/lib/services/asset_catalog.dart)) parse the registry + labels +
densities at startup and assert 86 labels; HomeScreen renders the loaded counts. Unit tests cover
registry/labels/density parsing; `flutter analyze` clean, tests pass.
> commit: `feat(mobile): bundle models, density table, and model registry`

**S3 — Domain models.** ✅ **DONE.** Pure value objects under
[mobile/lib/models/](../mobile/lib/models/): `BBox`, `Detection` (+ `isManual` for FR7), `Shape`
enum + `WeightedItem`, `Recipe` (snake_case JSON matching Gemini), `ModelChoice` (value equality
to detect selection changes), `ScanResult` (with `fromItems` per-class gram aggregation mirroring
`pipeline.py`), and `AppSettings` (nullable model ids → registry defaults, density overrides,
viz toggles, API key; JSON round-trip for S4). Barrel `models.dart`. Unit tests cover aggregation,
Recipe JSON, and AppSettings round-trip; `flutter analyze` clean, 10 tests pass.
> commit: `feat(mobile): core domain models`

**S4 — Persistence.** ✅ **DONE.**
[SettingsRepository](../mobile/lib/services/settings_repository.dart) stores the whole
`AppSettings` as one JSON blob in `shared_preferences` (corrupt/absent → defaults).
[SettingsProvider](../mobile/lib/state/settings_provider.dart) (`ChangeNotifier`) holds live
settings, notifies immediately, and write-throughs on every mutator (detector/depth/threshold/
density overrides/toggles/API key); `modelChoice` resolves unset ids to registry defaults.
`main.dart` refactored into an `AppBootstrap` that loads catalog + settings and wraps the
`MaterialApp` in `MultiProvider` **above the Navigator** (so pushed routes can read them), with
splash/error states. HomeScreen now reads from providers and shows the resolved model selection.
Tests cover persistence across provider instances (G4), default resolution, override clearing,
and listener notification; `flutter analyze` clean, 14 tests pass.
> commit: `feat(mobile): persistent settings repository`

**S5 — DensityService.** ✅ **DONE.**
[DensityService](../mobile/lib/services/density_service.dart) — immutable, sendable to the scan
isolate. Resolution order override → baseline → `kDefaultDensity` (800, matching `density.py`/
`weight.py`); exposes `densityFor`, `baselineFor`/`isOverridden` (for the S13 editor's reset), and
`densitiesFor(list)`. Constructed per scan from `catalog.densities` + `settings.densityOverrides`.
Tests cover resolution order, baseline-vs-override, and list mapping; `flutter analyze` clean, 17
tests pass.
> commit: `feat(mobile): density service with editable overrides`

**S6 — WeightService (pure Dart).** ✅ **DONE.**
[DepthMap](../mobile/lib/models/depth_map.dart) value type with a `medianIn(bbox)` that matches
`np.median` (integer half-open slicing, averages the two middle values for even counts).
[WeightService](../mobile/lib/services/weight_service.dart) ports `estimate_weights` verbatim:
sphere/cylinder class sets copied from weight.py, pinhole `real=(px/focal)×depth`, depth clamp
[0.1, 10] m, box volume `w·h·max(w,h)·0.5`, `weight_g = vol×density×1000`; static and pure so it
re-runs cheaply for G7. **Parity verified**: reference numbers generated from `pipeline/weight.py`
(focal 800 px) for sphere/cylinder/box, the even-count median (0.55 m), and the depth clamp
(50→10 m) all match within 1e-6; empty-ROI skip covered. `flutter analyze` clean, 23 tests pass.

> Note: the box formula follows the **code** (`w·h·max(w,h)·0.5`), not CLAUDE.md's prose
> (`…×depth_m×0.5`) — the running code is authoritative for parity.
> commit: `feat(mobile): weight estimation (pinhole + shapes) with parity tests`

**S7 — DetectorService.** ✅ **DONE.**
[ort_runtime.dart](../mobile/lib/services/ort_runtime.dart) initialises `OrtEnv` once (shared by
detector + depth). [DetectorService](../mobile/lib/services/detector_service.dart): loads the
selected ONNX from assets via `OrtSession.fromBuffer`; `preprocess` does aspect-preserving
letterbox into 640×640 with centre grey (114) padding, written CHW RGB normalised 0–1 as a
`Float32List`; `decodeDetections` thresholds the NMS-baked `[1,300,6]` rows (default conf 0.10),
un-letterboxes boxes back to original px, clamps to bounds, and maps class ids to labels
(`class_<id>` fallback). Preprocess/decode are pure static methods so they're unit-tested without
native inference; `detect()` glues them with proper ORT tensor/run/output release. Tests cover the
letterbox transform, threshold/rescale/label mapping, clamping, and label fallback;
`flutter analyze` clean, 27 tests pass.
> commit: `feat(mobile): YOLO ONNX detector service`

**S8 — DepthService.** ✅ **DONE.**
[DepthService](../mobile/lib/services/depth_service.dart) ports `depth.py`: Metric3D branch
(keep-aspect resize into 616×1064, centre-pad with ImageNet mean in 0–255, normalise, un-pad,
bilinear resize back, de-canonicalise `× focal×scale/1000`) and Depth Anything branch (518×518,
ImageNet 0–1). Pre/post helpers (`preprocessMetric3d`, `preprocessDepthAnything`, `cropPlane`,
`bilinearResize`, `metric3dDecanonFactor`) are pure static + unit-tested.

> **Float16 (resolved via runtime upgrade).** The fp16 Metric3D model has float16 input/output.
> The original `onnxruntime` package (ORT 1.15) couldn't create/read float16 tensors, so an earlier
> approach hand-wrote an FFI binary16 codec. That is now **removed**: the app migrated to
> **`flutter_onnxruntime` (ORT 1.22)**, which has native FP16 — `DepthService` feeds the model with
> `OrtValue.to(OrtDataType.float16)` and reads the float16 output back as doubles via
> `asFlattenedList()`. The registry carries `"precision":"float16"` (→ `DepthModel.float16` →
> `DepthService.fromAsset(float16:)`).

`flutter analyze` clean, tests pass.
> commit: `feat(mobile): depth service (Metric3D + Depth Anything, float16 support)`

**S9 — ScanController + Isolate.** ✅ **DONE.**
[ScanController](../mobile/lib/state/scan_controller.dart) (`ChangeNotifier`, provided in
`main.dart`) orchestrates detect → depth → density → weight with `ScanStatus`
(idle/running/success/error). Model inference runs **off the UI thread** via the services'
`runAsync` — confirmed `OrtIsolateSession` passes the session *address* to a spawned isolate
(native pointers are process-global) and reuses the `fromBuffer` session with no model reload, so
detector/depth `detect`/`estimate` are now `Future`-returning. Services are loaded lazily and
rebuilt only when the `ModelChoice` changes (G5). It **caches** the image, raw depth map, focal,
and detections, and exposes the G7 recompute path: `recompute()`/`updateSettings`/
`applyDistanceCorrection` (S15 hook)/`addManualDetection` (S16 hook) all re-run only the pure-Dart
weight pipeline on the cache. The core is a pure static `computeResult` (depth-scale → density →
weight → aggregate), unit-tested for aggregation, density-override proportionality, depth³ scaling,
manual detections, and default-density fallback. `flutter analyze` clean, 43 tests pass.
> commit: `feat(mobile): scan orchestration on isolate with recompute path`

**S10 — ScanScreen + ResultScreen (baseline).** ✅ **DONE.**
[focal.dart](../mobile/lib/services/focal.dart) reads EXIF `FocalLengthIn35mmFilm`
(`focal_px = focal35mm/36 × width`, pure `focalPxFromFocal35mm` helper) with the `width×0.8`
fallback, mirroring weight.py. [ScanScreen](../mobile/lib/screens/scan_screen.dart): live
`CameraPreview` + capture FAB, **plus a bundled-sample strip** (`kSampleImageAssets`) so the user
can scan a sample instead of taking a photo (graceful "camera unavailable" state on simulators).
Capture/select → decode → focal → `ScanController.scan` → push
[ResultScreen](../mobile/lib/screens/result_screen.dart), which reacts to `ScanStatus`
(running/error/empty/success) and lists ingredients with weight + expandable detail (shape,
confidence, depth, real size, density, manual flag). Home "Scan" button wired up; camera
permissions added (Android `CAMERA`, iOS `NSCameraUsageDescription`). Focal computation unit-tested;
`flutter analyze` clean, 45 tests pass.
> commit: `feat(mobile): scan and result screens`

**S11 — RecipeService + recipe cards.** ✅ **DONE.**
[RecipeService](../mobile/lib/services/recipe_service.dart) ports recipe.py: one
`gemini-2.0-flash-lite` call (`google_generative_ai`, `responseMimeType: application/json`),
`buildPrompt` mirrors the Python template, `parseRecipes` strips a ```json fence, decodes the
array, and caps at 3. Graceful degradation: empty list on no API key / no ingredients / network /
parse failure (pure helpers unit-tested). The [ScanController](../mobile/lib/state/scan_controller.dart)
runs it as stage ⑤ **after** the weights are shown (separate `recipesLoading` flag, non-blocking),
with `regenerateRecipes()` for on-demand refresh. [ResultScreen](../mobile/lib/screens/result_screen.dart)
shows a recipes section: spinner while loading, recipe cards (name, servings, ingredient chips,
numbered steps), or a "Recipe service not available right now. Try again later." message when
empty (with a hint to set the key in Settings). API key read from the per-user secure-storage value.
`flutter analyze` clean.
> commit: `feat(mobile): Gemini recipe generation and result cards`

**S12 — SettingsScreen: model selection.** ✅ **DONE.**
[SettingsScreen](../mobile/lib/screens/settings_screen.dart) replaces the placeholder: detector and
depth `RadioGroup` pickers from the registry (depth options flag "needs manual download" for Depth
Anything), a confidence slider (0.05–0.9), and an obscured Gemini API-key field. All wired to
`SettingsProvider` so changes persist (G4) and apply on the next scan (G5); the API key feeds
RecipeService (closes the S11 gap). **Security:** the key is stored in `flutter_secure_storage`
(Keychain/Keystore) and explicitly excluded from the `shared_preferences` JSON blob — per-user, no
bundled shared secret, nothing to reverse-engineer (chose this over `.env`-in-app, which is always
extractable). Used the modern `RadioGroup` ancestor API (RadioListTile's `groupValue`/`onChanged`
are deprecated in Flutter 3.41). Widget tests verify detector/depth selection flows through the
provider; a provider test asserts the key never lands in the prefs blob; `flutter analyze` clean,
55 tests pass.
> commit: `feat(mobile): settings screen with detector/depth model selection`

**S13 — Density editor.** ✅ **DONE.**
[DensityEditorScreen](../mobile/lib/screens/density_editor_screen.dart) (reached from a Settings
entry): searchable list of all 86 classes showing the effective kg/m³ (override or baseline) via
`DensityService`, edited through a numeric dialog. Per-row "undo to default" (shows the baseline)
and a global "reset all" in the app bar. Edits persist as overrides (G4) and push into
`ScanController.updateSettings` so the current scan's weights recompute live (G7). Widget test
covers search filtering. `flutter analyze` clean, 56 tests pass.

> **Scan bug fixed (reported during S13).** On-device scan failed with ORT `code=9`
> (NOT_IMPLEMENTED) "Could not find an implementation for Reshape(19)" on the v26m attention
> blocks. Root cause: the mobile ORT 1.15.1 graph **optimizer** emits fused/layout nodes with no
> kernel (the models are opset-19/IR-9, which 1.15 otherwise supports). Fix: set the detector and
> depth sessions to `GraphOptimizationLevel.ortDisableAll` (also what the fp16 Metric3D graph
> needs). Needs on-device re-verification.
> commit: `feat(mobile): editable density table screen`

**S14 — Visualisation toggles (hidden by default).** ✅ **DONE.**
Settings "Developer view" section with two `SwitchListTile`s (show bounding boxes / show depth
map), wired to the already-persisted `showBoxes`/`showDepthMap` flags (G4), off by default.
[ResultScreen](../mobile/lib/screens/result_screen.dart) gains a `_DebugViews` section: the
captured image (`controller.imageBytes`) with a [BoxOverlayPainter](../mobile/lib/widgets/bbox_overlay.dart)
drawing detection boxes + weight labels (manual boxes in orange), and a jet-coloured depth map via
[depth_visualizer.dart](../mobile/lib/services/depth_visualizer.dart) (`renderDepthMapPng`,
downsampled + min/max-normalised, rendered once per depth map and cached). The controller now
exposes `imageBytes` and the effective (distance-corrected) `depthMap`; `scan()` caches the source
bytes. Depth-colorizer unit-tested (downscale size, near→blue/far→red, constant-depth guard).
`flutter analyze` clean, 55 tests pass.
> commit: `feat(mobile): optional bbox overlay and depth-map view`

**S15 — Distance correction slider.** ✅ **DONE.**
[ResultScreen](../mobile/lib/screens/result_screen.dart) gains an "Adjust scale (optional)"
expander: a dropdown to pick a detected object + a distance slider (5–200 cm). On slider release it
calls `ScanController.applyDistanceCorrection(detection, metres)`, which samples the **raw** median
depth for that bbox and sets `_depthScale = realDistance / rawMedian` (absolute — repeated
corrections don't compound), then recomputes all weights via the pure G7 path. Shows the current
`×scale` and a "Reset scale" action. Applied on `onChangeEnd` (not per tick) to avoid copying the
full-res depth map repeatedly. The controller API now takes a `Detection` (sampling raw depth
itself); the placeholder `WeightedReference` was removed. Unit test confirms the anchored object
reads the set distance after correction. `flutter analyze` clean, 60 tests pass.
> commit: `feat(mobile): manual distance/scale correction with recompute`

**S16 — Manual annotation of undetected food.** Draw-rectangle tool + class picker from the
density list; synthetic detection → depth sample → weight; editable/removable; feeds recipes.
(FR7)
> commit: `feat(mobile): manual bounding-box annotation for missed items`

**S17 — On-device eval & polish.** Measure G1/G2/G3 on device, error/empty states, final UX pass;
update report.
> commit: `chore(mobile): on-device evaluation, polish, and report`

---

## 8. Dependencies (pubspec)

`camera`, `image` (EXIF + pixel ops + draw), `flutter_onnxruntime` (ORT 1.22),
`google_generative_ai`, `flutter_secure_storage` (API key at rest), `provider`,
`shared_preferences`, `path_provider`.

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| `epoch40.onnx` missing | S0 exports it before bundling |
| Two detectors + two depth ONNX ≈ 320 MB bundle | acceptable for the academic demo; if needed, mark `depthanything` an eval-only asset |
| Metric3D fp16 won't load on mobile ORT | reduced graph-opt level (see depth.py); fall back to fp32 reduced if required |
| EXIF focal stripped by camera plugin → wrong metric scale | read focal from camera metadata; ×0.8 fallback; FR6 lets the user correct it |
| Class-order mismatch after export | ship `labels.txt`; assert length 86 at load |
| Metric3D scale ambiguity on featureless close-ups | documented limitation; FR6 distance correction is the in-app fix |
```
