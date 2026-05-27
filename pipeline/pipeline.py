"""End-to-end pipeline: image → detections → depth → weights → recipes."""

from __future__ import annotations
from pathlib import Path

from PIL import Image

from .detect import Detector
from .depth import DepthEstimator
from .density import get_densities
from .weight import estimate_weights
from .recipe import generate_recipes


_DEFAULT_YOLO = Path("models/yolo/food_detector.pt")
_DEFAULT_DEPTH = Path("models/depth/depth_anything_v2_small.onnx")


def run(
    image_path: str | Path,
    yolo_model: str | Path = _DEFAULT_YOLO,
    depth_model: str | Path = _DEFAULT_DEPTH,
) -> dict:
    if isinstance(image_path, Image.Image):
        image = image_path.convert("RGB")
    else:
        image = Image.open(image_path).convert("RGB")

    detector = Detector(yolo_model)
    detections = detector.detect(image)
    if not detections:
        return {"detections": [], "weights": {}, "recipes": []}

    depth_estimator = DepthEstimator(depth_model)
    depth_map = depth_estimator.estimate(image)

    class_names = list({d.class_name for d in detections})
    densities = get_densities(class_names)

    weighted = estimate_weights(detections, depth_map, densities, image)

    ingredient_weights: dict[str, float] = {}
    for w in weighted:
        name = w.detection.class_name
        ingredient_weights[name] = ingredient_weights.get(name, 0.0) + w.weight_g

    recipes = generate_recipes(ingredient_weights)

    return {
        "detections": [
            {
                "class": w.detection.class_name,
                "confidence": round(w.detection.confidence, 3),
                "bbox": w.detection.bbox_xyxy,
                "depth_m": round(w.depth_m, 3),
                "weight_g": round(w.weight_g, 1),
            }
            for w in weighted
        ],
        "weights": {k: round(v, 1) for k, v in ingredient_weights.items()},
        "recipes": recipes,
    }


if __name__ == "__main__":
    import argparse
    import json

    parser = argparse.ArgumentParser(description="Visual Ingredient Scanner — full pipeline")
    parser.add_argument("--image", required=True, help="Path to input image")
    parser.add_argument("--yolo", default=str(_DEFAULT_YOLO))
    parser.add_argument("--depth", default=str(_DEFAULT_DEPTH))
    args = parser.parse_args()

    result = run(args.image, args.yolo, args.depth)
    print(json.dumps(result, indent=2))
