"""Merging the versions of a release, as in the app (web/discografia.js): the same rules here.

Deezer lists every version as a separate release (remixes, deluxe and explicit/clean
editions, acoustic and live versions). They share one key: kind + title without the
version marks. The check uses it so that a new remix of a release already seen is not
announced as a new release. The examples in tests/fixtures/doppioni.json are tested on
both sides, so the two versions cannot drift apart.
"""

from __future__ import annotations

import re
import unicodedata

KINDS = ("album", "ep", "single", "featuring", "compile")

# Words that mark a version of the same release, inside "( )", "[ ]" or after " - "
_VERSION_WORDS = re.compile(
    r"\b(deluxe|edition|version|explicit|clean|remaster(ed)?|bonus|expanded|extended|anniversary|remix(es)?|mix"
    r"|sped up|slowed|reverb|acoustic|instrumental|without dialogue|demo|live|feat\.?|ft\.?|featuring|with)\b",
    re.IGNORECASE,
)
_TAIL = re.compile(r"\s*(?:\(([^()]*)\)|\[([^\[\]]*)\]|\s-\s([^-]+))\s*$")
# "(feat. X)", "ft. X", "featuring X", "(with X)": the names after it are the guests
_FEAT = re.compile(r"(?:\b(?:feat|ft)\b\.?|\bfeaturing\b|[(\[]\s*with\b)\s*([^)\]]+)", re.IGNORECASE)


def normalize(text: str) -> str:
    """Lowercase, no accents, punctuation as spaces (the same as normalize() in web/deezer.js)."""
    t = unicodedata.normalize("NFKD", str(text or "").lower())
    t = "".join(ch for ch in t if not unicodedata.combining(ch))
    t = re.sub(r"[^\w\s]|_", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def base_title(title: str) -> str:
    """The title without the version marks: "Sweet but Psycho (Leon Lour Remix)" -> "Sweet but Psycho"."""
    t = str(title or "").strip()
    while True:
        match = _TAIL.search(t)
        if not match:
            return t
        inside = next(g for g in match.groups() if g is not None)
        if not _VERSION_WORDS.search(inside):
            return t
        shorter = t[: match.start()].strip()
        if not shorter:
            return t
        t = shorter


def is_featuring(title: str, artist_name: str) -> bool:
    """True when the artist is a guest named in the title, e.g. "BURN (feat. Ava Max)"."""
    wanted = normalize(artist_name)
    if not wanted:
        return False
    return any(f" {wanted} " in f" {normalize(guests)} " for guests in _FEAT.findall(str(title or "")))


def kind_of(title: str, record_type: str, artist_name: str) -> str:
    """album, ep, single, featuring or compile (unknown types count as album)."""
    if is_featuring(title, artist_name):
        return "featuring"
    kind = (record_type or "").lower()
    return kind if kind in KINDS else "album"


def group_key(title: str, record_type: str, artist_name: str) -> str:
    """The key shared by all the versions of a release (an EP and its deluxe album are one)."""
    kind = kind_of(title, record_type, artist_name)
    family = "album" if kind == "ep" else kind
    return f"{family}|{normalize(base_title(title))}"
