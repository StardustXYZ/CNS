"""Name and title normalization, so the same name matches across spellings (from CNV)."""

from __future__ import annotations

import re
import unicodedata


def normalize_title(raw: str) -> str:
    """Lowercase, strip accents and punctuation so names and titles match across sources."""
    t = unicodedata.normalize("NFKD", raw.strip().lower())
    t = "".join(ch for ch in t if not unicodedata.combining(ch))
    t = re.sub(r"[^\w\s]", " ", t)
    t = re.sub(r"\s+", " ", t)
    return t.strip()
