"""Gradio laptop demo — Phase 2 deliverable.

Run:  python prototype/app.py
Then open http://localhost:7860 in a browser and upload a kitchen photo.
"""

from __future__ import annotations
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import gradio as gr
from PIL import Image, ImageDraw

from pipeline.pipeline import run


_YOLO_MODEL = "models/yolo/food_detector.pt"
_DEPTH_MODEL = "models/depth/depth_anything_v2_small.onnx"


def _annotate(image: Image.Image, detections: list[dict]) -> Image.Image:
    draw = ImageDraw.Draw(image)
    for d in detections:
        x1, y1, x2, y2 = d["bbox"]
        label = f"{d['class']} {d['weight_g']:.0f}g"
        draw.rectangle([x1, y1, x2, y2], outline="lime", width=3)
        draw.text((x1 + 4, y1 + 4), label, fill="lime")
    return image


def scan(image: Image.Image) -> tuple[Image.Image, str, str]:
    if image is None:
        return None, "No image provided.", ""

    result = run(image, _YOLO_MODEL, _DEPTH_MODEL)

    annotated = _annotate(image.copy(), result["detections"])

    weights_text = "\n".join(
        f"• {name}: {w:.0f} g" for name, w in result["weights"].items()
    ) or "No ingredients detected."

    recipes_text = ""
    for i, r in enumerate(result.get("recipes", []), 1):
        recipes_text += f"**{i}. {r['name']}** (serves {r.get('servings', '?')})\n"
        recipes_text += "\n".join(f"  {step}" for step in r.get("steps", [])) + "\n\n"

    return annotated, weights_text, recipes_text or "No recipes generated."


with gr.Blocks(title="Visual Ingredient Scanner") as demo:
    gr.Markdown("# Visual Ingredient Scanner\nUpload a photo of your fridge or kitchen counter.")

    with gr.Row():
        inp = gr.Image(type="pil", label="Input image")
        out_img = gr.Image(type="pil", label="Detected ingredients")

    btn = gr.Button("Scan", variant="primary")

    with gr.Row():
        out_weights = gr.Textbox(label="Detected ingredients & weights", lines=8)
        out_recipes = gr.Markdown(label="Recipe suggestions")

    btn.click(fn=scan, inputs=inp, outputs=[out_img, out_weights, out_recipes])

if __name__ == "__main__":
    demo.launch()
