"""Notifications on the phone through ntfy (free, no account).

A release becomes one notification: title, type and cover; touching it opens Spotify on
the search for "artist + title" (without the Spotify API there is no exact link), and the
buttons open Spotify, Deezer (exact link) or the CNS app. From 23 to 8 Italian time it
arrives without sound.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Protocol
from urllib.parse import quote
from zoneinfo import ZoneInfo

import httpx

from app.config import settings
from app.services.deezer import DeezerRelease

PRIORITY_DEFAULT = 3
PRIORITY_QUIET = 2  # ntfy "low": shown, but no sound and no vibration
MAX_ACTIONS = 3  # ntfy shows at most three buttons

NEW_LABELS = {
    "album": "Nuovo album",
    "single": "Nuovo singolo",
    "ep": "Nuovo EP",
    "compile": "Nuova raccolta",
}


@dataclass(frozen=True)
class Notification:
    title: str
    message: str
    click: str | None = None
    icon: str | None = None  # small picture next to the text
    attach: str | None = None  # big picture (ntfy adds its own buttons for it)
    actions: tuple[tuple[str, str], ...] = field(default_factory=tuple)  # (label, url)
    priority: int = PRIORITY_DEFAULT
    tags: tuple[str, ...] = ("headphones",)

    def payload(self, topic: str) -> dict:
        """The JSON body ntfy expects when publishing to its root address."""
        body: dict = {
            "topic": topic,
            "title": self.title,
            "message": self.message,
            "priority": self.priority,
            "tags": list(self.tags),
        }
        if self.click:
            body["click"] = self.click
        if self.icon:
            body["icon"] = self.icon
        if self.attach:
            body["attach"] = self.attach
        if self.actions:
            body["actions"] = [
                {"action": "view", "label": label, "url": url, "clear": True}
                for label, url in self.actions[:MAX_ACTIONS]
            ]
        return body


def spotify_search_url(artist: str, title: str) -> str:
    """Spotify's search page for the release; on Android it opens the Spotify app."""
    return "https://open.spotify.com/search/" + quote(f"{artist} {title}".strip(), safe="")


def is_quiet(now: datetime, start: int = settings.QUIET_START, end: int = settings.QUIET_END) -> bool:
    """True during the silent night hours (Italian time)."""
    hour = now.astimezone(ZoneInfo(settings.TIMEZONE)).hour
    return hour >= start or hour < end if start > end else start <= hour < end


def release_notification(
    artist: str,
    release: DeezerRelease,
    now: datetime,
    app_url: str = settings.APP_URL,
    big_cover: bool = settings.BIG_COVER,
) -> Notification:
    """The notification for one new release of ``artist``.

    With ``big_cover`` the cover is attached (big picture) and only the Spotify button is
    sent, since Android would hide the others behind ntfy's own attachment buttons.
    """
    label = "Nuovo featuring" if release.is_featuring(artist) else NEW_LABELS.get(release.record_type, "Nuova uscita")
    lines = [release.title]
    if release.release_date:
        lines.append(f"Uscito il {release.release_date:%d/%m/%Y}")
    spotify = spotify_search_url(artist, release.title)
    actions = [("Apri su Spotify", spotify)]
    if not big_cover:
        if release.link:
            actions.append(("Apri su Deezer", release.link))
        actions.append(("Apri l'app", app_url))
    return Notification(
        title=f"{label}: {artist}",
        message="\n".join(lines),
        click=spotify,
        icon=None if big_cover else release.cover,
        attach=release.cover if big_cover else None,
        actions=tuple(actions),
        priority=PRIORITY_QUIET if is_quiet(now) else PRIORITY_DEFAULT,
    )


class NotificationSender(Protocol):
    """Anything that can deliver a notification (the real ntfy client or a test fake)."""

    async def send(self, notification: Notification) -> None: ...


class NtfyClient:
    """Publishes to ntfy. Use as ``async with NtfyClient(topic) as ntfy: ...``."""

    def __init__(
        self,
        topic: str | None = None,
        server: str | None = None,
        timeout: float = 15.0,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self.topic = topic if topic is not None else settings.NTFY_TOPIC
        if not self.topic:
            raise ValueError("NTFY_TOPIC non configurato (segreto di GitHub o file .env)")
        self._client = httpx.AsyncClient(base_url=server or settings.NTFY_SERVER, timeout=timeout, transport=transport)

    async def __aenter__(self) -> NtfyClient:
        return self

    async def __aexit__(self, *exc) -> None:
        await self._client.aclose()

    async def send(self, notification: Notification) -> None:
        """Deliver the notification (raises if ntfy refuses it)."""
        resp = await self._client.post("/", json=notification.payload(self.topic))
        resp.raise_for_status()
