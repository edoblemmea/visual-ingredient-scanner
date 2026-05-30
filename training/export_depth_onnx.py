"""Download and export Depth Anything V2 Small to ONNX.

Downloads from HuggingFace and wraps the model so torch.onnx.export sees plain
tensor inputs/outputs (transformers returns a DepthEstimatorOutput object which
breaks ONNX export without the wrapper).

Apache 2.0 — do NOT switch to V2-Base or V2-Large (CC-BY-NC).

Run from repo root:
    python training/export_depth_onnx.py

Output: models/depth/depth_anything_v2_small.onnx
"""

from __future__ import annotations
import argparse
from pathlib import Path

import torch
import torch.nn as nn
import onnxruntime as ort
from transformers import AutoModelForDepthEstimation


_HF_REPO = "depth-anything/Depth-Anything-V2-Metric-Indoor-Small-hf"
_OUT_PATH = Path("models/depth/depth_anything_v2_small.onnx")
_INPUT_SIZE = (518, 518)   # must match depth.py _INPUT_SIZE


class _DepthWrapper(nn.Module):
    """Strip the DepthEstimatorOutput wrapper so ONNX export sees a plain tensor."""

    def __init__(self, model: nn.Module) -> None:
        super().__init__()
        self.model = model

    def forward(self, pixel_values: torch.Tensor) -> torch.Tensor:
        return self.model(pixel_values=pixel_values).predicted_depth


def export(out_path: Path = _OUT_PATH, repo: str = _HF_REPO) -> None:
    print(f"Downloading {repo} ...")
    base_model = AutoModelForDepthEstimation.from_pretrained(repo)
    base_model.eval()

    model = _DepthWrapper(base_model)

    dummy = torch.zeros(1, 3, *_INPUT_SIZE)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"Exporting to {out_path} (opset 17) ...")
    torch.onnx.export(
        model,
        dummy,
        str(out_path),
        input_names=["pixel_values"],
        output_names=["predicted_depth"],
        dynamic_axes={
            "pixel_values": {0: "batch"},
            "predicted_depth": {0: "batch"},
        },
        opset_version=17,
        do_constant_folding=True,
    )
    print(f"Saved: {out_path}  ({out_path.stat().st_size / 1e6:.1f} MB)")

    print("Validating with onnxruntime ...")
    sess = ort.InferenceSession(str(out_path), providers=["CPUExecutionProvider"])
    out = sess.run(None, {"pixel_values": dummy.numpy()})
    assert out[0].shape[-2:] == _INPUT_SIZE, f"unexpected output shape: {out[0].shape}"
    print(f"Validation OK — output shape: {out[0].shape}, "
          f"range [{out[0].min():.3f}, {out[0].max():.3f}]")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Export Depth Anything V2 Small to ONNX")
    parser.add_argument("--out", default=str(_OUT_PATH), help="output .onnx path")
    parser.add_argument("--repo", default=_HF_REPO, help="HuggingFace repo ID")
    args = parser.parse_args()
    export(Path(args.out), args.repo)
