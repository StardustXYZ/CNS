"""Scheduled check with fake Firestore, Deezer and ntfy: new releases, silent first run,
versions that are not news, notifications per person, report without names."""

from __future__ import annotations

from datetime import date, datetime
from zoneinfo import ZoneInfo

import pytest

from app.controllo import MAX_ATTEMPTS, find_new, group_artists, run_check
from app.prova_firebase import STATUS_PATH
from app.services.deezer import DeezerError, DeezerRelease
from app.services.firestore import FirestoreError

ROME = ZoneInfo("Europe/Rome")
NOW = datetime(2026, 11, 13, 15, 17, tzinfo=ROME)
AVA, GAGA, AMY = "12948083", "75491", "15741"


def rel(id_, title, day, kind="single"):
    return DeezerRelease(id=id_, title=title, record_type=kind, release_date=date.fromisoformat(day) if day else None,
                         cover=f"https://cdn/{id_}.jpg", link=f"https://www.deezer.com/album/{id_}")


AVA_OLD = [rel(1, "Sweet but Psycho", "2018-08-17"), rel(2, "Heaven & Hell", "2020-09-18", "album")]
GAGA_OLD = [rel(10, "MAYHEM", "2025-03-07", "album")]


class FakeStore:
    def __init__(self, artists, docs=None):
        self.artists = artists
        self.docs = dict(docs or {})

    async def collection_group(self, collection_id):
        return self.artists

    async def get(self, path):
        return self.docs.get(path)

    async def set(self, path, data):
        self.docs[path] = data


class FakeDeezer:
    def __init__(self, discographies, broken=()):
        self.discographies, self.broken, self.calls = discographies, set(broken), []

    async def artist_releases(self, artist_id):
        self.calls.append(str(artist_id))
        if str(artist_id) in self.broken:
            raise DeezerError("Deezer non risponde")
        return self.discographies[str(artist_id)]


class FakeNtfy:
    def __init__(self, fail=False, fail_topics=()):
        self.sent, self.fail, self.fail_topics = [], fail, set(fail_topics)

    def __call__(self, topic):
        outer = self

        class Sender:
            async def send(self, notification):
                if outer.fail or topic in outer.fail_topics:
                    raise RuntimeError("ntfy giù")
                outer.sent.append((topic, notification))

        return Sender()


def artists(*rows):
    return [(f"utenti/{uid}/artisti/{aid}", {"nome": name, "lista": lista, **extra}) for uid, aid, name, lista, extra in rows]


def seen_from(artist_id, name, releases):
    from app.controllo import FollowedArtist, seen_state
    return seen_state(FollowedArtist(artist_id, name), releases, NOW)


def store_with_history(rows, extra_docs=None):
    docs = {
        f"visti/{AVA}": seen_from(AVA, "Ava Max", AVA_OLD),
        f"visti/{GAGA}": seen_from(GAGA, "Lady Gaga", GAGA_OLD),
        "utenti/vincenzo": {"ntfy": "argomento-di-vincenzo"},
        "utenti/amica": {"ntfy": "argomento-dell-amica"},
        **(extra_docs or {}),
    }
    return FakeStore(artists(*rows), docs)


async def test_first_run_is_silent_and_remembers_everything():
    store = FakeStore(artists(("vincenzo", AVA, "Ava Max", "controllare", {})), {"utenti/vincenzo": {"ntfy": "t"}})
    ntfy = FakeNtfy()
    await run_check(store, FakeDeezer({AVA: AVA_OLD}), NOW, ntfy)
    assert ntfy.sent == []
    assert store.docs[f"visti/{AVA}"]["ids"] == ["1", "2"]
    assert "single|sweet but psycho" in store.docs[f"visti/{AVA}"]["chiavi"]
    assert not any(p.startswith("utenti/vincenzo/novita/") for p in store.docs)


async def test_new_release_goes_to_novita_and_to_the_right_topic():
    store = store_with_history([("vincenzo", AVA, "Ava Max", "controllare", {})])
    ntfy = FakeNtfy()
    new = rel(3, "Christmas Wonderland", "2026-11-06")
    await run_check(store, FakeDeezer({AVA: AVA_OLD + [new]}), NOW, ntfy)
    assert [(topic, n.title) for topic, n in ntfy.sent] == [("argomento-di-vincenzo", "Nuovo singolo: Ava Max")]
    doc = store.docs["utenti/vincenzo/novita/3"]
    assert doc["titolo"] == "Christmas Wonderland" and doc["tipo"] == "single" and doc["data"] == "2026-11-06"
    assert doc["spotify"].startswith("https://open.spotify.com/search/")
    assert "3" in store.docs[f"visti/{AVA}"]["ids"]
    assert dict(ntfy.sent[0][1].actions)["Apri l'app"].endswith("/#/novita")


async def test_new_versions_and_old_catalogue_are_not_news():
    store = store_with_history([("vincenzo", AVA, "Ava Max", "controllare", {})])
    ntfy = FakeNtfy()
    remix = rel(4, "Sweet but Psycho (Nuovo Remix)", "2026-11-10")
    deluxe = rel(5, "Heaven & Hell (Deluxe)", "2026-11-12", "album")
    old_added_late = rel(6, "Una canzone del 2019", "2019-05-01")
    await run_check(store, FakeDeezer({AVA: AVA_OLD + [remix, deluxe, old_added_late]}), NOW, ntfy)
    assert ntfy.sent == []
    assert {"4", "5", "6"} <= set(store.docs[f"visti/{AVA}"]["ids"])  # remembered, so never announced later


async def test_two_versions_out_together_are_one_release():
    seen = {"ids": [], "chiavi": []}
    news = find_new(group_artists(artists(("v", AVA, "Ava Max", "controllare", {})))[AVA],
                    [rel(7, "FATE (Explicit)", "2026-11-12"), rel(8, "FATE", "2026-11-12")], seen, NOW.date())
    assert len(news) == 1


async def test_only_controllare_and_only_wanted_kinds_are_notified():
    store = store_with_history([
        ("vincenzo", AVA, "Ava Max", "controllare", {"tipi_avviso": ["album"]}),  # no singles
        ("amica", AVA, "Ava Max", "recuperando", {}),  # catching up: goes to the end of her queue, no notification
    ])
    ntfy = FakeNtfy()
    await run_check(store, FakeDeezer({AVA: AVA_OLD + [rel(3, "Christmas Wonderland", "2026-11-06")]}), NOW, ntfy)
    assert ntfy.sent == []
    assert "utenti/vincenzo/novita/3" not in store.docs and "utenti/amica/novita/3" not in store.docs


async def test_two_people_following_the_same_artist_ask_deezer_once():
    store = store_with_history([
        ("vincenzo", AVA, "Ava Max", "controllare", {}),
        ("amica", AVA, "Ava Max", "controllare", {}),
    ])
    deezer, ntfy = FakeDeezer({AVA: AVA_OLD + [rel(3, "Christmas Wonderland", "2026-11-06")]}), FakeNtfy()
    await run_check(store, deezer, NOW, ntfy)
    assert deezer.calls == [AVA]
    assert sorted(topic for topic, _ in ntfy.sent) == ["argomento-dell-amica", "argomento-di-vincenzo"]


async def test_more_than_three_become_one_notification():
    store = store_with_history([("vincenzo", AVA, "Ava Max", "controllare", {}), ("vincenzo", GAGA, "Lady Gaga", "controllare", {})])
    ntfy = FakeNtfy()
    ava_new = [rel(20 + i, f"Singolo {i}", "2026-11-1" + str(i)) for i in range(3)]
    gaga_new = [rel(30, "Nuovo album", "2026-11-13", "album")]
    await run_check(store, FakeDeezer({AVA: AVA_OLD + ava_new, GAGA: GAGA_OLD + gaga_new}), NOW, ntfy)
    assert len(ntfy.sent) == 1
    summary = ntfy.sent[0][1]
    assert summary.title.startswith("4 uscite nuove: Ava Max, Lady Gaga")
    assert summary.click.endswith("/#/novita")
    assert sum(p.startswith("utenti/vincenzo/novita/") for p in store.docs) == 4


async def test_without_a_topic_the_news_waits_in_novita():
    store = store_with_history([("vincenzo", AVA, "Ava Max", "controllare", {})], {"utenti/vincenzo": {}})
    ntfy = FakeNtfy()
    lines = await run_check(store, FakeDeezer({AVA: AVA_OLD + [rel(3, "Christmas Wonderland", "2026-11-06")]}), NOW, ntfy)
    assert ntfy.sent == [] and "utenti/vincenzo/novita/3" in store.docs
    assert "| Persone senza notifiche (solo in Novità) | 1 |" in lines  # no ntfy topic and no phone


async def test_deezer_or_ntfy_errors_do_not_stop_the_run():
    store = store_with_history([("vincenzo", AVA, "Ava Max", "controllare", {}), ("vincenzo", GAGA, "Lady Gaga", "controllare", {})])
    deezer = FakeDeezer({AVA: AVA_OLD + [rel(3, "Christmas Wonderland", "2026-11-06")]}, broken=[GAGA])
    lines = await run_check(store, deezer, NOW, FakeNtfy(fail=True))
    assert "| Artisti non letti (errore di Deezer) | 1 |" in lines
    assert "| Notifiche non riuscite | 1 |" in lines
    assert "utenti/vincenzo/novita/3" in store.docs
    assert f"visti/{GAGA}" in store.docs and store.docs[f"visti/{GAGA}"]["ids"] == ["10"]  # untouched


async def test_archived_artists_are_not_asked_to_deezer():
    store = store_with_history([("vincenzo", AMY, "Amy Lee", "archivio", {})])
    deezer = FakeDeezer({})
    await run_check(store, deezer, NOW, FakeNtfy())
    assert deezer.calls == []


async def test_status_and_report_have_numbers_but_no_names_codes_or_topics():
    store = store_with_history([("vincenzo", AVA, "Ava Max", "controllare", {})])
    lines = await run_check(store, FakeDeezer({AVA: AVA_OLD + [rel(3, "Christmas Wonderland", "2026-11-06")]}), NOW, FakeNtfy())
    status = store.docs[STATUS_PATH]
    assert status["ultimo_contatto"] == NOW and status["uscite_nuove"] == 1 and status["artisti"] == 1
    report = "\n".join(lines)
    assert "| Uscite nuove | 1 |" in report and "| Notifiche inviate | 1 |" in report
    for secret in ["Ava Max", "Christmas", "vincenzo", "argomento-di-vincenzo", AVA]:
        assert secret not in report


async def test_people_removed_from_the_allow_list_get_nothing():
    allow = {"admin": "vincenzo", "email": ["Amica@Example.com"]}
    store = store_with_history(
        [("vincenzo", AVA, "Ava Max", "controllare", {}), ("amica", AVA, "Ava Max", "controllare", {}),
         ("ex", AVA, "Ava Max", "controllare", {})],
        {"config/ammessi": allow,
         "utenti/amica": {"ntfy": "argomento-dell-amica", "email": "amica@example.com"},
         "utenti/ex": {"ntfy": "argomento-dell-ex", "email": "ex@example.com"}},
    )
    ntfy = FakeNtfy()
    lines = await run_check(store, FakeDeezer({AVA: AVA_OLD + [rel(3, "Christmas Wonderland", "2026-11-06")]}), NOW, ntfy)
    assert sorted(topic for topic, _ in ntfy.sent) == ["argomento-dell-amica", "argomento-di-vincenzo"]
    assert "utenti/ex/novita/3" not in store.docs
    assert "| Persone non più ammesse (saltate) | 1 |" in lines


# ---- A failure must not lose news: "seen" is written only once the people are told ----

class FlakyStore(FakeStore):
    """A store that fails once when a given document is read (Firestore had a bad moment)."""

    def __init__(self, *args, fail_get=()):
        super().__init__(*args)
        self.fail_get = set(fail_get)

    async def get(self, path):
        if path in self.fail_get:
            self.fail_get.discard(path)
            raise FirestoreError("Firestore ha risposto con HTTP 503: giù")
        return await super().get(path)


AVA_NEW = rel(3, "Christmas Wonderland", "2026-11-06")


async def test_a_firestore_failure_midway_loses_no_news():
    rows = [("vincenzo", AVA, "Ava Max", "controllare", {}), ("vincenzo", GAGA, "Lady Gaga", "controllare", {})]
    base = store_with_history(rows)
    store = FlakyStore(base.artists, base.docs, fail_get=[f"visti/{GAGA}"])  # Ava is done before Gaga fails
    deezer = FakeDeezer({AVA: AVA_OLD + [AVA_NEW], GAGA: GAGA_OLD})
    ntfy = FakeNtfy()
    with pytest.raises(FirestoreError):
        await run_check(store, deezer, NOW, ntfy)
    assert "3" not in store.docs[f"visti/{AVA}"]["ids"]  # not "seen" yet: nobody was told
    await run_check(store, deezer, NOW, ntfy)  # the next run
    assert [n.title for _, n in ntfy.sent] == ["Nuovo singolo: Ava Max"]
    assert "utenti/vincenzo/novita/3" in store.docs
    assert "3" in store.docs[f"visti/{AVA}"]["ids"]


async def test_a_failed_notification_is_tried_again_only_for_the_person_it_failed_for():
    store = store_with_history([("vincenzo", AVA, "Ava Max", "controllare", {}), ("amica", AVA, "Ava Max", "controllare", {})])
    deezer = FakeDeezer({AVA: AVA_OLD + [AVA_NEW]})
    first = FakeNtfy(fail_topics=["argomento-dell-amica"])
    lines = await run_check(store, deezer, NOW, first)
    assert [t for t, _ in first.sent] == ["argomento-di-vincenzo"]
    assert "3" not in store.docs[f"visti/{AVA}"]["ids"]  # to be checked again
    assert store.docs["utenti/amica/novita/3"]["da_riprovare"] is True  # she can read it in the app meanwhile
    assert "da_riprovare" not in store.docs["utenti/vincenzo/novita/3"]
    assert "| Artisti da ricontrollare (notifica non riuscita) | 1 |" in lines

    second = FakeNtfy()
    await run_check(store, deezer, NOW, second)
    assert [t for t, _ in second.sent] == ["argomento-dell-amica"]  # vincenzo is not told twice
    assert "da_riprovare" not in store.docs["utenti/amica/novita/3"]
    assert "3" in store.docs[f"visti/{AVA}"]["ids"]

    third = FakeNtfy()
    await run_check(store, deezer, NOW, third)
    assert third.sent == []  # nothing left to do


async def test_a_retry_keeps_the_original_time_of_the_news():
    store = store_with_history([("vincenzo", AVA, "Ava Max", "controllare", {})])
    deezer = FakeDeezer({AVA: AVA_OLD + [AVA_NEW]})
    await run_check(store, deezer, NOW, FakeNtfy(fail=True))
    later = datetime(2026, 11, 13, 18, 17, tzinfo=ROME)
    await run_check(store, deezer, later, FakeNtfy())
    assert store.docs["utenti/vincenzo/novita/3"]["notificata"] == NOW


async def test_it_gives_up_retrying_after_a_few_runs():
    store = store_with_history([("vincenzo", AVA, "Ava Max", "controllare", {})])
    deezer = FakeDeezer({AVA: AVA_OLD + [AVA_NEW]})
    for run in range(MAX_ATTEMPTS):
        assert "3" not in store.docs[f"visti/{AVA}"]["ids"], f"run {run}"
        await run_check(store, deezer, NOW, FakeNtfy(fail=True))
    assert "3" in store.docs[f"visti/{AVA}"]["ids"]  # no more tries: the news stays in Novità
    assert "da_riprovare" not in store.docs["utenti/vincenzo/novita/3"]
    again = FakeNtfy()
    await run_check(store, deezer, NOW, again)
    assert again.sent == []


async def test_a_release_deezer_leaves_out_for_a_run_is_not_news_when_it_comes_back():
    store = store_with_history([("vincenzo", AVA, "Ava Max", "controllare", {})])
    ntfy = FakeNtfy()
    await run_check(store, FakeDeezer({AVA: AVA_OLD + [AVA_NEW]}), NOW, ntfy)
    assert len(ntfy.sent) == 1
    await run_check(store, FakeDeezer({AVA: AVA_OLD}), NOW, ntfy)  # Deezer's catalogue misses it for a moment
    assert {"3"} <= set(store.docs[f"visti/{AVA}"]["ids"])  # still remembered
    await run_check(store, FakeDeezer({AVA: AVA_OLD + [AVA_NEW]}), NOW, ntfy)
    assert len(ntfy.sent) == 1  # and not announced a second time


async def test_seen_releases_only_grow():
    from app.controllo import FollowedArtist, seen_state
    artist = FollowedArtist(AVA, "Ava Max")
    before = seen_state(artist, AVA_OLD + [AVA_NEW], NOW)
    after = seen_state(artist, AVA_OLD, NOW, before)
    assert after["ids"] == before["ids"] and after["chiavi"] == before["chiavi"]
    assert seen_state(artist, AVA_OLD, NOW, None)["ids"] == ["1", "2"]  # first time: only what is there
