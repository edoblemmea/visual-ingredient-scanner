"""YOLO11s inference wrapper — returns bounding boxes and class labels."""

from __future__ import annotations
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image
from ultralytics import YOLO


@dataclass
class Detection:
    class_name: str
    confidence: float
    bbox_xyxy: tuple[int, int, int, int]  # (x1, y1, x2, y2) in pixels


class Detector:
    def __init__(self, model_path: str | Path) -> None:
        self.model = YOLO(str(model_path))

    def detect(self, image: Image.Image, conf_threshold: float = 0.10) -> list[Detection]:
        results = self.model(image, conf=conf_threshold, verbose=False)[0]
        detections: list[Detection] = []
        for box in results.boxes:
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            detections.append(Detection(
                class_name=results.names[int(box.cls)],
                confidence=float(box.conf),
                bbox_xyxy=(int(x1), int(y1), int(x2), int(y2)),
            ))
        return detections


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True)
    parser.add_argument("--model", default="models/yolo/food_detector.pt")
    args = parser.parse_args()

    detector = Detector(args.model)
    img = Image.open(args.image)
    for d in detector.detect(img):
        print(d)
