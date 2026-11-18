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
import contextlib
from dataclasses import dataclass, field, replace
from datetime import date, datetime, timedelta
import os
import re
import sys
import time
from typing import Awaitable, Callable, NamedTuple
from zoneinfo import ZoneInfo

from app.config import settings
from app.prova_firebase import STATUS_PATH, run_url
from app.services.deezer import DeezerClient, DeezerError, DeezerRelease, DiscographySource
from app.services.discografia import KINDS, group_key, kind_of
from app.services.fcm import FCM_SCOPES, FcmClient, PushSender
from app.services.firestore import (
    DocumentStore, FirestoreClient, FirestoreError, service_account_info, service_account_token,
)
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
MAX_ATTEMPTS = 3  # a notification that fails is tried again in the next runs, up to this many in all
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


def seen_state(artist: FollowedArtist, releases: list[DeezerRelease], now: datetime,
               previous: dict | None = None) -> dict:
    """What is saved in ``visti/<Deezer id>``: the releases seen so far plus the ones in
    ``releases``. It only grows: a release Deezer leaves out of its catalogue for a moment
    would otherwise look new when it comes back."""
    before = previous or {}
    return {
        "nome": artist.name,
        "ids": sorted({str(i) for i in before.get("ids", [])} | {str(r.id) for r in releases}),
        "chiavi": sorted(set(before.get("chiavi", [])) | {group_key(r.title, r.record_type, artist.name) for r in releases}),
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
    to_retry: int = 0  # artists left "unseen" because a notification failed: checked again next run
    no_topic: int = 0
    itunes_matched: int = 0
    itunes_errors: int = 0
    announced: int = 0
    reminders: int = 0
    not_admitted: int = 0
    phones: int = 0  # phones registered in the Android app
    push_sent: int = 0
    push_errors: int = 0
    phones_removed: int = 0  # the app was removed from the phone: its document goes away


@dataclass
class UserNews:
    """What one person is told in this run."""

    releases: list[NewRelease] = field(default_factory=list)
    announced: list[dict] = field(default_factory=list)  # announcements not told yet (documents)
    announced_keys: list[str] = field(default_factory=list)  # their iTunes ids, in the same order
    reminders: list[dict] = field(default_factory=list)  # announcements coming out today
    reminder_keys: list[str] = field(default_factory=list)  # their iTunes ids, in the same order
    skip_titles: set[str] = field(default_factory=set)  # announced titles: no second notification from Deezer

    def __bool__(self) -> bool:
        return bool(self.releases or self.announced or self.reminders)


def release_notifications(news: UserNews, now: datetime) -> list:
    """The notifications of the new releases: one each up to 3, else one together."""
    novita = settings.APP_URL.rstrip("/") + "/#/novita"  # "Apri l'app" opens Novità
    releases = [n for n in news.releases if title_key(n.release.title) not in news.skip_titles]
    if len(releases) <= MAX_SINGLE_NOTIFICATIONS:
        return [release_notification(n.artist.name, n.release, now, app_url=novita) for n in releases]
    return [summary_notification([(n.artist.name, n.release) for n in releases], now)]


def notifications_for(news: UserNews, now: datetime) -> list:
    """One person's notifications: releases (one each up to 3, else one together), then the
    announcements the same way, then the release-day reminders."""
    return release_notifications(news, now) + announcement_notifications(news, now)


def announcement_notifications(news: UserNews, now: datetime) -> list:
    """The announcements (one each up to 3, else one together) and the release-day reminders."""
    out = []
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
    the list. The app saves each person's e-mail in their settings. Without a list: nobody, as
    in the security rules (firebase/firestore.rules): a deleted list must not open the doors."""
    if allow_list is None:
        return False
    if allow_list.get("admin") == uid:
        return True
    email = str(settings_doc.get("email") or "").strip().lower()
    return bool(email) and email in [str(e).lower() for e in allow_list.get("email", [])]


class Delivery(NamedTuple):
    """How the notifications of one person went: the new releases, and the announcements and
    reminders. ``False`` means one failed (the caller decides whether to try again)."""

    releases_ok: bool = True
    others_ok: bool = True
    admitted: bool = True  # False: the person is not admitted (any more) and was told nothing


async def tell_user(db: DocumentStore, uid: str, news: UserNews, now: datetime,
                    sender_for: Callable[[str], NotificationSender], report: Report,
                    allow_list: dict | None = None, phones: list[tuple[str, str]] | None = None,
                    push: PushSender | None = None) -> Delivery:
    """Save the user's news in Novità and send the notifications to their ntfy topic and to
    the phones registered in the Android app (``phones``: document path and token).

    ``releases_ok`` is False when a notification of the new releases failed and there are
    tries left: the caller then keeps the artists "unseen", so the next run comes back here.
    A release already in Novità and not marked ``da_riprovare`` was told in an earlier run
    (the run may have stopped before it could write "seen"): it is skipped, never told twice.
    ``others_ok`` is False when an announcement or a reminder failed: ``settle_announcements``
    decides what to do with those documents.
    """
    settings_doc = await db.get(f"utenti/{uid}") or {}
    if not is_admitted(uid, settings_doc, allow_list):
        report.not_admitted += 1  # removed from the list: nothing more for them
        return Delivery(admitted=False)
    pending: list[NewRelease] = []
    tries: dict[str, int] = {}  # release id -> tries so far, this one included
    first_told: dict[str, datetime] = {}  # release id -> when it first reached Novità
    for item in news.releases:
        old = await db.get(f"utenti/{uid}/novita/{item.release.id}")
        if old is not None and not old.get("da_riprovare"):
            continue
        pending.append(item)
        tries[str(item.release.id)] = int((old or {}).get("tentativi") or 0) + 1
        first_told[str(item.release.id)] = (old or {}).get("notificata") or now
    news = replace(news, releases=pending)
    if not news:
        return Delivery()
    report.users_told += 1
    # In Novità at once, marked "to try again" until the notifications have gone out
    for item in pending:
        key = str(item.release.id)
        await db.set(f"utenti/{uid}/novita/{key}",
                     {**novita_document(item, first_told[key]), "da_riprovare": True, "tentativi": tries[key]})
    release_part = release_notifications(news, now)
    notifications = release_part + announcement_notifications(news, now)
    failed = other_failed = False  # a notification of the releases / of the announcements did not go out
    phones = phones if push else []
    topic = str(settings_doc.get("ntfy") or "").strip()
    if not TOPIC_PATTERN.match(topic):
        if not phones:
            report.no_topic += 1  # still in the app: the notification waits for a topic or a phone
    else:
        sender = sender_for(topic)
        for notification in notifications:
            try:
                await sender.send(notification)
                report.notifications += 1
            except Exception:  # noqa: BLE001 - one failed notification must not stop the others
                report.notification_errors += 1
                if any(notification is n for n in release_part):
                    failed = True
                else:
                    other_failed = True
    for path, token in phones or []:
        for notification in notifications:
            try:
                delivered = await push.send(token, notification)
            except Exception:  # noqa: BLE001 - one phone must not stop the others
                report.push_errors += 1
                if any(notification is n for n in release_part):
                    failed = True
                else:
                    other_failed = True
                continue
            if not delivered:
                await db.delete(path)  # the app is not on that phone any more
                report.phones_removed += 1
                break
            report.push_sent += 1
    retry = False
    for item in pending:
        key = str(item.release.id)
        if failed and tries[key] < MAX_ATTEMPTS:
            retry = True  # left marked: the next run tries again
        else:
            await db.set(f"utenti/{uid}/novita/{key}", novita_document(item, first_told[key]))
    return Delivery(releases_ok=not retry, others_ok=not other_failed)


async def settle_announcements(db: DocumentStore, uid: str, news: UserNews, delivery: Delivery, now: datetime,
                               saved: dict[str, dict[str, dict]], report: Report) -> None:
    """After telling a person: an announcement or reminder that went out is closed; one that
    failed stays open for the next run, until ``MAX_ATTEMPTS`` tries in all. For someone who is
    not admitted (any more) they are closed too, so they do not come back every run, but the
    reminder is not counted as sent.

    An announcement stays marked ``da_riprovare`` until it is told; a reminder stays
    ``promemoria: None``, so it is due again the same day.
    """
    mine = saved.setdefault(uid, {})
    delivered = delivery.others_ok
    for key in news.announced_keys:
        doc = mine[key]
        tries = int(doc.get("tentativi") or 0) + 1
        if delivered or tries >= MAX_ATTEMPTS:
            mine[key] = {k: v for k, v in doc.items() if k not in ("da_riprovare", "tentativi")}
        else:
            mine[key] = {**doc, "da_riprovare": True, "tentativi": tries}
        await db.set(f"utenti/{uid}/anteprime/{key}", mine[key])
    for key in news.reminder_keys:
        doc = mine[key]
        tries = int(doc.get("tentativi_promemoria") or 0) + 1
        if delivered or tries >= MAX_ATTEMPTS:
            mine[key] = {**{k: v for k, v in doc.items() if k != "tentativi_promemoria"}, "promemoria": now}
            report.reminders += delivered and delivery.admitted
        else:
            mine[key] = {**doc, "tentativi_promemoria": tries}
        await db.set(f"utenti/{uid}/anteprime/{key}", mine[key])


def phones_by_user(documents: list[tuple[str, dict]]) -> dict[str, list[tuple[str, str]]]:
    """The phones of each person: "utenti/<code>/telefoni/<id>" -> {code: [(path, token)]}."""
    found: dict[str, list[tuple[str, str]]] = {}
    for path, data in documents:
        parts = path.split("/")
        token = data.get("token")
        if len(parts) == 4 and parts[0] == "utenti" and parts[2] == "telefoni" and isinstance(token, str) and token:
            found.setdefault(parts[1], []).append((path, token))
    return found


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
                              saved: dict[str, dict[str, dict]], report: Report,
                              admitted: Callable[[str], Awaitable[bool]]) -> dict:
    """The artist's pre-orders on iTunes, saved for the people who have it in Controllare
    (and are admitted: for the others nothing is created).
    A new one is saved marked ``da_riprovare``: ``run_check`` tells it and ``settle_announcements``
    closes it, so an announcement is never lost between saving and telling. Returns the iTunes
    fields to keep with the releases already seen."""
    try:
        itunes_id, fields = await itunes_id_for(itunes, artist.name, [r.title for r in releases], seen, now)
        coming = upcoming(await itunes.artist_releases(itunes_id), now.date()) if itunes_id else []
    except ItunesError:
        report.itunes_errors += 1
        return itunes_fields(seen)
    if itunes_id:
        report.itunes_matched += 1
    for uid, data in artist.followers.items():
        if data.get("lista") != NOTIFY_LIST or not await admitted(uid):
            continue
        kinds = wanted_kinds(data)
        mine = saved.setdefault(uid, {})
        for release in coming:
            if release.kind not in kinds:
                continue
            key, path = str(release.id), f"utenti/{uid}/anteprime/{release.id}"
            old = mine.get(key)
            if old is None:
                doc = {**announcement_document(artist.name, artist.id, release, now), "da_riprovare": True, "tentativi": 0}
                await db.set(path, doc)
                mine[key] = doc
                report.announced += 1
            elif old.get("data") != release.release_date.isoformat():
                # The date moved: same announcement, new date, and a new reminder on the new day
                mine[key] = {k: v for k, v in old.items() if k != "tentativi_promemoria"}
                mine[key].update(data=release.release_date.isoformat(), promemoria=None)
                await db.set(path, mine[key])
    return fields


async def run_check(db: DocumentStore, deezer: DiscographySource, now: datetime,
                    sender_for: Callable[[str], NotificationSender], itunes: ReleaseSource | None = None,
                    push: PushSender | None = None) -> list[str]:
    """One run: read, compare, tell; returns the lines of the report (numbers only)."""
    artists = group_artists(await db.collection_group("artisti"))
    users = {uid for a in artists.values() for uid in a.followers}
    lists = Counter(data.get("lista") for a in artists.values() for data in a.followers.values())
    saved_announcements = announcements_by_user(await db.collection_group("anteprime")) if itunes else {}
    allow_list = await db.get(ALLOW_LIST_PATH)
    admission: dict[str, bool] = {}  # asked once per person in a run

    async def admitted(uid: str) -> bool:
        if uid not in admission:
            admission[uid] = is_admitted(uid, await db.get(f"utenti/{uid}") or {}, allow_list)
        return admission[uid]

    phones = phones_by_user(await db.collection_group("telefoni")) if push else {}
    report = Report()
    report.phones = sum(len(p) for p in phones.values())
    today = now.date()
    per_user: dict[str, UserNews] = {}
    # "Seen" is written only after the people are told: if the run stops halfway, or a
    # notification fails, the next run finds the same releases again instead of losing them.
    pending_seen: dict[str, dict] = {}  # Deezer id -> its ``visti`` document
    recipients: dict[str, set[str]] = {}  # Deezer id -> the people due to be told about its news
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
                mine = [n for n in news if n.kind in kinds]
                per_user.setdefault(uid, UserNews()).releases.extend(mine)
                if mine:
                    recipients.setdefault(artist.id, set()).add(uid)
        fields = itunes_fields(seen)
        if itunes and any(d.get("lista") == NOTIFY_LIST for d in artist.followers.values()):
            fields = await check_announcements(db, itunes, artist, releases, seen, now, saved_announcements, report, admitted)
        pending_seen[artist.id] = {**seen_state(artist, releases, now, seen), **fields}
    # What is still to tell about the announced releases: the new ones and the ones whose
    # notification failed before (``da_riprovare``), and the reminders of the release day (not
    # sent yet: ``promemoria`` stays empty until it is). Old announcements go away.
    for uid, mine in saved_announcements.items():
        for key, doc in list(mine.items()):
            if is_expired(doc, today):
                await db.delete(f"utenti/{uid}/anteprime/{key}")
                del mine[key]
                continue
            if doc.get("da_riprovare"):
                user = per_user.setdefault(uid, UserNews())
                user.announced.append(doc)
                user.announced_keys.append(key)
            if is_due_today(doc, today):
                user = per_user.setdefault(uid, UserNews())
                user.reminders.append(doc)
                user.reminder_keys.append(key)
        if uid in per_user:
            per_user[uid].skip_titles = announced_titles_around(mine, today)
    to_retry: set[str] = set()  # people a notification failed for: their artists are checked again
    for uid, user_news in per_user.items():
        if not user_news:
            continue
        delivery = await tell_user(db, uid, user_news, now, sender_for, report, allow_list, phones.get(uid, []), push)
        if not delivery.releases_ok:
            to_retry.add(uid)
        await settle_announcements(db, uid, user_news, delivery, now, saved_announcements, report)
    for artist_id, state in pending_seen.items():
        if recipients.get(artist_id, set()) & to_retry:
            report.to_retry += 1
            continue
        await db.set(f"visti/{artist_id}", state)
    await db.set(STATUS_PATH, {
        "ultimo_contatto": now,
        "origine": "controllo",
        "giro": run_url(),
        "utenti": len(users),
        "artisti": report.checked,
        "uscite_nuove": report.new_releases,
        "in_arrivo": report.announced,
    })
    warning = [] if allow_list is not None else [
        "⚠️ Manca la lista delle persone ammesse (config/ammessi su Firebase): nessuno viene avvisato.", "",
    ]
    return [
        f"✅ Giro del {now:%d/%m/%Y alle %H:%M}.",
        "",
        *warning,
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
        f"| Artisti da ricontrollare (notifica non riuscita) | {report.to_retry} |",
        f"| Telefoni con l'app Android | {report.phones} |",
        f"| Notifiche inviate all'app | {report.push_sent} |",
        f"| Notifiche all'app non riuscite | {report.push_errors} |",
        f"| Telefoni tolti (app disinstallata) | {report.phones_removed} |",
        f"| Persone senza notifiche (solo in Novità) | {report.no_topic} |",
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
        info = service_account_info()
        project = info.get("project_id") or settings.FIREBASE_PROJECT_ID
        try:  # without FCM the check goes on: ntfy and Novità do not need it
            push_token = await asyncio.to_thread(service_account_token, info, FCM_SCOPES)
        except Exception:  # noqa: BLE001 - google-auth raises its own errors
            push_token = None
        fcm_client = FcmClient(project, push_token) if push_token else contextlib.nullcontext()
        async with (FirestoreClient.from_settings() as db, DeezerClient() as deezer, ItunesClient() as itunes,
                    fcm_client as fcm):
            lines, ok = await run_check(db, deezer, now, ntfy_sender, itunes, fcm), True
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
