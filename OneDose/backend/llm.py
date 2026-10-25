# File: backend/llm.py
# Owner: Bhavya  (only the owner edits this file)
# Purpose: Turn an alert row into two plain sentences with Gemini. Check the answer only mentions ingredients from the alert; otherwise return a fixed template sentence. Wording only, never a safety decision.
# Inputs: One alert row (a dict from fn_check_prescription) and the list of all ingredient names.
# Outputs: Explanation text.
# Depends on: config.py
#
# The model sees only the alert row. Its answer is used only if is_grounded() passes:
#   - at most two sentences,
#   - no ingredient name other than the alert's own (checked against the full ingredient list),
#   - no number that is not already in the alert row.
# On any failure (no key, timeout, bad answer) the fixed template is used, so an alert always has an explanation.
import re

import httpx

from config import settings

URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
_cache: dict[tuple, str] = {}


def _names(alert: dict) -> list[str]:
    return [n for n in (alert.get("ingredient_name"), alert.get("related_ingredient_name")) if n]


def _sentence(text: str | None) -> str:
    text = (text or "").strip()
    return text if not text or text[-1] in ".!?" else text + "."


def template(alert: dict) -> str:
    """Fixed wording, built only from the alert row."""
    a = alert.get("ingredient_name") or "This medicine"
    b = alert.get("related_ingredient_name") or "another medicine"
    mech, how = (alert.get("mechanism") or "").strip().rstrip("."), _sentence(alert.get("management"))
    why = f" ({mech})" if mech else ""
    first = {
        "duplicate": f"{a} is already part of a medicine this patient takes, so this prescription would double up on it.",
        "interaction": f"{a} interacts with {b}, which the patient already takes{why}.",
        "allergy": f"The patient has a recorded allergy that covers {a}.",
        "contraindication": f"{a} is not recommended for a condition this patient has.",
        "dose_limit": f"The total daily dose of {a} would go above the limit for this patient's age band.",
    }.get(alert.get("check_type"), f"{a} was flagged for this patient.")
    return f"{first} {how}".strip() if how else first


def is_grounded(text: str, alert: dict, vocabulary) -> bool:
    low = text.lower()
    own = {n.lower() for n in _names(alert)}
    for name in vocabulary:
        name = name.lower()
        if name not in own and re.search(rf"\b{re.escape(name)}\b", low):
            return False
    facts = " ".join(str(v) for v in alert.values() if v is not None)
    known_numbers = set(re.findall(r"\d+(?:\.\d+)?", facts))
    if any(n not in known_numbers for n in re.findall(r"\d+(?:\.\d+)?", text)):
        return False
    sentences = [s for s in re.split(r"(?<=[.!?])\s+", text.strip()) if s]
    return 1 <= len(sentences) <= 2 and len(text) <= 400


def _prompt(alert: dict) -> str:
    facts = {k: alert.get(k) for k in ("check_type", "severity", "ingredient_name", "related_ingredient_name",
                                       "mechanism", "management", "detail", "source_name") if alert.get(k)}
    lines = "\n".join(f"- {k}: {v}" for k, v in facts.items())
    return ("You explain one drug-safety alert to a busy doctor in exactly two short plain sentences.\n"
            "Use ONLY the facts below. Do not name any other medicine, do not add numbers, do not give new advice.\n"
            f"Facts:\n{lines}")


async def _post(prompt: str) -> str:
    """One call to Gemini. Tests replace this function."""
    async with httpx.AsyncClient(timeout=5.0) as client:
        resp = await client.post(
            URL.format(model=settings.gemini_model),
            headers={"x-goog-api-key": settings.gemini_api_key},
            json={"contents": [{"parts": [{"text": prompt}]}],
                  "generationConfig": {"temperature": 0.2, "maxOutputTokens": 120}})
        resp.raise_for_status()
        return resp.json()["candidates"][0]["content"]["parts"][0]["text"].strip()


async def explain(alert: dict, vocabulary) -> str:
    key = tuple(alert.get(k) for k in ("check_type", "severity", "ingredient_id", "related_ingredient_id",
                                       "mechanism", "management", "detail"))
    if key in _cache:
        return _cache[key]
    text = template(alert)
    if settings.gemini_api_key:
        try:
            candidate = await _post(_prompt(alert))
            if is_grounded(candidate, alert, vocabulary):
                text = candidate
        except Exception:
            return text  # network or API failure: use the template now, try Gemini again next time
    _cache[key] = text
    return text
