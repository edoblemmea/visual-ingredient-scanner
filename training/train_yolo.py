"""YOLO11s fine-tuning script — designed to run on Google Colab with a T4 GPU.

Usage (Colab cell):
    !python training/train_yolo.py --data data/food.yaml --epochs 50 --imgsz 640
"""

from __future__ import annotations
import argparse

from ultralytics import YOLO


def train(data: str, epochs: int, imgsz: int, batch: int, device: str) -> None:
    model = YOLO("yolo11s.pt")  # downloads base checkpoint automatically
    model.train(
        data=data,
        epochs=epochs,
        imgsz=imgsz,
        batch=batch,
        device=device,
        project="runs/train",
        name="food_detector",
        exist_ok=True,
        augment=True,
        cos_lr=True,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", default="data/food.yaml", help="Roboflow dataset YAML")
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--batch", type=int, default=16)
    parser.add_argument("--device", default="0", help="GPU index or 'cpu'")
    args = parser.parse_args()

    train(args.data, args.epochs, args.imgsz, args.batch, args.device)
