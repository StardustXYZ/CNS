"""Deezer integration – thin async client for the public catalog API (no key, no login).

Deezer answers errors with HTTP 200 and an ``error`` object; code 4 means "too many
calls" (about 50 every 5 seconds), so the client keeps a small pause between calls and
waits before trying again. An answer that is not Deezer's JSON (e.g. a bot-protection
page) raises ``DeezerBlocked``: the feasibility test exists to catch exactly that.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import date
import re
from typing import Protocol

import httpx

from app.services.titles import normalize_title

DEEZER_API_URL = "https://api.deezer.com"
PAGE_SIZE = 100
MAX_PAGES = 50  # 5000 releases: a safety stop if Deezer kept sending "next"
MIN_INTERVAL = 0.15  # seconds between calls, well under 50 calls every 5 seconds
QUOTA_ERROR_CODE = 4
NO_DATA_ERROR_CODE = 800

TYPE_LABELS = {"album": "Album", "single": "Singolo", "ep": "EP", "compile": "Raccolta"}

# "(feat. X)", "ft. X", "featuring X", "(with X)": the names after it are the guests
_FEAT_RE = re.compile(r"(?:\b(?:feat|ft)\b\.?|\bfeaturing\b|[(\[]\s*with\b)\s*([^)\]]+)", re.IGNORECASE)


class DeezerError(Exception):
    """Deezer did not give the data (the message is in Italian, shown in the report)."""


class DeezerBlocked(DeezerError):
    """The answer is not Deezer's JSON: probably the bot protection stopped the call."""


class DeezerNotFound(DeezerError):
    """The artist or release does not exist on Deezer."""


@dataclass(frozen=True)
class DeezerArtist:
    id: int
    name: str
    fans: int = 0
    albums: int = 0
    picture: str | None = None
    link: str | None = None

    @classmethod
    def from_api(cls, hit: dict) -> DeezerArtist:
        return cls(
            id=int(hit["id"]),
            name=hit.get("name") or "",
            fans=int(hit.get("nb_fan") or 0),
            albums=int(hit.get("nb_album") or 0),
            picture=hit.get("picture_big") or hit.get("picture"),
            link=hit.get("link"),
        )


@dataclass(frozen=True)
class DeezerRelease:
    """One item of an artist's discography: album, single, EP or compilation."""

    id: int
    title: str
    record_type: str
    release_date: date | None = None
    cover: str | None = None
    link: str | None = None
    explicit: bool = False

    @property
    def type_label(self) -> str:
        return TYPE_LABELS.get(self.record_type, self.record_type.capitalize() or "Uscita")

    def is_featuring(self, artist_name: str) -> bool:
        """True when the artist is a guest named in the title, e.g. "BURN (feat. Ava Max)"."""
        wanted = normalize_title(artist_name)
        if not wanted:
            return False
        for guests in _FEAT_RE.findall(self.title):
            if f" {wanted} " in f" {normalize_title(guests)} ":
                return True
        return False

    @classmethod
    def from_api(cls, hit: dict) -> DeezerRelease:
        try:
            released = date.fromisoformat(hit.get("release_date") or "")
        except ValueError:  # missing or "0000-00-00"
            released = None
        return cls(
            id=int(hit["id"]),
            title=hit.get("title") or "",
            record_type=(hit.get("record_type") or "").lower(),
            release_date=released,
            cover=hit.get("cover_xl") or hit.get("cover_big") or hit.get("cover"),
            link=hit.get("link"),
            explicit=bool(hit.get("explicit_lyrics")),
        )


def chronological(releases: list[DeezerRelease]) -> list[DeezerRelease]:
    """Oldest first; releases without a date go last."""
    return sorted(releases, key=lambda r: (r.release_date is None, r.release_date or date.min, r.title.lower()))


def best_match(query: str, artists: list[DeezerArtist]) -> DeezerArtist | None:
    """The artist with exactly the searched name and the most fans, else the first result.

    Deezer does not always put the right artist first: for "Amy Lee" the singer is the
    fifth result, after small accounts with the same name.
    """
    wanted = normalize_title(query)
    same_name = [a for a in artists if normalize_title(a.name) == wanted]
    if same_name:
        return max(same_name, key=lambda a: a.fans)
    return artists[0] if artists else None


class ArtistSearcher(Protocol):
    """Anything that can search artists by name (the real client or a test fake)."""

    async def search_artists(self, query: str, limit: int = 10) -> list[DeezerArtist]: ...


class DiscographySource(Protocol):
    """Anything that can list an artist's releases (the real client or a test fake)."""

    async def artist_releases(self, artist_id: int) -> list[DeezerRelease]: ...


class DeezerClient:
    """Async Deezer client. Use as ``async with DeezerClient() as deezer: ...``."""

    def __init__(
        self,
        timeout: float = 15.0,
        transport: httpx.AsyncBaseTransport | None = None,
        min_interval: float = MIN_INTERVAL,
        retry_wait: float = 5.0,
        retries: int = 3,
    ) -> None:
        self._client = httpx.AsyncClient(
            base_url=DEEZER_API_URL,
            timeout=timeout,
            transport=transport,
            headers={"Accept": "application/json"},
        )
        self.min_interval = min_interval
        self.retry_wait = retry_wait
        self.retries = retries
        self.calls = 0  # HTTP calls made, for the feasibility report
        self._last_call = 0.0

    async def __aenter__(self) -> DeezerClient:
        return self

    async def __aexit__(self, *exc) -> None:
        await self.aclose()

    async def aclose(self) -> None:
        await self._client.aclose()

    async def _pause(self) -> None:
        loop = asyncio.get_running_loop()
        wait = self._last_call + self.min_interval - loop.time()
        if wait > 0:
            await asyncio.sleep(wait)
        self._last_call = loop.time()

    async def _get(self, url: str, params: dict | None = None) -> dict:
        """One API call, waiting and retrying while Deezer says there are too many calls."""
        for attempt in range(self.retries + 1):
            await self._pause()
            try:
                resp = await self._client.get(url, params=params)
            except httpx.HTTPError as err:
                raise DeezerError(f"Deezer non risponde ({type(err).__name__})") from err
            self.calls += 1
            too_many = resp.status_code == 429
            if not too_many:
                try:
                    data = resp.json()
                except ValueError:
                    raise DeezerBlocked(
                        f"risposta non di Deezer (HTTP {resp.status_code}): {resp.text[:80].strip()!r}"
                    ) from None
                if resp.status_code >= 400:
                    raise DeezerError(f"Deezer ha risposto con HTTP {resp.status_code}")
                error = data.get("error") if isinstance(data, dict) else None
                if not error:
                    return data
                code = error.get("code")
                if code == NO_DATA_ERROR_CODE:
                    raise DeezerNotFound(error.get("message") or "nessun dato")
                if code != QUOTA_ERROR_CODE:
                    raise DeezerError(f"errore di Deezer {code}: {error.get('message')}")
                too_many = True
            if attempt < self.retries:
                await asyncio.sleep(self.retry_wait * (attempt + 1))
        raise DeezerError("Deezer continua a dire che le chiamate sono troppe")

    async def search_artists(self, query: str, limit: int = 10) -> list[DeezerArtist]:
        """Artists whose name matches the query, in Deezer's order."""
        data = await self._get("/search/artist", {"q": query, "limit": limit})
        return [DeezerArtist.from_api(hit) for hit in data.get("data", [])]

    async def get_artist(self, artist_id: int) -> DeezerArtist:
        return DeezerArtist.from_api(await self._get(f"/artist/{artist_id}"))

    async def artist_releases(self, artist_id: int) -> list[DeezerRelease]:
        """The whole discography (albums, singles, EPs, compilations, featurings), oldest first."""
        releases: dict[int, DeezerRelease] = {}
        url: str | None = f"/artist/{artist_id}/albums"
        params: dict | None = {"limit": PAGE_SIZE}
        for _ in range(MAX_PAGES):
            if url is None:
                break
            data = await self._get(url, params)
            for hit in data.get("data", []):
                release = DeezerRelease.from_api(hit)
                releases[release.id] = release
            url, params = data.get("next"), None  # "next" already holds limit and index
        return chronological(list(releases.values()))
