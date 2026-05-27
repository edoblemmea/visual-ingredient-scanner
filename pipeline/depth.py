"""Depth Anything V2-S ONNX inference wrapper — returns a metric depth map in metres."""

from __future__ import annotations
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image


_INPUT_SIZE = (518, 518)
_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)


class DepthEstimator:
    def __init__(self, model_path: str | Path) -> None:
        self.session = ort.InferenceSession(
            str(model_path),
            providers=["CPUExecutionProvider"],
        )
        self._input_name = self.session.get_inputs()[0].name

    def estimate(self, image: Image.Image) -> np.ndarray:
        """Return a depth map (H, W) in metres, resized to original image dimensions."""
        orig_w, orig_h = image.size
        resized = image.resize(_INPUT_SIZE, Image.BILINEAR).convert("RGB")
        arr = np.array(resized, dtype=np.float32) / 255.0
        arr = (arr - _MEAN) / _STD
        tensor = arr.transpose(2, 0, 1)[np.newaxis]  # (1, 3, H, W)

        depth = self.session.run(None, {self._input_name: tensor})[0]  # (1, H, W) or (H, W)
        depth = np.squeeze(depth)

        # Resize back to original image resolution
        depth_img = Image.fromarray(depth).resize((orig_w, orig_h), Image.BILINEAR)
        return np.array(depth_img)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True)
    parser.add_argument("--model", default="models/depth/depth_anything_v2_small.onnx")
    parser.add_argument("--out", default="depth_output.npy")
    args = parser.parse_args()

    estimator = DepthEstimator(args.model)
    img = Image.open(args.image)
    depth_map = estimator.estimate(img)
    np.save(args.out, depth_map)
    print(f"Depth map saved to {args.out}, shape={depth_map.shape}, "
          f"min={depth_map.min():.2f}m, max={depth_map.max():.2f}m")
