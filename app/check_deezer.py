"""Feasibility test: does Deezer answer from GitHub's servers, and does ntfy reach the phone?

For each test artist: search by name, pick the right artist, read the whole discography,
then report releases by type, featurings, first and last release, upcoming ones, calls
and seconds. With ``--notifica`` it also sends one test notification for the most recent
release found. Modelled on CNV's check_sites (.github/workflows/prova-deezer.yml).

Usage:
    python -m app.check_deezer [--notifica]
Exit code 1 if an artist could not be read or the notification was not sent.
"""

from __future__ import annotations

import argparse
import asyncio
from collections import Counter
from dataclasses import dataclass, field
from datetime import date, datetime
import os
import sys
import time
from zoneinfo import ZoneInfo

from app.config import settings
from app.services.deezer import DeezerArtist, DeezerClient, DeezerError, DeezerRelease, best_match
from app.services.ntfy import NotificationSender, NtfyClient, release_notification

TEST_ARTISTS = [
    "Ava Max",
    "Lady Gaga",
    "Isabel LaRosa",
    "Arctic Monkeys",
    "K/DA",
    "League of Legends",
    "Amy Lee",
]


@dataclass
class ArtistReport:
    query: str
    artist: DeezerArtist | None = None
    releases: list[DeezerRelease] = field(default_factory=list)
    calls: int = 0
    seconds: float = 0.0
    error: str | None = None

    @property
    def ok(self) -> bool:
        return self.error is None and self.artist is not None

    def featurings(self) -> list[DeezerRelease]:
        return [r for r in self.releases if self.artist and r.is_featuring(self.artist.name)]

    def released(self, today: date) -> list[DeezerRelease]:
        return [r for r in self.releases if r.release_date and r.release_date <= today]

    def upcoming(self, today: date) -> list[DeezerRelease]:
        return [r for r in self.releases if r.release_date and r.release_date > today]


async def check_artist(deezer, query: str) -> ArtistReport:
    """Search the artist and read the discography; ``deezer`` is the real client or a fake
    with ``calls``, ``search_artists`` and ``artist_releases``."""
    report = ArtistReport(query)
    calls_before, start = deezer.calls, time.perf_counter()
    try:
        report.artist = best_match(query, await deezer.search_artists(query))
        if report.artist is None:
            report.error = "nessun artista trovato"
        else:
            report.releases = await deezer.artist_releases(report.artist.id)
    except DeezerError as err:
        report.error = f"{type(err).__name__}: {err}"
    report.calls = deezer.calls - calls_before
    report.seconds = time.perf_counter() - start
    return report


async def check(deezer, artists: list[str]) -> list[ArtistReport]:
    return [await check_artist(deezer, query) for query in artists]


def _day(d: date | None) -> str:
    return f"{d:%d/%m/%Y}" if d else "—"


def report_markdown(reports: list[ArtistReport], today: date) -> str:
    rows = [
        "## Prova di Deezer",
        "",
        "| Cercato | Trovato su Deezer | Uscite | Album | EP | Singoli | Raccolte | Featuring | Prima | Ultima | Future | Chiamate | Secondi | Esito |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for r in reports:
        if not r.ok:
            rows.append(f"| {r.query} | — | | | | | | | | | | {r.calls} | {r.seconds:.1f} | ❌ {r.error} |")
            continue
        types = Counter(rel.record_type for rel in r.releases)
        released = r.released(today)
        fans = f"{r.artist.fans:,}".replace(",", ".")  # Italian thousands separator
        found = f"[{r.artist.name}]({r.artist.link}) (id {r.artist.id}, {fans} fan)"
        rows.append(
            f"| {r.query} | {found} | {len(r.releases)} | {types['album']} | {types['ep']} | {types['single']} "
            f"| {types['compile']} | {len(r.featurings())} | {_day(released[0].release_date if released else None)} "
            f"| {_day(released[-1].release_date if released else None)} | {len(r.upcoming(today))} "
            f"| {r.calls} | {r.seconds:.1f} | ✅ |"
        )
    total_calls = sum(r.calls for r in reports)
    total_seconds = sum(r.seconds for r in reports)
    rows += ["", f"Totale: {total_calls} chiamate in {total_seconds:.1f} secondi."]
    upcoming = [(r.artist.name, rel) for r in reports if r.ok for rel in r.upcoming(today)]
    if upcoming:
        rows += ["", "### Uscite con una data futura", ""]
        rows += [f"- {name}: {rel.title} ({rel.type_label}, {_day(rel.release_date)})" for name, rel in upcoming]
    rows += [
        "",
        "I featuring contati sono solo quelli con il nome dell'artista nel titolo (es. \"feat. Ava Max\").",
        "",
    ]
    return "\n".join(rows)


def latest_release(reports: list[ArtistReport], today: date) -> tuple[str, DeezerRelease] | None:
    """The most recent release already out among all the artists (for the test notification)."""
    candidates = [(r.artist.name, rel) for r in reports if r.ok for rel in r.released(today)]
    if not candidates:
        return None
    return max(candidates, key=lambda c: c[1].release_date)


async def send_test_notification(sender: NotificationSender, reports: list[ArtistReport], now: datetime) -> str:
    """Send the notification for the latest release; returns a line for the report."""
    found = latest_release(reports, now.date())
    if found is None:
        return "Notifica di prova non inviata: nessuna uscita trovata."
    artist, release = found
    notification = release_notification(artist, release, now)
    await sender.send(notification)
    sound = "senza suono (ore notturne)" if notification.priority < 3 else "con il suono"
    return f"Notifica di prova inviata {sound}: «{notification.title}» – {release.title}."


async def run(notify: bool) -> tuple[str, bool]:
    now = datetime.now(ZoneInfo(settings.TIMEZONE))
    async with DeezerClient() as deezer:
        reports = await check(deezer, TEST_ARTISTS)
    report = report_markdown(reports, now.date())
    all_ok = all(r.ok for r in reports)
    if notify:
        if not settings.NTFY_TOPIC:
            line, all_ok = "❌ Notifica non inviata: manca il segreto NTFY_TOPIC.", False
        else:
            try:
                async with NtfyClient() as ntfy:
                    line = "✅ " + await send_test_notification(ntfy, reports, now)
            except Exception as err:  # noqa: BLE001 - reported in the summary
                line, all_ok = f"❌ Notifica non inviata: {type(err).__name__}: {err}", False
        report += "\n" + line + "\n"
    return report, all_ok


def main() -> int:
    parser = argparse.ArgumentParser(description="Prova di Deezer (e di ntfy) per CNS")
    parser.add_argument("--notifica", action="store_true", help="manda anche una notifica di prova sul telefono")
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    report, all_ok = asyncio.run(run(args.notifica))
    print(report)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:  # shown on the run page on GitHub
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write(report)
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
