"""Firebase feasibility test with a fake Firestore."""

from __future__ import annotations

from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import pytest

from app.prova_firebase import STATUS_PATH, check, run_url
from app.services.firestore import FirestoreError

NOW = datetime(2026, 11, 12, 19, 40, tzinfo=ZoneInfo("Europe/Rome"))


class FakeStore:
    def __init__(self, docs=None, broken=False):
        self.docs = dict(docs or {})
        self.broken = broken

    async def get(self, path):
        return self.docs.get(path)

    async def set(self, path, data):
        if not self.broken:
            self.docs[path] = {k: (v.astimezone(timezone.utc) if isinstance(v, datetime) else v) for k, v in data.items()}


async def test_first_contact():
    store = FakeStore()
    lines = await check(store, NOW)
    assert store.docs[STATUS_PATH]["origine"] == "prova"
    assert "19:40:00 del 12/11/2026" in lines[0]
    assert "Primo contatto" in lines[1]


async def test_previous_contact_is_reported_in_italian_time():
    store = FakeStore({STATUS_PATH: {"ultimo_contatto": datetime(2026, 11, 11, 23, 15, tzinfo=timezone.utc)}})
    lines = await check(store, NOW)
    assert lines[1] == "Il contatto precedente era del 12/11/2026 alle 00:15."


async def test_write_that_does_not_stick_is_an_error():
    with pytest.raises(FirestoreError, match="riletto"):
        await check(FakeStore(broken=True), NOW)


def test_run_url(monkeypatch):
    monkeypatch.delenv("GITHUB_RUN_ID", raising=False)
    assert run_url() is None
    monkeypatch.setenv("GITHUB_SERVER_URL", "https://github.com")
    monkeypatch.setenv("GITHUB_REPOSITORY", "StardustXYZ/CNS")
    monkeypatch.setenv("GITHUB_RUN_ID", "42")
    assert run_url() == "https://github.com/StardustXYZ/CNS/actions/runs/42"
