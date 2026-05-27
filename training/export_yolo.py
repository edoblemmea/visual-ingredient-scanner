"""Export fine-tuned YOLO11s to TFLite (Android) and CoreML (iOS).

Run after training:
    python training/export_yolo.py --weights runs/train/food_detector/weights/best.pt
"""

from __future__ import annotations
import argparse
from pathlib import Path

from ultralytics import YOLO


def export(weights: str) -> None:
    model = YOLO(weights)

    # INT8 TFLite for Android
    model.export(format="tflite", int8=True, imgsz=640)
    print("TFLite export done.")

    # CoreML for iOS
    model.export(format="coreml", imgsz=640)
    print("CoreML export done.")

    # Copy exports to models/yolo/
    src = Path(weights).parent
    dst = Path("models/yolo")
    dst.mkdir(parents=True, exist_ok=True)
    for suffix in ("_int8.tflite", ".mlpackage"):
        for f in src.glob(f"*{suffix}"):
            target = dst / ("food_detector" + suffix)
            f.replace(target)
            print(f"Moved {f.name} → {target}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--weights",
        default="runs/train/food_detector/weights/best.pt",
        help="Path to fine-tuned .pt checkpoint",
    )
    args = parser.parse_args()
    export(args.weights)
