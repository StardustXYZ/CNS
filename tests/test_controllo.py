"""Scheduled check with a fake Firestore: grouping by artist, recorded run, no names in the report."""

from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from app.controllo import group_artists, run_check
from app.prova_firebase import STATUS_PATH

NOW = datetime(2026, 11, 13, 9, 17, tzinfo=ZoneInfo("Europe/Rome"))

DOCS = [
    ("utenti/vincenzo/artisti/12948083", {"nome": "Ava Max", "lista": "controllare"}),
    ("utenti/vincenzo/artisti/15741", {"nome": "Amy Lee", "lista": "recuperando"}),
    ("utenti/vincenzo/artisti/1182", {"nome": "Arctic Monkeys", "lista": "archivio"}),
    ("utenti/amica/artisti/12948083", {"nome": "Ava Max", "lista": "recuperando"}),
    ("utenti/amica/artisti/75491", {"nome": "Lady Gaga", "lista": "controllare"}),
    ("altro/x/artisti/1", {"nome": "Non nostro", "lista": "controllare"}),
    ("utenti/vincenzo/artisti/non-numerico", {"nome": "Rotto", "lista": "controllare"}),
]


class FakeStore:
    def __init__(self, docs):
        self.docs, self.written = docs, {}

    async def get(self, path):
        return self.written.get(path)

    async def set(self, path, data):
        self.written[path] = data

    async def collection_group(self, collection_id):
        assert collection_id == "artisti"
        return self.docs


def test_artists_are_grouped_once_per_deezer_artist():
    artists = group_artists(DOCS)
    assert set(artists) == {"12948083", "15741", "1182", "75491"}
    assert artists["12948083"].followers == {"vincenzo": "controllare", "amica": "recuperando"}
    assert artists["12948083"].to_check
    assert not artists["1182"].to_check  # only in someone's archive


async def test_run_is_recorded_for_the_app():
    store = FakeStore(DOCS)
    await run_check(store, NOW)
    status = store.written[STATUS_PATH]
    assert status["ultimo_contatto"] == NOW
    assert status["origine"] == "controllo"
    assert status["utenti"] == 2
    assert status["artisti"] == 3  # Ava Max, Amy Lee, Lady Gaga (not the archived Arctic Monkeys)


async def test_report_has_numbers_but_no_names_or_user_codes():
    report = "\n".join(await run_check(FakeStore(DOCS), NOW))
    assert "| Artisti diversi da chiedere a Deezer | 3 |" in report
    assert "| …di cui seguiti da più persone | 1 |" in report
    assert "| Artisti in Controllare (per utente) | 2 |" in report
    for secret in ["Ava Max", "Amy Lee", "Lady Gaga", "Arctic Monkeys", "vincenzo", "amica", "12948083"]:
        assert secret not in report


async def test_no_artists_yet():
    store = FakeStore([])
    lines = await run_check(store, NOW)
    assert store.written[STATUS_PATH]["artisti"] == 0
    assert "| Utenti con almeno un artista | 0 |" in lines
