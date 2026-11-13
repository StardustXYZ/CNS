"""Announced releases in the scheduled check, with fake Firestore, Deezer, iTunes and ntfy:
"In arrivo" once, the date moving, "Esce oggi" on the day, no second notification from
Deezer, old announcements removed, the iTunes match saved."""

from __future__ import annotations

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from app.controllo import FollowedArtist, run_check, seen_state
from app.services.deezer import DeezerRelease
from app.services.itunes import ItunesArtist, ItunesError, ItunesRelease

ROME = ZoneInfo("Europe/Rome")
NOW = datetime(2026, 11, 13, 9, 17, tzinfo=ROME)
AVA = "12948083"
ITUNES_AVA = 1265164818


def deezer_rel(id_, title, day, kind="single"):
    return DeezerRelease(id=id_, title=title, record_type=kind, release_date=date.fromisoformat(day),
                         cover=f"https://cdn/{id_}.jpg", link=f"https://www.deezer.com/album/{id_}")


def itunes_rel(id_, title, day, kind="single"):
    return ItunesRelease(id=id_, title=title, kind=kind, release_date=date.fromisoformat(day),
                         cover=f"https://is1/{id_}.jpg", link=f"https://music.apple.com/it/album/{id_}")


AVA_DEEZER = [deezer_rel(1, "Sweet but Psycho", "2018-08-17"), deezer_rel(2, "Heaven & Hell", "2020-09-18", "album")]
AVA_ITUNES_OLD = [itunes_rel(901, "Sweet but Psycho", "2018-08-17"), itunes_rel(902, "Heaven & Hell", "2020-09-18", "album")]


class FakeStore:
    def __init__(self, docs):
        self.docs = dict(docs)

    async def collection_group(self, collection_id):
        return [(p, d) for p, d in self.docs.items() if p.split("/")[-2] == collection_id]

    async def get(self, path):
        return self.docs.get(path)

    async def set(self, path, data):
        self.docs[path] = data

    async def delete(self, path):
        self.docs.pop(path, None)


class FakeDeezer:
    def __init__(self, releases):
        self.releases = releases

    async def artist_releases(self, artist_id):
        return self.releases


class FakeItunes:
    def __init__(self, releases, broken=False):
        self.releases, self.broken, self.searches = releases, broken, 0

    async def search_artists(self, name):
        self.searches += 1
        if self.broken:
            raise ItunesError("HTTP 403")
        return [ItunesArtist(ITUNES_AVA, "Ava Max", "Pop")]

    async def artist_releases(self, artist_id):
        if self.broken:
            raise ItunesError("HTTP 403")
        return self.releases


class FakeNtfy:
    def __init__(self):
        self.sent = []

    def __call__(self, topic):
        outer = self

        class Sender:
            async def send(self, n):
                outer.sent.append(n)

        return Sender()


def store(lista="controllare", extra=None, **artist_fields):
    seen = seen_state(FollowedArtist(AVA, "Ava Max"), AVA_DEEZER, NOW)
    return FakeStore({
        f"utenti/vincenzo/artisti/{AVA}": {"nome": "Ava Max", "lista": lista, **artist_fields},
        "utenti/vincenzo": {"ntfy": "argomento"},
        f"visti/{AVA}": seen,
        **(extra or {}),
    })


async def run(s, itunes, deezer=AVA_DEEZER, now=NOW):
    ntfy = FakeNtfy()
    lines = await run_check(s, FakeDeezer(deezer), now, ntfy, itunes)
    return ntfy, lines


async def test_announced_release_is_saved_and_notified_once():
    s = store()
    itunes = FakeItunes(AVA_ITUNES_OLD + [itunes_rel(950, "Nuovo Album", "2026-12-04", "album")])
    ntfy, lines = await run(s, itunes)
    assert [n.title for n in ntfy.sent] == ["In arrivo: Ava Max"]
    assert "Esce il 04/12/2026" in ntfy.sent[0].message and "(Album)" in ntfy.sent[0].message
    doc = s.docs["utenti/vincenzo/anteprime/950"]
    assert (doc["titolo"], doc["data"], doc["tipo"], doc["promemoria"]) == ("Nuovo Album", "2026-12-04", "album", None)
    assert "| Uscite in arrivo annunciate ora | 1 |" in lines
    # The iTunes match is saved: next time no search
    assert s.docs[f"visti/{AVA}"]["itunes_id"] == ITUNES_AVA
    ntfy, _ = await run(s, itunes)
    assert ntfy.sent == [] and itunes.searches == 1


async def test_a_moved_date_updates_the_announcement_without_a_new_notification():
    s = store()
    await run(s, FakeItunes(AVA_ITUNES_OLD + [itunes_rel(950, "Nuovo Album", "2026-12-04", "album")]))
    ntfy, _ = await run(s, FakeItunes(AVA_ITUNES_OLD + [itunes_rel(950, "Nuovo Album", "2026-12-11", "album")]))
    assert ntfy.sent == []
    assert s.docs["utenti/vincenzo/anteprime/950"]["data"] == "2026-12-11"


async def test_release_day_reminder_once_and_no_second_notification_from_deezer():
    s = store(extra={"utenti/vincenzo/anteprime/950": {
        "artista": "Ava Max", "artista_id": AVA, "titolo": "Nuovo Album", "tipo": "album", "data": "2026-12-04",
        "copertina": "", "link": "", "spotify": "", "avvisata": NOW, "promemoria": None}})
    day = datetime(2026, 12, 4, 9, 17, tzinfo=ROME)
    itunes = FakeItunes(AVA_ITUNES_OLD + [itunes_rel(950, "Nuovo Album", "2026-12-04", "album")])  # not "upcoming" any more
    # The same morning it arrives on Deezer too
    deezer = AVA_DEEZER + [deezer_rel(3, "Nuovo Album (Deluxe)", "2026-12-04", "album")]
    ntfy, lines = await run(s, itunes, deezer, now=day)
    assert [n.title for n in ntfy.sent] == ["Esce oggi: Ava Max"]  # not also "Nuovo album: Ava Max"
    assert "utenti/vincenzo/novita/3" in s.docs  # still in the history
    assert s.docs["utenti/vincenzo/anteprime/950"]["promemoria"] == day
    ntfy, _ = await run(s, itunes, deezer, now=day + timedelta(hours=3))
    assert ntfy.sent == []  # one reminder only


async def test_old_announcements_are_removed():
    s = store(extra={"utenti/vincenzo/anteprime/940": {"artista": "Ava Max", "titolo": "Vecchio", "data": "2026-10-01", "promemoria": NOW}})
    await run(s, FakeItunes(AVA_ITUNES_OLD))
    assert "utenti/vincenzo/anteprime/940" not in s.docs


async def test_only_controllare_and_wanted_kinds():
    coming = AVA_ITUNES_OLD + [itunes_rel(951, "Nuovo Singolo", "2026-11-20")]
    s = store(tipi_avviso=["album"])  # no singles
    ntfy, _ = await run(s, FakeItunes(coming))
    assert ntfy.sent == [] and "utenti/vincenzo/anteprime/951" not in s.docs
    s = store(lista="recuperando")
    itunes = FakeItunes(coming)
    ntfy, _ = await run(s, itunes)
    assert ntfy.sent == [] and itunes.searches == 0  # nobody has it in Controllare: iTunes is not even asked


async def test_no_match_is_retried_after_a_week():
    s = store()
    itunes = FakeItunes([itunes_rel(990, "Nessun titolo in comune", "2019-01-01")])
    await run(s, itunes)
    assert "itunes_id" not in s.docs[f"visti/{AVA}"] and s.docs[f"visti/{AVA}"]["itunes_cercato"] == NOW
    await run(s, itunes, now=NOW + timedelta(days=2))
    assert itunes.searches == 1
    await run(s, itunes, now=NOW + timedelta(days=8))
    assert itunes.searches == 2


async def test_itunes_errors_do_not_stop_the_check():
    s = store()
    ntfy, lines = await run(s, FakeItunes([], broken=True), AVA_DEEZER + [deezer_rel(3, "Singolo Nuovo", "2026-11-12")])
    assert "| Errori di iTunes | 1 |" in lines
    assert [n.title for n in ntfy.sent] == ["Nuovo singolo: Ava Max"]  # Deezer's news still arrives


async def test_more_than_three_announcements_become_one():
    coming = AVA_ITUNES_OLD + [itunes_rel(960 + i, f"Singolo {i}", f"2026-12-0{i + 1}") for i in range(4)]
    ntfy, _ = await run(store(), FakeItunes(coming))
    assert [n.title for n in ntfy.sent] == ["4 uscite in arrivo"]
    assert "Ava Max: Singolo 0 (01/12)" in ntfy.sent[0].message


async def test_report_has_no_titles():
    _, lines = await run(store(), FakeItunes(AVA_ITUNES_OLD + [itunes_rel(950, "Titolo Segreto", "2026-12-04", "album")]))
    assert "Titolo Segreto" not in "\n".join(lines) and "Ava Max" not in "\n".join(lines)
