"""iTunes client with a fake server: releases, matching the right artist, announced releases."""

from __future__ import annotations

from datetime import date

import httpx
import pytest

from app.services.itunes import (
    ItunesArtist,
    ItunesClient,
    ItunesError,
    ItunesRelease,
    match_artist,
    title_overlap,
    upcoming,
)
from tests.conftest import json_transport

TODAY = date(2026, 11, 13)


def album(id_, name, day, artist="ENHYPEN"):
    return {"wrapperType": "collection", "collectionType": "Album", "collectionId": id_, "collectionName": name,
            "artistName": artist, "releaseDate": f"{day}T08:00:00Z",
            "artworkUrl100": f"https://is1.mzstatic.com/{id_}/100x100bb.jpg",
            "collectionViewUrl": f"https://music.apple.com/it/album/{id_}"}


def test_release_from_api():
    r = ItunesRelease.from_api(album(1, "THE SIN : PARALLEL WORLD - Single", "2026-11-20"))
    assert (r.title, r.kind, r.release_date) == ("THE SIN : PARALLEL WORLD", "single", date(2026, 11, 20))
    assert r.cover == "https://is1.mzstatic.com/1/600x600bb.jpg"
    assert ItunesRelease.from_api(album(2, "MANIFESTO : DAY 1 - EP", "2022-07-04")).kind == "ep"
    assert ItunesRelease.from_api(album(3, "Grand Theft Auto VI: Original Score", "2026-12-11")).kind == "album"
    assert ItunesRelease.from_api({**album(4, "X", "2026-01-01"), "releaseDate": ""}).release_date is None


def test_upcoming_soonest_first_one_per_title():
    rs = [ItunesRelease.from_api(a) for a in [
        album(1, "Grand Theft Auto VI: Original Score", "2026-12-11"),
        album(2, "Grand Theft Auto VI: Original Score", "2026-12-11"),  # iTunes lists it twice
        album(3, "THE SIN : PARALLEL WORLD - Single", "2026-11-20"),
        album(4, "Uscito ieri - Single", "2026-11-12"),
        album(5, "Esce oggi - Single", "2026-11-13"),  # today is not "announced": it is out
    ]]
    assert [r.title for r in upcoming(rs, TODAY)] == ["THE SIN : PARALLEL WORLD", "Grand Theft Auto VI: Original Score"]


def test_title_overlap_ignores_versions_and_suffixes():
    rs = [ItunesRelease.from_api(album(1, "Heaven & Hell", "2020-09-18")), ItunesRelease.from_api(album(2, "Sweet but Psycho - Single", "2018-08-17"))]
    assert title_overlap(rs, ["Heaven & Hell (Deluxe)", "Sweet but Psycho (Acoustic)", "Altro"]) == 2


class FakeItunes:
    def __init__(self, artists, releases):
        self.artists, self.releases, self.looked_up = artists, releases, []

    async def search_artists(self, name):
        return self.artists

    async def artist_releases(self, artist_id):
        self.looked_up.append(artist_id)
        return self.releases.get(artist_id, [])


async def test_match_picks_the_artist_with_titles_in_common():
    # Five "Justice" on iTunes: the French duo shares titles with Deezer
    fake = FakeItunes(
        [ItunesArtist(1727741097, "Justice", "Hip-hop"), ItunesArtist(145072812, "Justice", "Elettronica"),
         ItunesArtist(1467210628, "Just-Ice", "Hip-Hop/Rap")],
        {145072812: [ItunesRelease.from_api(album(9, "Cross", "2007-06-11", "Justice")),
                     ItunesRelease.from_api(album(10, "Hyperdrama", "2024-04-26", "Justice"))],
         1727741097: [ItunesRelease.from_api(album(11, "Altro rap - Single", "2025-01-01", "Justice"))]},
    )
    artist, releases, overlap = await match_artist(fake, "Justice", ["Cross", "Hyperdrama", "Woman"])
    assert artist.id == 145072812 and overlap == 2 and len(releases) == 2
    assert 1467210628 not in fake.looked_up  # a different name is not even looked at


async def test_match_a_longer_name_only_with_titles_in_common():
    lol = ItunesArtist(960030338, "League of Legends Music", "Colonne sonore")
    wild = ItunesArtist(1537758380, "League of Legends: Wild Rift", "Pop")
    songs = [ItunesRelease.from_api(album(i, t, "2020-01-01")) for i, t in [(1, "Take Over - Single"), (2, "RISE - Single"), (3, "Warriors - Single")]]
    fake = FakeItunes([lol, wild], {960030338: songs, 1537758380: [ItunesRelease.from_api(album(9, "Wild - Single", "2021-01-01"))]})
    artist, _, overlap = await match_artist(fake, "League of Legends", ["Take Over", "RISE", "Warriors", "GODS"])
    assert artist == lol and overlap == 3
    # With fewer than 3 titles in common a longer name is not trusted
    assert (await match_artist(fake, "League of Legends", ["Take Over"]))[0] is None


async def test_match_without_anybody_of_that_name():
    assert await match_artist(FakeItunes([ItunesArtist(1, "Altro", "")], {}), "Nessuno", []) == (None, [], 0)


# ---- HTTP client ----

def client(routes, log=None):
    return ItunesClient(transport=json_transport(routes, log), min_interval=0, retry_wait=0)


async def test_search_and_lookup():
    routes = {
        "/search": {"results": [{"artistId": 1438357393, "artistName": "ENHYPEN", "primaryGenreName": "K-Pop"}]},
        "/lookup": {"results": [{"wrapperType": "artist", "artistId": 1438357393},
                                album(6824959794, "THE SIN : PARALLEL WORLD - Single", "2026-11-20")]},
    }
    log = []
    async with client(routes, log) as itunes:
        artists = await itunes.search_artists("ENHYPEN")
        releases = await itunes.artist_releases(1438357393)
    assert artists == [ItunesArtist(1438357393, "ENHYPEN", "K-Pop")]
    assert [r.title for r in releases] == ["THE SIN : PARALLEL WORLD"]
    assert all(req.url.params["country"] == "IT" for req in log)
    assert itunes.calls == 2


async def test_too_many_calls_waits_and_retries():
    routes = {"/search": [httpx.Response(429), {"results": []}]}
    async with client(routes) as itunes:
        assert await itunes.search_artists("X") == []
    assert itunes.calls == 2


async def test_blocked_is_reported():
    async with client({"/search": [httpx.Response(403), httpx.Response(403)]}) as itunes:
        with pytest.raises(ItunesError, match="HTTP 403"):
            await itunes.search_artists("X")
    async with client({"/search": httpx.Response(200, text="<html>no</html>")}) as itunes:
        with pytest.raises(ItunesError, match="non di iTunes"):
            await itunes.search_artists("X")
