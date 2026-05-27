# ── Run merge ────────────────────────────────────────────────────────────────
total = {"train": 0, "valid": 0, "test": 0}

data_yaml = yaml.safe_load(Path(RAW_DIR, "data.yaml").read_text())
source_names = data_yaml["names"]
remap = build_remap(source_names, RENAME_MAP, SKIP_SET)

kept    = sum(1 for v in remap.values() if v >= 0)
skipped = sum(1 for v in remap.values() if v < 0)
print(f"Source classes : {len(source_names)}")
print(f"Kept           : {kept}")
print(f"Skipped        : {skipped}")

for split in ("train", "valid", "test"):
    total[split] = merge_split(RAW_DIR, split, remap, 0)

merged_yaml = {
    "path":  str(MERGED_DIR),
    "train": "train/images",
    "val":   "valid/images",
    "test":  "test/images",
    "nc":    len(MASTER_CLASSES),
    "names": MASTER_CLASSES,
}
MERGED_YAML = str(MERGED_DIR / "data.yaml")
with open(MERGED_YAML, "w") as f:
    yaml.dump(merged_yaml, f, default_flow_style=False, sort_keys=False)

print("=" * 50)
print(f"Merged dataset: {MERGED_DIR}")
print(f"  train : {total['train']} images")
print(f"  valid : {total['valid']} images")
print(f"  test  : {total['test']} images")
print(f"  total : {sum(total.values())} images")
print(f"  classes: {len(MASTER_CLASSES)}")
