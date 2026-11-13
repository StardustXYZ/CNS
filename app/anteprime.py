"""Announced releases (phase 6): the iTunes pre-orders of the artists in Controllare.

Used by the scheduled check (app/controllo.py):
- the iTunes artist that matches a Deezer artist is found once and saved with the releases
  already seen (``visti/<Deezer id>``: fields ``itunes_*``); if none matches, it is tried
  again after a week;
- each announced release becomes ``utenti/<code>/anteprime/<iTunes id>`` for the people who
  have the artist in Controllare (the app shows it under "In arrivo"), with one notification;
- on the release day a reminder ("Esce oggi"); a week later the announcement is removed.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta

from app.services.discografia import base_title, normalize
from app.services.itunes import ItunesRelease, ReleaseSource, match_artist
from app.services.ntfy import spotify_search_url

ITUNES_RETRY_DAYS = 7  # an artist not found on iTunes is searched again after this
KEEP_DAYS_AFTER = 7  # an announcement stays this long after its day, then it is removed
SAME_RELEASE_DAYS = 3  # a Deezer release this close to an announced one with the same title is the same


def itunes_fields(seen: dict | None) -> dict:
    """The iTunes match saved with the releases already seen."""
    return {k: v for k, v in (seen or {}).items() if k.startswith("itunes_")}


async def itunes_id_for(itunes: ReleaseSource, name: str, deezer_titles: list[str], seen: dict | None,
                        now: datetime) -> tuple[int | None, dict]:
    """The iTunes artist id (saved, or searched now) and the fields to save."""
    saved = itunes_fields(seen)
    if saved.get("itunes_id"):
        return int(saved["itunes_id"]), saved
    searched = saved.get("itunes_cercato")
    if isinstance(searched, datetime) and now - searched < timedelta(days=ITUNES_RETRY_DAYS):
        return None, saved
    artist, _, overlap = await match_artist(itunes, name, deezer_titles)
    if artist and overlap >= 1:
        return artist.id, {"itunes_id": artist.id, "itunes_nome": artist.name, "itunes_comuni": overlap}
    return None, {"itunes_cercato": now}


def announcement_document(artist_name: str, artist_id: str, release: ItunesRelease, now: datetime) -> dict:
    return {
        "artista": artist_name,
        "artista_id": artist_id,
        "titolo": release.title,
        "tipo": release.kind,
        "data": release.release_date.isoformat() if release.release_date else "",
        "copertina": release.cover or "",
        "link": release.link or "",
        "spotify": spotify_search_url(artist_name, release.title),
        "avvisata": now,
        "promemoria": None,
    }


def title_key(title: str) -> str:
    """Titles compared without version marks and punctuation (iTunes and Deezer write them alike)."""
    return normalize(base_title(title))


def announced_titles_around(announcements: dict[str, dict], today: date) -> set[str]:
    """Titles announced for the days around today: when they arrive on Deezer they are not news again."""
    start, end = (today - timedelta(days=SAME_RELEASE_DAYS)).isoformat(), (today + timedelta(days=1)).isoformat()
    return {title_key(a.get("titolo", "")) for a in announcements.values() if start <= str(a.get("data", "")) <= end}


def is_expired(announcement: dict, today: date) -> bool:
    day = str(announcement.get("data") or "")
    return bool(day) and day < (today - timedelta(days=KEEP_DAYS_AFTER)).isoformat()


def is_due_today(announcement: dict, today: date) -> bool:
    return announcement.get("data") == today.isoformat() and not announcement.get("promemoria")
