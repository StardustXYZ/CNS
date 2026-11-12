"""ntfy notifications: text, buttons, night silence and sending (to a fake server)."""

from __future__ import annotations

from datetime import date, datetime
import json
from zoneinfo import ZoneInfo

import httpx
import pytest

from app.services.deezer import DeezerRelease
from app.services.ntfy import (
    PRIORITY_DEFAULT,
    PRIORITY_QUIET,
    NtfyClient,
    is_quiet,
    release_notification,
    spotify_search_url,
)
from tests.conftest import json_transport

ROME = ZoneInfo("Europe/Rome")
AFTERNOON = datetime(2026, 11, 12, 15, 30, tzinfo=ROME)


def release(title="Christmas Wonderland", kind="single", link="https://www.deezer.com/album/1139685681"):
    return DeezerRelease(id=1139685681, title=title, record_type=kind, release_date=date(2026, 11, 6),
                         cover="https://cdn/cover.jpg", link=link)


def test_spotify_search_url_is_encoded():
    assert spotify_search_url("K/DA", "MORE (feat. Ava)") == "https://open.spotify.com/search/K%2FDA%20MORE%20%28feat.%20Ava%29"


@pytest.mark.parametrize("hour, quiet", [(22, False), (23, True), (0, True), (7, True), (8, False), (15, False)])
def test_quiet_hours_italian_time(hour, quiet):
    assert is_quiet(datetime(2026, 11, 12, hour, 30, tzinfo=ROME)) is quiet


def test_quiet_hours_use_italian_time_even_from_utc():
    # 22:30 UTC in November is 23:30 in Italy
    assert is_quiet(datetime(2026, 11, 12, 22, 30, tzinfo=ZoneInfo("UTC"))) is True


def test_release_notification():
    n = release_notification("Ava Max", release(), AFTERNOON, app_url="https://app/")
    assert n.title == "Nuovo singolo: Ava Max"
    assert n.message == "Christmas Wonderland\nUscito il 06/11/2026"
    assert n.click == spotify_search_url("Ava Max", "Christmas Wonderland")
    assert n.attach == "https://cdn/cover.jpg"
    assert [label for label, _ in n.actions] == ["Apri su Spotify", "Apri su Deezer", "Apri l'app"]
    assert n.actions[1][1] == "https://www.deezer.com/album/1139685681"
    assert n.priority == PRIORITY_DEFAULT


@pytest.mark.parametrize("kind, title", [("album", "Nuovo album"), ("ep", "Nuovo EP"), ("compile", "Nuova raccolta"), ("boh", "Nuova uscita")])
def test_notification_title_by_type(kind, title):
    assert release_notification("Ava Max", release(kind=kind), AFTERNOON).title == f"{title}: Ava Max"


def test_featuring_notification():
    assert release_notification("Ava Max", release("BURN (feat. Ava Max)"), AFTERNOON).title == "Nuovo featuring: Ava Max"


def test_night_notification_is_silent():
    assert release_notification("Ava Max", release(), datetime(2026, 11, 13, 0, 5, tzinfo=ROME)).priority == PRIORITY_QUIET


def test_payload_without_deezer_link():
    n = release_notification("Ava Max", release(link=None), AFTERNOON, app_url="https://app/")
    body = n.payload("argomento")
    assert body["topic"] == "argomento"
    assert [a["label"] for a in body["actions"]] == ["Apri su Spotify", "Apri l'app"]
    assert all(a["action"] == "view" for a in body["actions"])
    assert body["tags"] == ["headphones"]


async def test_ntfy_client_posts_json():
    log: list[httpx.Request] = []
    transport = json_transport({"/": {"id": "abc"}}, log)
    async with NtfyClient("argomento-segreto", server="https://ntfy.example", transport=transport) as ntfy:
        await ntfy.send(release_notification("Ava Max", release(), AFTERNOON))
    sent = json.loads(log[0].content)
    assert log[0].method == "POST"
    assert sent["topic"] == "argomento-segreto"
    assert sent["title"] == "Nuovo singolo: Ava Max"


async def test_ntfy_client_raises_when_refused():
    transport = json_transport({"/": httpx.Response(429, json={"error": "limit"})})
    async with NtfyClient("t", server="https://ntfy.example", transport=transport) as ntfy:
        with pytest.raises(httpx.HTTPStatusError):
            await ntfy.send(release_notification("Ava Max", release(), AFTERNOON))


def test_ntfy_client_needs_a_topic():
    with pytest.raises(ValueError, match="NTFY_TOPIC"):
        NtfyClient("")
