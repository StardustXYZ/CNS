"""iTunes / Apple Music public search (no key): the source of the announced releases.

Deezer shows a release only once it is out; the iTunes store lists pre-orders with their
future date. Apple asks to stay around 20 calls a minute, so the client keeps a pause
between calls and waits when Apple says there are too many.

The same artist name can belong to several artists on iTunes (five "Justice"): the right
one is the one whose albums share the most titles with the artist's Deezer discography.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import date
import re
from typing import Protocol

import httpx

from app.services.discografia import base_title, normalize

ITUNES_URL = "https://itunes.apple.com"
COUNTRY = "IT"
MIN_INTERVAL = 3.0  # seconds between calls: about 20 a minute
MIN_OVERLAP_LONGER_NAME = 3  # titles in common needed to accept an artist whose name only starts the same
_SUFFIX = re.compile(r"\s+-\s+(Single|EP)$", re.IGNORECASE)


class ItunesError(Exception):
    """iTunes did not give the data (the message is in Italian, shown in the report)."""


@dataclass(frozen=True)
class ItunesArtist:
    id: int
    name: str
    genre: str = ""


@dataclass(frozen=True)
class ItunesRelease:
    id: int
    title: str  # without iTunes' " - Single" / " - EP"
    kind: str  # "album", "ep" or "single" (as in the app)
    release_date: date | None
    cover: str | None = None
    link: str | None = None

    @classmethod
    def from_api(cls, hit: dict) -> ItunesRelease:
        name = hit.get("collectionName") or ""
        suffix = _SUFFIX.search(name)
        kind = suffix.group(1).lower() if suffix else "album"
        title = name[: suffix.start()] if suffix else name
        try:
            released = date.fromisoformat((hit.get("releaseDate") or "")[:10])
        except ValueError:
            released = None
        cover = hit.get("artworkUrl100")
        return cls(
            id=int(hit["collectionId"]),
            title=title.strip(),
            kind="single" if kind == "single" else kind,
            release_date=released,
            cover=cover.replace("100x100bb", "600x600bb") if cover else None,
            link=hit.get("collectionViewUrl"),
        )


class ReleaseSource(Protocol):
    """Anything that can search iTunes artists and list their releases (real client or test fake)."""

    async def search_artists(self, name: str) -> list[ItunesArtist]: ...

    async def artist_releases(self, artist_id: int) -> list[ItunesRelease]: ...


def title_overlap(itunes_releases: list[ItunesRelease], deezer_titles: list[str]) -> int:
    """How many release titles the two discographies share (without version marks)."""
    deezer = {normalize(base_title(t)) for t in deezer_titles}
    return len({normalize(base_title(r.title)) for r in itunes_releases} & deezer)


async def match_artist(itunes: ReleaseSource, name: str, deezer_titles: list[str]) -> tuple[ItunesArtist | None, list[ItunesRelease], int]:
    """The iTunes artist that is the Deezer one: same name and the most titles in common.

    Returns the artist, its releases and the titles in common (0: no sure match, None if
    nobody with that name)."""
    wanted = normalize(name)
    found = await itunes.search_artists(name)
    candidates = [a for a in found if normalize(a.name) == wanted]
    min_overlap = 0
    if not candidates:
        # A longer name on iTunes ("League of Legends Music"): only with real titles in common
        candidates = [a for a in found if normalize(a.name).startswith(wanted + " ")]
        min_overlap = MIN_OVERLAP_LONGER_NAME
    best: tuple[ItunesArtist | None, list[ItunesRelease], int] = (None, [], -1)
    for candidate in candidates[:4]:  # each one is a call: the first few are enough
        releases = await itunes.artist_releases(candidate.id)
        overlap = title_overlap(releases, deezer_titles)
        if overlap >= min_overlap and overlap > best[2]:
            best = (candidate, releases, overlap)
        if overlap >= 3 and len(candidates) == 1:
            break
    return best if best[0] else (None, [], 0)


def upcoming(releases: list[ItunesRelease], today: date) -> list[ItunesRelease]:
    """The announced releases (date after today), soonest first; one per title."""
    seen: set[str] = set()
    result = []
    for r in sorted((r for r in releases if r.release_date and r.release_date > today), key=lambda r: (r.release_date, r.id)):
        key = normalize(base_title(r.title))
        if key not in seen:
            seen.add(key)
            result.append(r)
    return result


class ItunesClient:
    """Async iTunes client. Use as ``async with ItunesClient() as itunes: ...``."""

    def __init__(self, timeout: float = 20.0, transport: httpx.AsyncBaseTransport | None = None,
                 min_interval: float = MIN_INTERVAL, retry_wait: float = 60.0, retries: int = 1) -> None:
        self._client = httpx.AsyncClient(base_url=ITUNES_URL, timeout=timeout, transport=transport,
                                         headers={"Accept": "application/json"})
        self.min_interval, self.retry_wait, self.retries = min_interval, retry_wait, retries
        self.calls = 0
        self._last_call = 0.0

    async def __aenter__(self) -> ItunesClient:
        return self

    async def __aexit__(self, *exc) -> None:
        await self._client.aclose()

    async def _pause(self) -> None:
        loop = asyncio.get_running_loop()
        wait = self._last_call + self.min_interval - loop.time()
        if wait > 0:
            await asyncio.sleep(wait)
        self._last_call = loop.time()

    async def _get(self, path: str, params: dict) -> dict:
        for attempt in range(self.retries + 1):
            await self._pause()
            try:
                resp = await self._client.get(path, params={**params, "country": COUNTRY})
            except httpx.HTTPError as err:
                raise ItunesError(f"iTunes non risponde ({type(err).__name__})") from err
            self.calls += 1
            if resp.status_code in (403, 429) and attempt < self.retries:
                await asyncio.sleep(self.retry_wait)  # too many calls: Apple wants a pause
                continue
            if resp.status_code >= 400:
                raise ItunesError(f"iTunes ha risposto con HTTP {resp.status_code}")
            try:
                return resp.json()
            except ValueError:
                raise ItunesError(f"risposta non di iTunes: {resp.text[:80].strip()!r}") from None
        raise ItunesError("iTunes continua a dire che le chiamate sono troppe")

    async def search_artists(self, name: str) -> list[ItunesArtist]:
        data = await self._get("/search", {"term": name, "entity": "musicArtist", "limit": 10})
        return [ItunesArtist(int(h["artistId"]), h.get("artistName") or "", h.get("primaryGenreName") or "")
                for h in data.get("results", []) if h.get("artistId")]

    async def artist_releases(self, artist_id: int) -> list[ItunesRelease]:
        data = await self._get("/lookup", {"id": artist_id, "entity": "album", "limit": 200, "sort": "recent"})
        return [ItunesRelease.from_api(h) for h in data.get("results", [])
                if h.get("wrapperType") == "collection" and h.get("collectionId")]
