"""Merged versions in Python: the same examples as the app's JavaScript tests."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.services.discografia import base_title, group_key, is_featuring, kind_of, normalize

CASES = json.loads((Path(__file__).parent / "fixtures" / "doppioni.json").read_text(encoding="utf-8"))


@pytest.mark.parametrize("title, expected", CASES["titolo_base"])
def test_base_title(title, expected):
    assert base_title(title) == expected


@pytest.mark.parametrize("title, artist, expected", CASES["featuring"])
def test_featuring(title, artist, expected):
    assert is_featuring(title, artist) is expected


@pytest.mark.parametrize("title, record_type, artist, expected", CASES["chiave"])
def test_group_key(title, record_type, artist, expected):
    assert group_key(title, record_type, artist) == expected


def test_normalize_like_the_app():
    assert normalize("Beyoncé") == "beyonce"
    assert normalize("  K/DA ") == "k da"
    assert normalize("snake_case") == "snake case"


def test_kind_of():
    assert kind_of("BURN (feat. Ava Max)", "single", "Ava Max") == "featuring"
    assert kind_of("X", "EP", "Ava Max") == "ep"
    assert kind_of("X", "", "Ava Max") == "album"
