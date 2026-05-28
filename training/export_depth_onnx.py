"""Export Depth Anything V2 Small (metric indoor) to ONNX.

The model is used pretrained — no fine-tuning.
Apache 2.0 licence — do NOT switch to V2-Base or V2-Large (CC-BY-NC).

Run once:
    python training/export_depth_onnx.py

Output: models/depth/depth_anything_v2_small.onnx
"""

from __future__ import annotations
from pathlib import Path

import torch
from transformers import AutoModelForDepthEstimation


# Use the metric-indoor checkpoint so the ONNX outputs actual metres.
# The relative checkpoint ("depth-anything/Depth-Anything-V2-Small") outputs
# unitless disparity and requires post-hoc normalisation — avoid it.
_CHECKPOINT = "depth-anything/Depth-Anything-V2-Small-Metric-Indoor-hf"
_OUT_PATH = Path("models/depth/depth_anything_v2_small.onnx")
_INPUT_SIZE = (518, 518)


def export() -> None:
    print(f"Loading {_CHECKPOINT} ...")
    model = AutoModelForDepthEstimation.from_pretrained(_CHECKPOINT)
    model.eval()

    dummy = torch.zeros(1, 3, *_INPUT_SIZE)

    _OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        model,
        dummy,
        str(_OUT_PATH),
        input_names=["pixel_values"],
        output_names=["predicted_depth"],
        dynamic_axes={
            "pixel_values": {0: "batch"},
            "predicted_depth": {0: "batch"},
        },
        opset_version=17,
    )
    print(f"ONNX export saved to {_OUT_PATH}")

    # Validate
    import onnxruntime as ort
    import numpy as np

    sess = ort.InferenceSession(str(_OUT_PATH), providers=["CPUExecutionProvider"])
    out = sess.run(None, {"pixel_values": dummy.numpy()})
    print(f"Validation OK — output shape: {out[0].shape}")


if __name__ == "__main__":
    export()
