"""Gemini density lookup with local JSON cache."""

from __future__ import annotations
import json
import os
from pathlib import Path

import google.generativeai as genai
from dotenv import load_dotenv

load_dotenv()

_CACHE_PATH = Path("data/density_cache.json")
_FALLBACK_PATH = Path("data/density_fallback.json")

_PROMPT_TEMPLATE = (
    "Return only a JSON object mapping each food class name to its average bulk density "
    "in kg/m³. Classes: {classes}. Include packaging weight for packaged goods. "
    "No explanation, only JSON."
)


def _load_cache() -> dict[str, float]:
    if _CACHE_PATH.exists():
        return json.loads(_CACHE_PATH.read_text())
    return {}


def _save_cache(cache: dict[str, float]) -> None:
    _CACHE_PATH.write_text(json.dumps(cache, indent=2))


def _load_fallback() -> dict[str, float]:
    if _FALLBACK_PATH.exists():
        return json.loads(_FALLBACK_PATH.read_text())
    return {}


def get_densities(class_names: list[str]) -> dict[str, float]:
    """Return density (kg/m³) for each class, querying Gemini only for uncached classes."""
    cache = _load_cache()
    missing = [c for c in class_names if c not in cache]

    if missing:
        api_key = os.environ.get("GEMINI_API_KEY")
        if api_key:
            try:
                genai.configure(api_key=api_key)
                model = genai.GenerativeModel("gemini-2.0-flash-lite")
                prompt = _PROMPT_TEMPLATE.format(classes=", ".join(missing))
                response = model.generate_content(prompt)
                text = response.text.strip()
                # Strip markdown code fences if present
                if text.startswith("```"):
                    text = "\n".join(text.split("\n")[1:-1])
                fetched: dict[str, float] = json.loads(text)
                cache.update(fetched)
                _save_cache(cache)
            except Exception as exc:
                print(f"[density] Gemini call failed: {exc}; using fallback for missing classes")

        # Fill any still-missing classes from static fallback
        fallback = _load_fallback()
        for c in missing:
            if c not in cache:
                cache[c] = fallback.get(c, 800.0)

    return {c: cache.get(c, 800.0) for c in class_names}
