from ultralytics import YOLO
from PIL import Image
import sys

img_path = sys.argv[1] if len(sys.argv) > 1 else input("Image path: ")

model = YOLO("models/yolo/food_detector.pt")
img = Image.open(img_path)

results = model(img, conf=0.01)[0]
print(f"\nTotal detections at conf=0.01: {len(results.boxes)}")
print(f"{'Class':<25} {'Confidence':>10}")
print("-" * 37)
for box in sorted(results.boxes, key=lambda b: float(b.conf), reverse=True):
    print(f"{results.names[int(box.cls)]:<25} {float(box.conf):>10.3f}")
