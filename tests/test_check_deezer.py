"""Feasibility report with a fake Deezer and a fake notification sender."""

from __future__ import annotations

from datetime import date, datetime
from zoneinfo import ZoneInfo

from app.check_deezer import check, latest_release, report_markdown, send_test_notification
from app.services.deezer import DeezerArtist, DeezerBlocked, DeezerRelease

TODAY = date(2026, 11, 12)


def rel(id_, title, day, kind="single"):
    return DeezerRelease(id=id_, title=title, record_type=kind, release_date=date.fromisoformat(day),
                         cover=f"https://cdn/{id_}.jpg", link=f"https://www.deezer.com/album/{id_}")


class FakeDeezer:
    def __init__(self, artists, discographies, blocked=()):
        self.artists, self.discographies, self.blocked = artists, discographies, set(blocked)
        self.calls = 0

    async def search_artists(self, query, limit=10):
        self.calls += 1
        if query in self.blocked:
            raise DeezerBlocked("risposta non di Deezer (HTTP 403)")
        return self.artists.get(query, [])

    async def artist_releases(self, artist_id):
        self.calls += 2
        return self.discographies[artist_id]


class FakeSender:
    def __init__(self):
        self.sent = []

    async def send(self, notification):
        self.sent.append(notification)


def fake():
    return FakeDeezer(
        artists={
            "Ava Max": [DeezerArtist(12948083, "Ava Max", 1000, link="https://www.deezer.com/artist/12948083")],
            "Amy Lee": [DeezerArtist(1, "Amy Lee", 153), DeezerArtist(15741, "Amy Lee", 265225)],
        },
        discographies={
            12948083: [rel(1, "Sweet but Psycho", "2018-08-17"), rel(2, "Heaven & Hell", "2020-09-18", "album"),
                       rel(3, "BURN (feat. Ava Max)", "2026-10-09"), rel(4, "Christmas Wonderland", "2026-11-06"),
                       rel(5, "Futuro", "2026-12-04", "album")],
            15741: [rel(6, "Aftermath", "2014-02-18", "album")],
        },
        blocked={"K/DA"},
    )


async def test_check_reports_each_artist():
    reports = await check(fake(), ["Ava Max", "Amy Lee", "K/DA", "Nessuno"])
    ava, amy, kda, nobody = reports
    assert ava.ok and len(ava.releases) == 5 and ava.calls == 3
    assert [r.title for r in ava.featurings()] == ["BURN (feat. Ava Max)"]
    assert [r.title for r in ava.upcoming(TODAY)] == ["Futuro"]
    assert amy.artist.id == 15741  # the right Amy Lee, not the first result
    assert not kda.ok and "DeezerBlocked" in kda.error
    assert not nobody.ok and nobody.error == "nessun artista trovato"


async def test_report_table():
    text = report_markdown(await check(fake(), ["Ava Max", "K/DA"]), TODAY)
    ava_row = next(line for line in text.splitlines() if line.startswith("| Ava Max"))
    cells = [c.strip() for c in ava_row.split("|")[1:-1]]
    # Cercato, Trovato, Uscite, Album, EP, Singoli, Raccolte, Featuring, Prima, Ultima, Future, Chiamate, Secondi, Esito
    assert cells[2:8] == ["5", "2", "0", "3", "0", "1"]
    assert cells[8:11] == ["17/08/2018", "06/11/2026", "1"]
    assert cells[-1] == "✅"
    assert "1.000 fan" in cells[1]
    assert "| K/DA | — |" in text and "❌ DeezerBlocked" in text
    assert "- Ava Max: Futuro (Album, 04/12/2026)" in text


async def test_test_notification_uses_latest_release_already_out():
    reports = await check(fake(), ["Ava Max", "Amy Lee"])
    assert latest_release(reports, TODAY)[1].title == "Christmas Wonderland"  # not the future one
    sender = FakeSender()
    line = await send_test_notification(sender, reports, datetime(2026, 11, 12, 15, 0, tzinfo=ZoneInfo("Europe/Rome")))
    assert sender.sent[0].title == "Nuovo singolo: Ava Max"
    assert "con il suono" in line


async def test_no_notification_without_releases():
    sender = FakeSender()
    line = await send_test_notification(sender, await check(fake(), ["K/DA"]), datetime(2026, 11, 12, 3, 0, tzinfo=ZoneInfo("Europe/Rome")))
    assert sender.sent == [] and "non inviata" in line
