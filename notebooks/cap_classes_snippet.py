import random
from collections import defaultdict, Counter
from pathlib import Path

MAX_INSTANCES = 2000
label_dir = MERGED_DIR / "train" / "labels"
img_dir   = MERGED_DIR / "train" / "images"

# Build a map: file -> {cls: instance_count}
file_instances = {}
for lf in label_dir.glob("*.txt"):
    content = lf.read_text().strip()
    if not content:
        continue
    counts = Counter(
        int(line.split()[0])
        for line in content.splitlines() if line
    )
    file_instances[lf] = counts

# For each class, list (file, instance_count_in_file)
class_data = defaultdict(list)
for lf, counts in file_instances.items():
    for cls, cnt in counts.items():
        class_data[cls].append((lf, cnt))

# Print over-represented classes before capping
print(f"{'Class':<25} {'Instances':>10}")
print("-" * 37)
for cls in sorted(class_data,
                  key=lambda c: sum(cnt for _, cnt in class_data[c]),
                  reverse=True):
    total = sum(cnt for _, cnt in class_data[c])
    if total > MAX_INSTANCES:
        solo  = sum(1 for lf, _ in class_data[c] if len(file_instances[lf]) == 1)
        mixed = sum(1 for lf, _ in class_data[c] if len(file_instances[lf]) > 1)
        print(f"{MASTER_CLASSES[cls]:<25} {total:>10}  (solo files: {solo}, mixed files: {mixed})")

# ── Cap each class by instance count ─────────────────────────────────────────
removed_files = set()

for cls in sorted(class_data,
                  key=lambda c: sum(cnt for _, cnt in class_data[c]),
                  reverse=True):

    available = [(lf, cnt) for lf, cnt in class_data[cls]
                 if lf not in removed_files]
    total_instances = sum(cnt for _, cnt in available)

    if total_instances <= MAX_INSTANCES:
        continue

    instances_to_remove = total_instances - MAX_INSTANCES

    # Separate solo (no collateral) vs mixed (affects other classes)
    solo_items  = [(lf, cnt) for lf, cnt in available
                   if len(file_instances[lf]) == 1]
    mixed_items = [(lf, cnt) for lf, cnt in available
                   if len(file_instances[lf]) > 1]

    random.shuffle(solo_items)
    random.shuffle(mixed_items)

    # Step 1 — delete solo files first
    for lf, cnt in solo_items:
        if instances_to_remove <= 0:
            break
        removed_files.add(lf)
        instances_to_remove -= cnt

    # Step 2 — delete mixed files only if still needed
    if instances_to_remove > 0:
        for lf, cnt in mixed_items:
            if instances_to_remove <= 0:
                break
            removed_files.add(lf)
            instances_to_remove -= cnt

    removed_count = sum(
        cnt for lf, cnt in available if lf in removed_files
    )
    print(f"{MASTER_CLASSES[cls]:<25} {total_instances} → ~{total_instances - removed_count}")

# ── Physically delete files ───────────────────────────────────────────────────
for lf in removed_files:
    for ext in (".jpg", ".jpeg", ".png", ".JPG", ".JPEG", ".PNG"):
        img = img_dir / (lf.stem + ext)
        if img.exists():
            img.unlink()
            break
    lf.unlink(missing_ok=True)

print(f"\nDeleted {len(removed_files)} files.")
print("Re-run Cell 7 to verify the new distribution.")
