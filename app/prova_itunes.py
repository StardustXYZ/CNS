"""Feasibility test: does iTunes answer from GitHub's servers, and does it show announced releases?

For each test artist: the Deezer artist and its titles, then the matching iTunes artist
(same name, most titles in common), its releases and the announced ones (date after today).
ENHYPEN and Justice are in the list because in November 2026 they have releases in
pre-order: if they show up, the source works. Modelled on app/check_deezer.py.

Usage:
    python -m app.prova_itunes
Exit code 1 if iTunes could not be read for an artist (e.g. Apple blocking GitHub).
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import date, datetime
import os
import sys
import time
from zoneinfo import ZoneInfo

from app.check_deezer import TEST_ARTISTS
from app.config import settings
from app.services.deezer import DeezerClient, DeezerError, best_match
from app.services.itunes import ItunesArtist, ItunesClient, ItunesError, ItunesRelease, match_artist, upcoming

PROVA_ARTISTS = [*TEST_ARTISTS, "ENHYPEN", "Justice"]


@dataclass
class Result:
    query: str
    artist: ItunesArtist | None = None
    releases: list[ItunesRelease] = field(default_factory=list)
    overlap: int = 0
    announced: list[ItunesRelease] = field(default_factory=list)
    calls: int = 0
    error: str | None = None


async def check_one(deezer, itunes, query: str, today: date) -> Result:
    result = Result(query)
    calls_before = itunes.calls
    try:
        found = best_match(query, await deezer.search_artists(query))
        titles = [r.title for r in await deezer.artist_releases(found.id)] if found else []
        result.artist, result.releases, result.overlap = await match_artist(itunes, query, titles)
        result.announced = upcoming(result.releases, today)
        if result.artist is None:
            result.error = "nessun artista con questo nome su iTunes"
    except (DeezerError, ItunesError) as err:
        result.error = f"{type(err).__name__}: {err}"
    result.calls = itunes.calls - calls_before
    return result


def _day(d: date | None) -> str:
    return f"{d:%d/%m/%Y}" if d else "—"


def report_markdown(results: list[Result], seconds: float, calls: int) -> str:
    rows = [
        "## Prova di iTunes (uscite annunciate)",
        "",
        "| Cercato | Artista iTunes | Titoli in comune con Deezer | Uscite su iTunes | Annunciate | Chiamate | Esito |",
        "|---|---|---|---|---|---|---|",
    ]
    for r in results:
        if r.error:
            rows.append(f"| {r.query} | — | | | | {r.calls} | ❌ {r.error} |")
            continue
        first = r.announced[0] if r.announced else None
        announced = f"{len(r.announced)}: {first.title} ({_day(first.release_date)})" if first else "0"
        sure = "" if r.overlap else " ⚠️ abbinamento incerto"
        rows.append(f"| {r.query} | {r.artist.name} (id {r.artist.id}, {r.artist.genre}) | {r.overlap}{sure} | "
                    f"{len(r.releases)} | {announced} | {r.calls} | ✅ |")
    rows += ["", f"Totale: {calls} chiamate a iTunes in {seconds:.0f} secondi.", ""]
    return "\n".join(rows)


async def run() -> tuple[str, bool]:
    today = datetime.now(ZoneInfo(settings.TIMEZONE)).date()
    start = time.perf_counter()
    async with DeezerClient() as deezer, ItunesClient() as itunes:
        results = [await check_one(deezer, itunes, q, today) for q in PROVA_ARTISTS]
        calls = itunes.calls
    report = report_markdown(results, time.perf_counter() - start, calls)
    return report, all(r.error is None for r in results)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    report, ok = asyncio.run(run())
    print(report)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:  # shown on the run page on GitHub
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write(report)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
