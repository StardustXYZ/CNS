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
5. For the artists in Controllare, the pre-orders on iTunes (app/anteprime.py): "In arrivo"
   once, "Esce oggi" on the day, and no second notification when Deezer then has it.

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
from app.anteprime import (
    announced_titles_around, announcement_document, is_due_today, is_expired, itunes_fields, itunes_id_for, title_key,
)
from app.services.itunes import ItunesClient, ItunesError, ReleaseSource, upcoming
from app.services.ntfy import (
    NotificationSender, NtfyClient, announce_notification, list_notification, release_notification,
    reminder_notification, spotify_search_url, summary_notification,
)

LISTS_TO_CHECK = ("controllare", "recuperando")  # new releases matter in both; "archivio" is left alone
NOTIFY_LIST = "controllare"  # only these get a notification; in Recuperando they go to the end of the queue
RECENT_DAYS = 30  # an older release appearing now is Deezer filling in its catalogue, not news
MAX_SINGLE_NOTIFICATIONS = 3  # more new releases for one person become one notification
TOPIC_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
ALLOW_LIST_PATH = "config/ammessi"  # who may use CNS (managed by the administrator in the app)


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
    itunes_matched: int = 0
    itunes_errors: int = 0
    announced: int = 0
    reminders: int = 0
    not_admitted: int = 0


@dataclass
class UserNews:
    """What one person is told in this run."""

    releases: list[NewRelease] = field(default_factory=list)
    announced: list[dict] = field(default_factory=list)  # new announcements (documents)
    reminders: list[dict] = field(default_factory=list)  # announcements coming out today
    skip_titles: set[str] = field(default_factory=set)  # announced titles: no second notification from Deezer

    def __bool__(self) -> bool:
        return bool(self.releases or self.announced or self.reminders)


def notifications_for(news: UserNews, now: datetime) -> list:
    """One person's notifications: releases (one each up to 3, else one together), then the
    announcements the same way, then the release-day reminders."""
    novita = settings.APP_URL.rstrip("/") + "/#/novita"  # "Apri l'app" opens Novità
    out = []
    releases = [n for n in news.releases if title_key(n.release.title) not in news.skip_titles]
    if len(releases) <= MAX_SINGLE_NOTIFICATIONS:
        out += [release_notification(n.artist.name, n.release, now, app_url=novita) for n in releases]
    else:
        out.append(summary_notification([(n.artist.name, n.release) for n in releases], now))
    if len(news.announced) <= MAX_SINGLE_NOTIFICATIONS:
        out += [announce_notification(a["artista"], a["titolo"], a["tipo"], date.fromisoformat(a["data"]),
                                      a.get("copertina") or None, a.get("link") or None, now) for a in news.announced]
    else:
        lines = [f"{a['artista']}: {a['titolo']} ({a['data'][8:10]}/{a['data'][5:7]})" for a in news.announced]
        out.append(list_notification(f"{len(news.announced)} uscite in arrivo", lines, now))
    out += [reminder_notification(a["artista"], a["titolo"], a["tipo"], a.get("copertina") or None, now)
            for a in news.reminders]
    return out


def is_admitted(uid: str, settings_doc: dict, allow_list: dict | None) -> bool:
    """Whether the person is still admitted (config/ammessi): the administrator, or an e-mail in
    the list. The app saves each person's e-mail in their settings. Without a list: everybody."""
    if allow_list is None:
        return True
    if allow_list.get("admin") == uid:
        return True
    email = str(settings_doc.get("email") or "").strip().lower()
    return bool(email) and email in [str(e).lower() for e in allow_list.get("email", [])]


async def tell_user(db: DocumentStore, uid: str, news: UserNews, now: datetime,
                    sender_for: Callable[[str], NotificationSender], report: Report,
                    allow_list: dict | None = None) -> None:
    """Save the user's news in Novità and send the notifications to their topic."""
    settings_doc = await db.get(f"utenti/{uid}") or {}
    if not is_admitted(uid, settings_doc, allow_list):
        report.not_admitted += 1  # removed from the list: nothing more for them
        return
    for item in news.releases:
        await db.set(f"utenti/{uid}/novita/{item.release.id}", novita_document(item, now))
    topic = str(settings_doc.get("ntfy") or "").strip()
    if not TOPIC_PATTERN.match(topic):
        report.no_topic += 1  # still in the app: the notification waits for a topic in Impostazioni
        return
    sender = sender_for(topic)
    for notification in notifications_for(news, now):
        try:
            await sender.send(notification)
            report.notifications += 1
        except Exception:  # noqa: BLE001 - one failed notification must not stop the others
            report.notification_errors += 1


def announcements_by_user(documents: list[tuple[str, dict]]) -> dict[str, dict[str, dict]]:
    """Saved announcements ``utenti/<code>/anteprime/<iTunes id>``: user code -> id -> document."""
    result: dict[str, dict[str, dict]] = {}
    for path, data in documents:
        parts = path.split("/")
        if len(parts) == 4 and parts[0] == "utenti" and parts[2] == "anteprime":
            result.setdefault(parts[1], {})[parts[3]] = data
    return result


async def check_announcements(db: DocumentStore, itunes: ReleaseSource, artist: FollowedArtist,
                              releases: list[DeezerRelease], seen: dict | None, now: datetime,
                              saved: dict[str, dict[str, dict]], per_user: dict[str, UserNews], report: Report) -> dict:
    """The artist's pre-orders on iTunes, saved and announced to the people who have it in
    Controllare. Returns the iTunes fields to keep with the releases already seen."""
    try:
        itunes_id, fields = await itunes_id_for(itunes, artist.name, [r.title for r in releases], seen, now)
        coming = upcoming(await itunes.artist_releases(itunes_id), now.date()) if itunes_id else []
    except ItunesError:
        report.itunes_errors += 1
        return itunes_fields(seen)
    if itunes_id:
        report.itunes_matched += 1
    for uid, data in artist.followers.items():
        if data.get("lista") != NOTIFY_LIST:
            continue
        kinds = wanted_kinds(data)
        mine = saved.setdefault(uid, {})
        for release in coming:
            if release.kind not in kinds:
                continue
            key, path = str(release.id), f"utenti/{uid}/anteprime/{release.id}"
            old = mine.get(key)
            if old is None:
                doc = announcement_document(artist.name, artist.id, release, now)
                await db.set(path, doc)
                mine[key] = doc
                per_user.setdefault(uid, UserNews()).announced.append(doc)
                report.announced += 1
            elif old.get("data") != release.release_date.isoformat():
                # The date moved: same announcement, new date, and a new reminder on the new day
                mine[key] = {**old, "data": release.release_date.isoformat(), "promemoria": None}
                await db.set(path, mine[key])
    return fields


async def run_check(db: DocumentStore, deezer: DiscographySource, now: datetime,
                    sender_for: Callable[[str], NotificationSender], itunes: ReleaseSource | None = None) -> list[str]:
    """One run: read, compare, tell; returns the lines of the report (numbers only)."""
    artists = group_artists(await db.collection_group("artisti"))
    users = {uid for a in artists.values() for uid in a.followers}
    lists = Counter(data.get("lista") for a in artists.values() for data in a.followers.values())
    saved_announcements = announcements_by_user(await db.collection_group("anteprime")) if itunes else {}
    allow_list = await db.get(ALLOW_LIST_PATH)
    report = Report()
    today = now.date()
    per_user: dict[str, UserNews] = {}
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
            news = find_new(artist, releases, seen, today)
        report.new_releases += len(news)
        for uid, data in artist.followers.items():
            if data.get("lista") == NOTIFY_LIST:
                kinds = wanted_kinds(data)
                per_user.setdefault(uid, UserNews()).releases.extend(n for n in news if n.kind in kinds)
        fields = itunes_fields(seen)
        if itunes and any(d.get("lista") == NOTIFY_LIST for d in artist.followers.values()):
            fields = await check_announcements(db, itunes, artist, releases, seen, now, saved_announcements, per_user, report)
        await db.set(f"visti/{artist.id}", {**seen_state(artist, releases, now), **fields})
    # Release day of the announced releases; old announcements go away
    for uid, mine in saved_announcements.items():
        for key, doc in list(mine.items()):
            path = f"utenti/{uid}/anteprime/{key}"
            if is_due_today(doc, today):
                mine[key] = {**doc, "promemoria": now}
                await db.set(path, mine[key])
                per_user.setdefault(uid, UserNews()).reminders.append(mine[key])
                report.reminders += 1
            elif is_expired(doc, today):
                await db.delete(path)
                del mine[key]
        if uid in per_user:
            per_user[uid].skip_titles = announced_titles_around(mine, today)
    for uid, user_news in per_user.items():
        if user_news:
            report.users_told += 1
            await tell_user(db, uid, user_news, now, sender_for, report, allow_list)
    await db.set(STATUS_PATH, {
        "ultimo_contatto": now,
        "origine": "controllo",
        "giro": run_url(),
        "utenti": len(users),
        "artisti": report.checked,
        "uscite_nuove": report.new_releases,
        "in_arrivo": report.announced,
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
        f"| Artisti abbinati su iTunes | {report.itunes_matched} |",
        f"| Errori di iTunes | {report.itunes_errors} |",
        f"| Uscite in arrivo annunciate ora | {report.announced} |",
        f"| Promemoria «esce oggi» | {report.reminders} |",
        f"| Persone avvisate | {report.users_told} |",
        f"| Notifiche inviate | {report.notifications} |",
        f"| Notifiche non riuscite | {report.notification_errors} |",
        f"| Persone senza argomento ntfy (solo in Novità) | {report.no_topic} |",
        f"| Persone non più ammesse (saltate) | {report.not_admitted} |",
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
        async with FirestoreClient.from_settings() as db, DeezerClient() as deezer, ItunesClient() as itunes:
            lines, ok = await run_check(db, deezer, now, ntfy_sender, itunes), True
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
