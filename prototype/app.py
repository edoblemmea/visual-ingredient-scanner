"""Gradio laptop demo — Phase 2 deliverable.

Run:  python prototype/app.py
Then open http://localhost:7860 in a browser and upload a kitchen photo.
"""

from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import cv2
import numpy as np
import pandas as pd
import gradio as gr
from PIL import Image, ImageDraw, ImageFont

from pipeline.pipeline import run


_REPO_ROOT = Path(__file__).parent.parent

# Shared display height (px) for the input image and its derived views
# (annotated detection image + depth map), so all three render at the same size.
_IMAGE_HEIGHT = 780


def _scan_models(subdir: str, ext: str) -> list[str]:
    """Return repo-root-relative paths for all model files under models/<subdir>/.

    Recurses into sub-folders (e.g. models/yolo/v11s/, models/yolo/v26m/) so
    different model variants can be organised in their own directories.
    Newest files (most recently modified) come first so the latest model is
    pre-selected in the dropdown.
    """
    folder = _REPO_ROOT / "models" / subdir
    if not folder.exists():
        return []
    files = sorted(folder.rglob(f"*.{ext}"), key=lambda p: p.stat().st_mtime, reverse=True)
    return [str(p.relative_to(_REPO_ROOT)) for p in files]


def _load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for name in (
        "Arial.ttf",
        "DejaVuSans.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def _annotate(image: Image.Image, detections: list[dict]) -> Image.Image:
    draw = ImageDraw.Draw(image)
    font_size = max(13, int(min(image.size) * 0.018))
    font = _load_font(font_size)
    box_width = max(2, font_size // 8)
    pad = 2

    # First pass: draw every bounding box, so a later box never paints over an
    # earlier box's label.
    for d in detections:
        x1, y1, x2, y2 = d["bbox"]
        draw.rectangle([x1, y1, x2, y2], outline="lime", width=box_width)

    # Second pass: draw labels on top of all boxes.
    for d in detections:
        x1, y1, _, _ = d["bbox"]
        label = f"{d['class']} {d['confidence']:.0%}  {d['weight_g']:.0f}g"
        # Measure the glyph box at origin; left/top capture the font's internal
        # bearing so the text can be placed flush inside its background band.
        left, top, right, bottom = draw.textbbox((0, 0), label, font=font)
        text_w, text_h = right - left, bottom - top

        band_left = x1
        band_top = y1 - text_h - 2 * pad  # sit the label just above the box
        if band_top < 0:                  # no room above → drop it inside the box
            band_top = y1
        draw.rectangle(
            [band_left, band_top, band_left + text_w + 2 * pad, band_top + text_h + 2 * pad],
            fill=(0, 0, 0),
        )
        draw.text((band_left + pad - left, band_top + pad - top), label, fill="lime", font=font)
    return image


def _depth_colormap(depth_map: np.ndarray) -> Image.Image:
    """Convert a depth map (metres) to a plasma-coloured PIL image."""
    d_min, d_max = float(depth_map.min()), float(depth_map.max())
    if d_max > d_min:
        norm = ((depth_map - d_min) / (d_max - d_min) * 255).astype(np.uint8)
    else:
        norm = np.zeros_like(depth_map, dtype=np.uint8)
    colored_bgr = cv2.applyColorMap(norm, cv2.COLORMAP_PLASMA)
    colored_rgb = cv2.cvtColor(colored_bgr, cv2.COLOR_BGR2RGB)
    return Image.fromarray(colored_rgb)


def _overlay_boxes_on_depth(depth_img: Image.Image, detections: list[dict]) -> Image.Image:
    """Draw bounding boxes on the depth colormap."""
    draw = ImageDraw.Draw(depth_img)
    for d in detections:
        x1, y1, x2, y2 = d["bbox"]
        draw.rectangle([x1, y1, x2, y2], outline="white", width=2)
        draw.text((x1 + 3, y1 + 2), f"{d['class']} {d['depth_m']:.2f}m", fill="white")
    return depth_img


# Column headers for each results table (shared by the component and the DataFrame)
_DET_COLS = ["Class", "Confidence", "BBox  x1, y1, x2, y2  (px)"]
_DEPTH_COLS = ["Class", "Median depth (m)", "Real width (cm)", "Real height (cm)"]
_WEIGHT_COLS = [
    "Class", "Shape", "Depth (m)",
    "Width (cm)", "Height (cm)",
    "Volume (cm³)", "Density (kg/m³)", "Weight (g)",
]

# Empty placeholders for each table when there are no detections.
# Returning a pandas DataFrame (not a raw list) ensures gr.Dataframe always
# re-renders — a plain list of identical shape is sometimes diffed away and the
# table keeps showing the previous scan's rows.
_EMPTY_DET = pd.DataFrame([["—"] * len(_DET_COLS)], columns=_DET_COLS)
_EMPTY_DEPTH = pd.DataFrame([["—"] * len(_DEPTH_COLS)], columns=_DEPTH_COLS)
_EMPTY_WEIGHT = pd.DataFrame([["—"] * len(_WEIGHT_COLS)], columns=_WEIGHT_COLS)


def scan(image: Image.Image, yolo_model: str, depth_model: str):
    if image is None:
        return None, _EMPTY_DET, None, _EMPTY_DEPTH, _EMPTY_WEIGHT, "No image provided.", ""

    result = run(image, yolo_model, depth_model)
    detections = result["detections"]
    depth_map: np.ndarray | None = result.get("depth_map")

    if not detections:
        depth_vis = _depth_colormap(depth_map) if depth_map is not None else None
        return (
            image,
            _EMPTY_DET,
            depth_vis,
            _EMPTY_DEPTH,
            _EMPTY_WEIGHT,
            "No ingredients detected.",
            "",
        )

    # ── ① Detection ──────────────────────────────────────────────────────────
    annotated = _annotate(image.copy(), detections)
    det_rows = pd.DataFrame(
        [
            [
                d["class"],
                f"{d['confidence']:.1%}",
                f"{d['bbox'][0]}, {d['bbox'][1]}, {d['bbox'][2]}, {d['bbox'][3]}",
            ]
            for d in detections
        ],
        columns=_DET_COLS,
    )

    # ── ② Depth ───────────────────────────────────────────────────────────────
    depth_vis = None
    if depth_map is not None:
        depth_vis = _overlay_boxes_on_depth(_depth_colormap(depth_map), detections)

    depth_rows = pd.DataFrame(
        [
            [
                d["class"],
                f"{d['depth_m']:.3f}",
                f"{d['real_width_m'] * 100:.1f}",
                f"{d['real_height_m'] * 100:.1f}",
            ]
            for d in detections
        ],
        columns=_DEPTH_COLS,
    )

    # ── ③ Weight Estimation ───────────────────────────────────────────────────
    weight_rows = pd.DataFrame(
        [
            [
                d["class"],
                d["shape"],
                f"{d['depth_m']:.3f}",
                f"{d['real_width_m'] * 100:.1f}",
                f"{d['real_height_m'] * 100:.1f}",
                f"{d['volume_m3'] * 1e6:.2f}",
                f"{d['density_kg_m3']:.0f}",
                f"{d['weight_g']:.1f}",
            ]
            for d in detections
        ],
        columns=_WEIGHT_COLS,
    )

    # ── ④ Ingredients ────────────────────────────────────────────────────────
    ingredients_text = "\n".join(
        f"• {name}: {w:.0f} g" for name, w in result["weights"].items()
    )

    # ── ⑤ Recipes ────────────────────────────────────────────────────────────
    recipes_md = ""
    for i, r in enumerate(result.get("recipes", []), 1):
        recipes_md += f"### {i}. {r['name']}  *(serves {r.get('servings', '?')})*\n\n"
        if r.get("ingredients_used"):
            recipes_md += "**Ingredients used:** " + ", ".join(r["ingredients_used"]) + "\n\n"
        for j, step in enumerate(r.get("steps", []), 1):
            recipes_md += f"{j}. {step}\n"
        recipes_md += "\n---\n\n"

    return (
        annotated,
        det_rows,
        depth_vis,
        depth_rows,
        weight_rows,
        ingredients_text,
        recipes_md or "No recipes generated.",
    )


_yolo_models = _scan_models("yolo", "pt")
_depth_models = _scan_models("depth", "onnx")

with gr.Blocks(title="Visual Ingredient Scanner") as demo:
    gr.Markdown("# Visual Ingredient Scanner\nUpload a kitchen photo and click **Scan**.")

    with gr.Row():
        yolo_dd = gr.Dropdown(
            choices=_yolo_models,
            value=_yolo_models[0] if _yolo_models else None,
            label="YOLO model",
            info="All .pt files in models/yolo/ — hot-swap without restart",
        )
        depth_dd = gr.Dropdown(
            choices=_depth_models,
            value=_depth_models[0] if _depth_models else None,
            label="Depth model",
            info="All .onnx files in models/depth/ — hot-swap without restart",
        )

    with gr.Row():
        inp = gr.Image(type="pil", label="Input image", height=_IMAGE_HEIGHT)

    btn = gr.Button("Scan", variant="primary")

    with gr.Tabs():

        with gr.Tab("① Detection  —  YOLO"):
            gr.Markdown(
                "Raw YOLO bounding boxes.  "
                "Label format: `class  confidence  estimated_weight`."
            )
            out_annotated = gr.Image(type="pil", label="Annotated image", height=_IMAGE_HEIGHT)
            out_det_table = gr.Dataframe(
                headers=_DET_COLS,
                label="All detections",
                interactive=False,
            )

        with gr.Tab("② Depth  —  Depth Anything V2-S"):
            gr.Markdown(
                "Depth map from the ONNX model.  "
                "Plasma colormap — **dark purple = near, bright yellow = far**.  "
                "White boxes show each detected bbox with its median depth."
            )
            out_depth_img = gr.Image(type="pil", label="Depth map + bounding boxes", height=_IMAGE_HEIGHT)
            out_depth_table = gr.Dataframe(
                headers=_DEPTH_COLS,
                label="Per-detection depth & real-world size (pinhole model)",
                interactive=False,
            )

        with gr.Tab("③ Weight Estimation"):
            gr.Markdown(
                "**Pinhole model** → real-world dimensions from bbox pixels + depth.  \n"
                "**Shape heuristic** → volume (sphere / cylinder / box).  \n"
                "**Weight** = volume × density (from Gemini or fallback table).  \n"
                "Volumes are in cm³ (1 m³ = 10⁶ cm³)."
            )
            out_weight_table = gr.Dataframe(
                headers=_WEIGHT_COLS,
                label="Weight estimation details",
                interactive=False,
            )

        with gr.Tab("④ Ingredients"):
            gr.Markdown(
                "Aggregated weight per ingredient class.  "
                "Multiple detections of the same class are summed."
            )
            out_ingredients = gr.Textbox(label="Detected ingredients & weights", lines=12)

        with gr.Tab("⑤ Recipes  —  Gemini"):
            gr.Markdown(
                "Three ranked recipe suggestions generated by Gemini "
                "based on detected ingredients and their estimated weights."
            )
            out_recipes = gr.Markdown()

    btn.click(
        fn=scan,
        inputs=[inp, yolo_dd, depth_dd],
        outputs=[
            out_annotated, out_det_table,
            out_depth_img, out_depth_table,
            out_weight_table,
            out_ingredients,
            out_recipes,
        ],
    )

if __name__ == "__main__":
    demo.launch()
