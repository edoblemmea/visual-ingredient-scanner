"""Gradio laptop demo — Phase 2 deliverable.

Run:  python prototype/app.py
Then open http://localhost:7860 in a browser and upload a kitchen photo.
"""

from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import gradio as gr
from PIL import Image, ImageDraw

from pipeline.pipeline import run


_REPO_ROOT = Path(__file__).parent.parent


def _scan_models(subdir: str, ext: str) -> list[str]:
    """Return repo-root-relative paths for all model files in models/<subdir>/."""
    folder = _REPO_ROOT / "models" / subdir
    if not folder.exists():
        return []
    return sorted(str(p.relative_to(_REPO_ROOT)) for p in folder.glob(f"*.{ext}"))


def _annotate(image: Image.Image, detections: list[dict]) -> Image.Image:
    draw = ImageDraw.Draw(image)
    for d in detections:
        x1, y1, x2, y2 = d["bbox"]
        label = f"{d['class']} {d['weight_g']:.0f}g"
        draw.rectangle([x1, y1, x2, y2], outline="lime", width=3)
        draw.text((x1 + 4, y1 + 4), label, fill="lime")
    return image


def scan(image: Image.Image, yolo_model: str, depth_model: str) -> tuple:
    if image is None:
        return None, "No image provided.", ""

    result = run(image, yolo_model, depth_model)

    annotated = _annotate(image.copy(), result["detections"])

    weights_text = "\n".join(
        f"• {name}: {w:.0f} g" for name, w in result["weights"].items()
    ) or "No ingredients detected."

    recipes_text = ""
    for i, r in enumerate(result.get("recipes", []), 1):
        recipes_text += f"**{i}. {r['name']}** (serves {r.get('servings', '?')})\n"
        recipes_text += "\n".join(f"  {step}" for step in r.get("steps", [])) + "\n\n"

    return annotated, weights_text, recipes_text or "No recipes generated."


_yolo_models = _scan_models("yolo", "pt")
_depth_models = _scan_models("depth", "onnx")

with gr.Blocks(title="Visual Ingredient Scanner") as demo:
    gr.Markdown("# Visual Ingredient Scanner\nUpload a photo of your fridge or kitchen counter.")

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
        inp = gr.Image(type="pil", label="Input image")
        out_img = gr.Image(type="pil", label="Detected ingredients")

    btn = gr.Button("Scan", variant="primary")

    with gr.Row():
        out_weights = gr.Textbox(label="Detected ingredients & weights", lines=8)
        out_recipes = gr.Markdown(label="Recipe suggestions")

    btn.click(
        fn=scan,
        inputs=[inp, yolo_dd, depth_dd],
        outputs=[out_img, out_weights, out_recipes],
    )

if __name__ == "__main__":
    demo.launch()
