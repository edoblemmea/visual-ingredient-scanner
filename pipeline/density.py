"""Static food-density lookup (kg/m³) — no network calls.

Stage ③ of the pipeline reads curated real-world bulk densities for every class
from data/food_densities.json instead of querying an external model.
"""

from __future__ import annotations
import json
from pathlib import Path

_DENSITIES_PATH = Path("data/food_densities.json")
_DEFAULT_DENSITY = 800.0  # kg/m³ — last-resort default for a class not in the table


def _load_densities() -> dict[str, float]:
    if _DENSITIES_PATH.exists():
        return json.loads(_DENSITIES_PATH.read_text())
    return {}


def get_densities(class_names: list[str]) -> dict[str, float]:
    """Return density (kg/m³) for each requested class from the static table."""
    table = _load_densities()
    return {c: float(table.get(c, _DEFAULT_DENSITY)) for c in class_names}
