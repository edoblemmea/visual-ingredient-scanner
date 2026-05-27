"""Gemini recipe generation — returns 3 ranked recipe suggestions as structured JSON."""

from __future__ import annotations
import json
import os

import google.generativeai as genai
from dotenv import load_dotenv

load_dotenv()

_PROMPT_TEMPLATE = """\
You are a helpful recipe assistant. Given the following detected ingredients and their \
estimated weights, suggest exactly 3 ranked recipes that make good use of the available \
quantities. Adapt suggestions to the amounts (e.g., if there is only 120g of pasta, suggest \
a single-serving dish). Return ONLY a JSON array with this structure, no explanation:
[
  {{
    "name": "Recipe name",
    "ingredients_used": ["ingredient amount", ...],
    "steps": ["Step 1", "Step 2", ...],
    "servings": 2
  }}
]

Available ingredients:
{ingredients}
"""


def generate_recipes(ingredients: dict[str, float]) -> list[dict]:
    """
    ingredients: mapping of class_name → weight_g
    Returns a list of 3 recipe dicts.
    """
    ingredient_lines = "\n".join(
        f"- {name}: {weight:.0f}g" for name, weight in ingredients.items()
    )
    prompt = _PROMPT_TEMPLATE.format(ingredients=ingredient_lines)

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        return [{"name": "API key not configured", "ingredients_used": [], "steps": [], "servings": 0}]

    genai.configure(api_key=api_key)
    model = genai.GenerativeModel("gemini-2.0-flash-lite")
    response = model.generate_content(prompt)
    text = response.text.strip()
    if text.startswith("```"):
        text = "\n".join(text.split("\n")[1:-1])

    return json.loads(text)
