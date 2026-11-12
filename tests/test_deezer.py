"""Deezer client with a fake server: parsing, pagination, errors, choice of the artist."""

from __future__ import annotations

from datetime import date

import httpx
import pytest

from app.services.deezer import (
    DeezerArtist,
    DeezerBlocked,
    DeezerClient,
    DeezerError,
    DeezerNotFound,
    DeezerRelease,
    best_match,
    chronological,
)
from tests.conftest import json_transport


def client(routes, log=None) -> DeezerClient:
    return DeezerClient(transport=json_transport(routes, log), min_interval=0, retry_wait=0)


def album(id_, title, day="2024-01-05", kind="single", **extra) -> dict:
    return {"id": id_, "title": title, "release_date": day, "record_type": kind,
            "cover_xl": f"https://cdn/{id_}.jpg", "link": f"https://www.deezer.com/album/{id_}", **extra}


# ---- Release data ----

def test_release_from_api():
    r = DeezerRelease.from_api(album(1, "Christmas Wonderland", "2026-11-06", "single", explicit_lyrics=True))
    assert r.release_date == date(2026, 11, 6)
    assert r.type_label == "Singolo"
    assert r.cover == "https://cdn/1.jpg"
    assert r.explicit is True


@pytest.mark.parametrize("raw", ["", "0000-00-00", None])
def test_release_without_valid_date(raw):
    assert DeezerRelease.from_api(album(1, "X", raw)).release_date is None


@pytest.mark.parametrize("kind, label", [("album", "Album"), ("single", "Singolo"), ("ep", "EP"), ("compile", "Raccolta")])
def test_type_labels_in_italian(kind, label):
    assert DeezerRelease.from_api(album(1, "X", kind=kind)).type_label == label


@pytest.mark.parametrize("title, expected", [
    ("BURN (feat. Ava Max)", True),
    ("Brought The Heat Back (Feat. Ava Max)", True),
    ("Song ft. Ava Max & Someone", True),
    ("Duet (with Ava Max)", True),
    ("Kings & Queens, Pt. 2 (feat. Lauv & Saweetie)", False),  # her own song with guests
    ("Sweet but Psycho", False),
    ("Song (feat. Ava Maxwell)", False),  # a different name that starts the same
])
def test_featuring_detection(title, expected):
    assert DeezerRelease.from_api(album(1, title)).is_featuring("Ava Max") is expected


def test_chronological_puts_undated_last():
    rs = [DeezerRelease.from_api(album(i, t, d)) for i, t, d in
          [(1, "B", "2020-01-01"), (2, "Senza data", ""), (3, "A", "2018-05-05"), (4, "C", "2020-01-01")]]
    assert [r.title for r in chronological(rs)] == ["A", "B", "C", "Senza data"]


# ---- Choosing the artist ----

def artist(id_, name, fans):
    return DeezerArtist(id=id_, name=name, fans=fans)


def test_best_match_prefers_exact_name_with_most_fans():
    # Real case: the singer Amy Lee is the fifth result on Deezer
    results = [artist(1, "Amy Lee", 153), artist(2, "AmyLee", 264), artist(3, "Amy Lee", 4), artist(5, "Amy Lee", 265225)]
    assert best_match("Amy Lee", results).id == 5


def test_best_match_ignores_case_and_accents():
    assert best_match("isabel larosa", [artist(1, "Isabella Rosa", 20), artist(2, "Isabel LaRosa", 136074)]).id == 2
    assert best_match("Beyonce", [artist(1, "Beyoncé", 10)]).id == 1


def test_best_match_falls_back_to_first_result():
    assert best_match("K/DA", [artist(1, "K/DA", 10)]).id == 1  # punctuation does not matter
    assert best_match("Qualcuno", [artist(7, "Altro", 1), artist(8, "Altro ancora", 2)]).id == 7
    assert best_match("Nessuno", []) is None


# ---- HTTP client ----

async def test_search_artists():
    routes = {"/search/artist": {"data": [{"id": 15741, "name": "Amy Lee", "nb_fan": 265225, "nb_album": 11,
                                           "picture_big": "https://cdn/amy.jpg", "link": "https://www.deezer.com/artist/15741"}]}}
    async with client(routes) as deezer:
        found = await deezer.search_artists("Amy Lee")
    assert found == [DeezerArtist(15741, "Amy Lee", 265225, 11, "https://cdn/amy.jpg", "https://www.deezer.com/artist/15741")]
    assert deezer.calls == 1


async def test_discography_follows_all_pages_and_sorts():
    routes = {
        "/artist/9/albums?limit=100": {"data": [album(2, "Nuovo", "2026-11-06"), album(1, "Vecchio", "2016-08-12")],
                                       "next": "https://api.deezer.com/artist/9/albums?limit=100&index=100"},
        "/artist/9/albums?limit=100&index=100": {"data": [album(3, "Medio", "2020-03-06", "album"),
                                                          album(1, "Vecchio", "2016-08-12")]},  # repeated: kept once
    }
    async with client(routes) as deezer:
        releases = await deezer.artist_releases(9)
    assert [r.title for r in releases] == ["Vecchio", "Medio", "Nuovo"]
    assert deezer.calls == 2


async def test_quota_error_waits_and_retries():
    quota = {"error": {"type": "Exception", "message": "Quota limit exceeded", "code": 4}}
    routes = {"/search/artist": [quota, httpx.Response(429), {"data": [{"id": 1, "name": "K/DA"}]}]}
    async with client(routes) as deezer:
        found = await deezer.search_artists("K/DA")
    assert [a.name for a in found] == ["K/DA"]
    assert deezer.calls == 3


async def test_quota_error_gives_up_after_retries():
    quota = {"error": {"type": "Exception", "message": "Quota limit exceeded", "code": 4}}
    routes = {"/search/artist": [quota] * 4}
    async with client(routes) as deezer:
        with pytest.raises(DeezerError, match="troppe"):
            await deezer.search_artists("X")
    assert deezer.calls == 4


async def test_bot_protection_page_is_reported():
    page = httpx.Response(403, text="<html>Access Denied</html>", headers={"Content-Type": "text/html"})
    async with client({"/search/artist": page}) as deezer:
        with pytest.raises(DeezerBlocked, match="HTTP 403"):
            await deezer.search_artists("X")


async def test_missing_album_is_not_found():
    no_data = {"error": {"type": "DataException", "message": "no data", "code": 800}}
    async with client({"/artist/0": no_data}) as deezer:
        with pytest.raises(DeezerNotFound):
            await deezer.get_artist(0)


async def test_other_errors_are_reported():
    async with client({"/search/artist": {"error": {"message": "boh", "code": 100}}}) as deezer:
        with pytest.raises(DeezerError, match="100"):
            await deezer.search_artists("X")
    async with client({"/search/artist": httpx.Response(500, json={})}) as deezer:
        with pytest.raises(DeezerError, match="HTTP 500"):
            await deezer.search_artists("X")
