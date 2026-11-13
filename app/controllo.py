"""The scheduled check, every 3 hours on GitHub Actions (.github/workflows/controllo.yml).

1. Reads the artists of every user from Firestore and groups them by Deezer artist: an
   artist followed by three people is asked to Deezer only once.
2. For each one, compares Deezer's discography with the releases already seen
   (``visti/<Deezer id>``). The first time an artist is checked nothing is announced: its
   whole discography just becomes "seen".
3. A release is new only if it is not a version of one already seen (same key as in the
   app: a new remix or deluxe edition is not news) and it is recent (Deezer sometimes
   adds old albums to its catalogue).
4. Each user who has the artist in Controllare, with that kind turned on, gets it in
   ``utenti/<code>/novita`` (the Novità page) and as an ntfy notification on their own
   topic (Impostazioni). Up to 3 releases, one notification each; more, one together.

The run's log is public (the repository is public): it shows only numbers, never the
names of the artists, the users' codes or their ntfy topics.

Usage:
    python -m app.controllo
Exit code 1 if Firestore could not be read or written.
"""

from __future__ import annotations

import asyncio
from collections import Counter
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
import os
import re
import sys
import time
from typing import Callable
from zoneinfo import ZoneInfo

from app.config import settings
from app.prova_firebase import STATUS_PATH, run_url
from app.services.deezer import DeezerClient, DeezerError, DeezerRelease, DiscographySource
from app.services.discografia import KINDS, group_key, kind_of
from app.services.firestore import DocumentStore, FirestoreClient, FirestoreError
from app.services.ntfy import NotificationSender, NtfyClient, release_notification, spotify_search_url, summary_notification

LISTS_TO_CHECK = ("controllare", "recuperando")  # new releases matter in both; "archivio" is left alone
NOTIFY_LIST = "controllare"  # only these get a notification; in Recuperando they go to the end of the queue
RECENT_DAYS = 30  # an older release appearing now is Deezer filling in its catalogue, not news
MAX_SINGLE_NOTIFICATIONS = 3  # more new releases for one person become one notification
TOPIC_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


@dataclass
class FollowedArtist:
    """One Deezer artist and who follows it: user code -> that user's document for the artist."""

    id: str
    name: str
    followers: dict[str, dict] = field(default_factory=dict)

    @property
    def to_check(self) -> bool:
        return any(data.get("lista") in LISTS_TO_CHECK for data in self.followers.values())


@dataclass
class NewRelease:
    artist: FollowedArtist
    release: DeezerRelease
    kind: str


def group_artists(documents: list[tuple[str, dict]]) -> dict[str, FollowedArtist]:
    """Artists from the documents ``utenti/<code>/artisti/<Deezer id>``, one entry per Deezer artist."""
    artists: dict[str, FollowedArtist] = {}
    for path, data in documents:
        parts = path.split("/")
        if len(parts) != 4 or parts[0] != "utenti" or parts[2] != "artisti" or not parts[3].isdigit():
            continue  # a collection called "artisti" somewhere else: not ours
        uid, artist_id = parts[1], parts[3]
        artist = artists.setdefault(artist_id, FollowedArtist(artist_id, str(data.get("nome") or "")))
        artist.followers[uid] = data
    return artists


def wanted_kinds(data: dict) -> list[str]:
    """The kinds this person wants to be told about for this artist (all, unless changed in the app)."""
    kinds = data.get("tipi_avviso")
    return [k for k in kinds if k in KINDS] if isinstance(kinds, list) and kinds else list(KINDS)


def find_new(artist: FollowedArtist, releases: list[DeezerRelease], seen: dict, today: date) -> list[NewRelease]:
    """The releases worth announcing: not seen, not a version of one seen, recent; one per release."""
    seen_ids = {str(i) for i in seen.get("ids", [])}
    seen_keys = set(seen.get("chiavi", []))
    news: dict[str, NewRelease] = {}
    for release in sorted(releases, key=lambda r: (r.release_date or date.max, r.id)):
        if str(release.id) in seen_ids:
            continue
        key = group_key(release.title, release.record_type, artist.name)
        if key in seen_keys or key in news:
            continue  # a new version of a known release, or two versions out together
        if release.release_date and release.release_date < today - timedelta(days=RECENT_DAYS):
            continue
        news[key] = NewRelease(artist, release, kind_of(release.title, release.record_type, artist.name))
    return list(news.values())


def seen_state(artist: FollowedArtist, releases: list[DeezerRelease], now: datetime) -> dict:
    return {
        "nome": artist.name,
        "ids": sorted({str(r.id) for r in releases}),
        "chiavi": sorted({group_key(r.title, r.record_type, artist.name) for r in releases}),
        "aggiornato": now,
    }


def novita_document(item: NewRelease, now: datetime) -> dict:
    r = item.release
    return {
        "artista": item.artist.name,
        "artista_id": item.artist.id,
        "titolo": r.title,
        "tipo": item.kind,
        "data": r.release_date.isoformat() if r.release_date else "",
        "copertina": r.cover or "",
        "link": r.link or "",
        "spotify": spotify_search_url(item.artist.name, r.title),
        "notificata": now,
    }


@dataclass
class Report:
    checked: int = 0
    first_time: int = 0
    deezer_errors: int = 0
    new_releases: int = 0
    users_told: int = 0
    notifications: int = 0
    notification_errors: int = 0
    no_topic: int = 0


async def tell_user(db: DocumentStore, uid: str, items: list[NewRelease], now: datetime,
                    sender_for: Callable[[str], NotificationSender], report: Report) -> None:
    """Save the user's news in Novità and send the notifications to their topic."""
    for item in items:
        await db.set(f"utenti/{uid}/novita/{item.release.id}", novita_document(item, now))
    settings_doc = await db.get(f"utenti/{uid}") or {}
    topic = str(settings_doc.get("ntfy") or "").strip()
    if not TOPIC_PATTERN.match(topic):
        report.no_topic += 1  # still in Novità: the notification waits for a topic in Impostazioni
        return
    if len(items) <= MAX_SINGLE_NOTIFICATIONS:
        novita = settings.APP_URL.rstrip("/") + "/#/novita"  # "Apri l'app" opens Novità
        notifications = [release_notification(i.artist.name, i.release, now, app_url=novita) for i in items]
    else:
        notifications = [summary_notification([(i.artist.name, i.release) for i in items], now)]
    sender = sender_for(topic)
    for notification in notifications:
        try:
            await sender.send(notification)
            report.notifications += 1
        except Exception:  # noqa: BLE001 - one failed notification must not stop the others
            report.notification_errors += 1


async def run_check(db: DocumentStore, deezer: DiscographySource, now: datetime,
                    sender_for: Callable[[str], NotificationSender]) -> list[str]:
    """One run: read, compare, tell; returns the lines of the report (numbers only)."""
    artists = group_artists(await db.collection_group("artisti"))
    users = {uid for a in artists.values() for uid in a.followers}
    lists = Counter(data.get("lista") for a in artists.values() for data in a.followers.values())
    report = Report()
    per_user: dict[str, list[NewRelease]] = {}
    for artist in (a for a in artists.values() if a.to_check):
        try:
            releases = await deezer.artist_releases(int(artist.id))
        except DeezerError:
            report.deezer_errors += 1
            continue
        report.checked += 1
        seen = await db.get(f"visti/{artist.id}")
        if seen is None:
            report.first_time += 1  # first time: everything becomes "seen", nothing is announced
            news = []
        else:
            news = find_new(artist, releases, seen, now.date())
        report.new_releases += len(news)
        for uid, data in artist.followers.items():
            if data.get("lista") == NOTIFY_LIST:
                kinds = wanted_kinds(data)
                per_user.setdefault(uid, []).extend(n for n in news if n.kind in kinds)
        await db.set(f"visti/{artist.id}", seen_state(artist, releases, now))
    for uid, items in per_user.items():
        if items:
            report.users_told += 1
            await tell_user(db, uid, items, now, sender_for, report)
    await db.set(STATUS_PATH, {
        "ultimo_contatto": now,
        "origine": "controllo",
        "giro": run_url(),
        "utenti": len(users),
        "artisti": report.checked,
        "uscite_nuove": report.new_releases,
    })
    return [
        f"✅ Giro del {now:%d/%m/%Y alle %H:%M}.",
        "",
        "| | Numero |",
        "|---|---|",
        f"| Utenti con almeno un artista | {len(users)} |",
        f"| Artisti in Controllare (per utente) | {lists['controllare']} |",
        f"| Artisti in Recuperando (per utente) | {lists['recuperando']} |",
        f"| Artisti controllati su Deezer | {report.checked} |",
        f"| …controllati per la prima volta (senza avvisi) | {report.first_time} |",
        f"| Artisti non letti (errore di Deezer) | {report.deezer_errors} |",
        f"| Uscite nuove | {report.new_releases} |",
        f"| Persone avvisate | {report.users_told} |",
        f"| Notifiche inviate | {report.notifications} |",
        f"| Notifiche non riuscite | {report.notification_errors} |",
        f"| Persone senza argomento ntfy (solo in Novità) | {report.no_topic} |",
    ]


def ntfy_sender(topic: str) -> NotificationSender:
    """A sender that opens and closes its connection for each notification (a few per run)."""

    class _Sender:
        async def send(self, notification) -> None:
            async with NtfyClient(topic) as ntfy:
                await ntfy.send(notification)

    return _Sender()


async def run() -> tuple[str, bool]:
    now = datetime.now(ZoneInfo(settings.TIMEZONE)).replace(microsecond=0)
    start = time.perf_counter()
    try:
        async with FirestoreClient.from_settings() as db, DeezerClient() as deezer:
            lines, ok = await run_check(db, deezer, now, ntfy_sender), True
        lines.append(f"Durata: {time.perf_counter() - start:.1f} secondi.")
    except FirestoreError as err:
        lines, ok = [f"❌ {err}"], False
    return "\n".join(["## Controllo delle uscite", "", *lines, ""]), ok


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
