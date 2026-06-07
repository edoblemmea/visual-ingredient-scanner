# Phase 3 Report - Foodie Lens Mobile

**Course:** Computer Vision - Master MEI FIB - UPC - Spring 2026  
**Team:** Pol Plana - Emma Najera - Houda El Fezzak  
**Date:** 7 June 2026  

---

## 1. Delivery Summary

Phase 3 ships a Flutter mobile app that runs the full computer-vision stack on device:
YOLO v26m food detection, Metric3D/Depth Anything depth estimation, density-table lookup,
pinhole/shape weight estimation, manual correction tools, and optional Gemini recipe generation.

Only recipe generation uses the network. Detector, depth, density lookup, weight estimation,
manual annotation, density overrides, and scale correction all run locally.

## 2. Implemented Mobile Features

| Area | Status |
|---|---|
| Asset catalog and bundled model registry | Done |
| Settings persistence, model selection, confidence threshold | Done |
| Density table editor with live recompute | Done |
| Detector and depth ONNX Runtime integration | Done |
| Isolated scan pipeline and result state machine | Done |
| Camera/sample-image scan screen | Done |
| Result list with per-item weight details | Done |
| Gemini recipe cards with graceful fallback | Done |
| Optional bbox and depth-map developer views | Done |
| Manual distance/scale correction | Done |
| Manual annotation, smart lasso boxes, relabel/remove | Done |
| S17 polish: actionable error/empty states and scan timing chips | Done |

## 3. Evaluation Status

| Goal | Target | Current result | Status |
|---|---:|---:|---|
| G1 end-to-end latency, capture to CV result | < 10 s | 7 s average on Pixel 9 simulator | Pass |
| G2 detection mAP50-95, shipped detector family | > 0.40 | 0.552 on validation log (`docs/results.csv`, epoch 25) | Pass |

S17 adds in-app timing for the scan pipeline. Turn on either developer-view toggle in
Settings, run a scan, and the result screen shows elapsed seconds, detection count, weighed
item count, and any active distance-correction scale. On the Pixel 9 simulator used for S17, the
capture-to-CV-result path averages 7 s, below the 10 s target.

## 4. Final UX Polish

The result screen now handles all scan states:

- Running: spinner and analysis status.
- Error: explicit failure state, surfaced runtime message, and a back-to-scan action.
- Empty success: recovery actions to annotate missed items or scan again.
- Success: item weights, details, optional debug views, scale correction, recipes.

The scan screen also surfaces camera-startup errors while preserving sample-image fallback.

## 5. Known Limits

- Weight accuracy depends on object shape, bbox tightness, and monocular depth scale.
- Featureless extreme close-ups remain scale-ambiguous; use distance correction when needed.
- Recipe generation depends on a user-provided Gemini API key and network availability.

## 6. Verification

Automated checks for S17:

- `flutter analyze`
- `flutter test`
