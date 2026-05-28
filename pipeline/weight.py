"""Pinhole model + shape heuristics — converts bbox + depth map + density to weight in grams."""

from __future__ import annotations
import math
from dataclasses import dataclass

import numpy as np
from PIL import Image

from .detect import Detection


_DEFAULT_FOCAL_RATIO = 0.8  # focal_px = image_width_px * 0.8 when EXIF is absent

# Shape heuristic mapping: exact class name → shape
_SPHERE_CLASSES = {
    # fruits
    "apple", "avocado", "blackberries", "blueberries", "cantaloupe", "coconut",
    "fig", "grapes", "grapefruit", "kiwi", "lemon", "lime", "mango", "orange",
    "peach", "pear", "pomegranate", "raspberries", "strawberries", "watermelon",
    # vegetables
    "artichoke", "beet", "brussels_sprouts", "cabbage", "cauliflower", "egg",
    "garlic", "mushrooms", "onion", "peas", "potato", "pumpkin", "radish",
    "sweet_potato", "tomato",
}
_CYLINDER_CLASSES = {
    # fruits & vegetables
    "banana", "carrot", "celery", "chili", "corn", "cucumber", "eggplant",
    "green_beans", "okra", "pineapple", "zucchini",
    # dairy & packaged
    "heavy_cream", "honey", "hummus", "jam", "juice", "mayonnaise",
    "oil", "soda", "tomato_sauce", "vinegar", "water", "yogurt",
}
# everything else → box


def _get_focal_length_px(image: Image.Image) -> float:
    try:
        exif = image._getexif()  # type: ignore[attr-defined]
        if exif:
            focal_35mm = exif.get(0xA405)  # FocalLengthIn35mmFilm tag
            if focal_35mm:
                sensor_width_35mm = 36.0  # mm
                return (focal_35mm / sensor_width_35mm) * image.width
    except Exception:
        pass
    return image.width * _DEFAULT_FOCAL_RATIO


def _volume_m3(shape: str, w: float, h: float) -> float:
    """Estimate volume from real-world bounding-box dimensions (in metres)."""
    if shape == "sphere":
        d = min(w, h)
        return (4 / 3) * math.pi * (d / 2) ** 3
    if shape == "cylinder":
        r = w / 2
        return math.pi * r ** 2 * h
    # box — 0.5 factor for 2-D projection of 3-D object
    return w * h * max(w, h) * 0.5


def _shape_for_class(class_name: str) -> str:
    name = class_name.lower()
    if name in _SPHERE_CLASSES:
        return "sphere"
    if name in _CYLINDER_CLASSES:
        return "cylinder"
    return "box"


@dataclass
class WeightedDetection:
    detection: Detection
    depth_m: float
    real_width_m: float
    real_height_m: float
    volume_m3: float
    density_kg_m3: float
    weight_g: float


# Assumed median distance from phone to food for a typical kitchen photo.
# Used to anchor the relative depth scale to actual metres.
_TARGET_FOOD_DEPTH_M = 0.50


def estimate_weights(
    detections: list[Detection],
    depth_map: np.ndarray,
    densities: dict[str, float],
    image: Image.Image,
) -> list[WeightedDetection]:
    focal_px = _get_focal_length_px(image)

    # The ONNX depth model outputs relative (not metric) depth.
    # Scale the whole depth map so the median depth across all food bboxes = 0.5 m,
    # anchoring to the typical phone-to-counter distance in a kitchen photo.
    food_medians: list[float] = []
    for det in detections:
        x1, y1, x2, y2 = det.bbox_xyxy
        roi = depth_map[y1:y2, x1:x2]
        if roi.size > 0:
            food_medians.append(float(np.median(roi)))
    if food_medians:
        median_scene_depth = float(np.median(food_medians))
        if median_scene_depth > 0:
            depth_map = depth_map * (_TARGET_FOOD_DEPTH_M / median_scene_depth)

    results: list[WeightedDetection] = []

    for det in detections:
        x1, y1, x2, y2 = det.bbox_xyxy
        roi = depth_map[y1:y2, x1:x2]
        if roi.size == 0:
            continue
        depth_m = float(np.median(roi))
        depth_m = float(np.clip(depth_m, 0.3, 3.0))  # clamp to indoor range (matches depth normalisation)

        bbox_w_px = x2 - x1
        bbox_h_px = y2 - y1
        real_w = (bbox_w_px / focal_px) * depth_m
        real_h = (bbox_h_px / focal_px) * depth_m

        shape = _shape_for_class(det.class_name)
        vol = _volume_m3(shape, real_w, real_h)

        density = densities.get(det.class_name, 800.0)  # 800 kg/m³ as last-resort default
        weight_g = vol * density * 1000.0

        results.append(WeightedDetection(
            detection=det,
            depth_m=depth_m,
            real_width_m=real_w,
            real_height_m=real_h,
            volume_m3=vol,
            density_kg_m3=density,
            weight_g=weight_g,
        ))

    return results
