"""Depth model ONNX wrappers — return a metric depth map in metres.

Two model families are supported, auto-detected from the ONNX outputs:

  • Metric3D (ViT-Small) — outputs predicted_depth + predicted_normal. Needs the
    canonical-camera recipe: resize keeping aspect, pad to 616x1064, run, then
    DE-CANONICALISE the output with the real focal length to get true metres.
    This is the model that actually drives absolute distance.

  • Depth Anything V2 (metric-indoor) — single predicted_depth output, 518x518
    square input, already in metres. Returned as-is.
"""

from __future__ import annotations
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort
from PIL import Image

from .weight import _get_focal_length_px


# Depth Anything V2 preprocessing
_DA_INPUT_SIZE = (518, 518)
_DA_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
_DA_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)

# Metric3D canonical-camera preprocessing (pixel values in 0–255 scale)
_M3D_INPUT = (616, 1064)  # (H, W) — both multiples of 14
_M3D_MEAN = np.array([123.675, 116.28, 103.53], dtype=np.float32)
_M3D_STD = np.array([58.395, 57.12, 57.375], dtype=np.float32)
_M3D_PAD = (123.675, 116.28, 103.53)
_M3D_CANONICAL_FOCAL = 1000.0  # focal the model was canonicalised to during training


class DepthEstimator:
    def __init__(self, model_path: str | Path) -> None:
        self.session = ort.InferenceSession(
            str(model_path),
            providers=["CPUExecutionProvider"],
        )
        self._input_name = self.session.get_inputs()[0].name
        out_names = {o.name for o in self.session.get_outputs()}
        self._is_metric3d = "predicted_normal" in out_names or len(out_names) > 1

    def estimate(self, image: Image.Image) -> np.ndarray:
        """Return a metric depth map (H, W) in metres, at the original resolution."""
        if self._is_metric3d:
            return self._estimate_metric3d(image)
        return self._estimate_depth_anything(image)

    def _estimate_depth_anything(self, image: Image.Image) -> np.ndarray:
        orig_w, orig_h = image.size
        resized = image.resize(_DA_INPUT_SIZE, Image.BILINEAR).convert("RGB")
        arr = np.array(resized, dtype=np.float32) / 255.0
        arr = (arr - _DA_MEAN) / _DA_STD
        tensor = arr.transpose(2, 0, 1)[np.newaxis]  # (1, 3, H, W)

        depth = self.session.run(None, {self._input_name: tensor})[0]
        depth = np.squeeze(depth).astype(np.float32)

        depth_img = Image.fromarray(depth).resize((orig_w, orig_h), Image.BILINEAR)
        return np.array(depth_img, dtype=np.float32)

    def _estimate_metric3d(self, image: Image.Image) -> np.ndarray:
        focal_px = _get_focal_length_px(image)
        rgb = np.array(image.convert("RGB"), dtype=np.float32)
        h, w = rgb.shape[:2]

        # Keep-aspect resize to fit the canonical input, then centre-pad to 616x1064.
        scale = min(_M3D_INPUT[0] / h, _M3D_INPUT[1] / w)
        rs = cv2.resize(rgb, (round(w * scale), round(h * scale)), interpolation=cv2.INTER_LINEAR)
        rh, rw = rs.shape[:2]
        pad_top = (_M3D_INPUT[0] - rh) // 2
        pad_left = (_M3D_INPUT[1] - rw) // 2
        pad_bottom = _M3D_INPUT[0] - rh - pad_top
        pad_right = _M3D_INPUT[1] - rw - pad_left
        padded = cv2.copyMakeBorder(
            rs, pad_top, pad_bottom, pad_left, pad_right,
            cv2.BORDER_CONSTANT, value=_M3D_PAD,
        )

        tensor = ((padded - _M3D_MEAN) / _M3D_STD).transpose(2, 0, 1)[np.newaxis]
        depth = self.session.run(["predicted_depth"], {self._input_name: tensor})[0]
        depth = np.squeeze(depth).astype(np.float32)

        # Un-pad, restore original resolution.
        depth = depth[pad_top:_M3D_INPUT[0] - pad_bottom, pad_left:_M3D_INPUT[1] - pad_right]
        depth = cv2.resize(depth, (w, h), interpolation=cv2.INTER_LINEAR)

        # De-canonicalise: the prediction is in canonical-focal space; scale it back
        # to real metres using the (resized) focal length.
        depth = depth * (focal_px * scale / _M3D_CANONICAL_FOCAL)
        return depth.astype(np.float32)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True)
    parser.add_argument("--model", default="models/depth/metric3d-vit-small.onnx")
    parser.add_argument("--out", default="depth_output.npy")
    args = parser.parse_args()

    estimator = DepthEstimator(args.model)
    img = Image.open(args.image)
    depth_map = estimator.estimate(img)
    np.save(args.out, depth_map)
    print(f"Depth map saved to {args.out}, shape={depth_map.shape}, "
          f"min={depth_map.min():.2f}m, max={depth_map.max():.2f}m")
