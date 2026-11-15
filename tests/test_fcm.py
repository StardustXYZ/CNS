"""Notifications of the Android app (Firebase Cloud Messaging), with a fake FCM."""

from __future__ import annotations

import asyncio
from datetime import date, datetime
import json
from zoneinfo import ZoneInfo

import httpx
import pytest

from app import controllo
from app.controllo import Report, UserNews, phones_by_user, run_check, tell_user
from app.prova_notifiche import check_api, send_test
from app.services.deezer import DeezerRelease
from app.services.fcm import CHANNEL_DEFAULT, CHANNEL_QUIET, FcmClient, PushError, fcm_message
from app.services.ntfy import PRIORITY_QUIET, Notification

ROME = ZoneInfo("Europe/Rome")
DAY = datetime(2026, 11, 15, 16, 0, tzinfo=ROME)
NIGHT = datetime(2026, 11, 15, 23, 30, tzinfo=ROME)


def run(coro):
    return asyncio.run(coro)


def fcm_answer(handler):
    """An FcmClient whose answers come from ``handler(request) -> httpx.Response``."""
    return FcmClient("cns-chi-ni-sindimu", "token-di-accesso", transport=httpx.MockTransport(handler))


def error(status, http_status, code=None):
    details = [{"@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", "errorCode": code}] if code else []
    return httpx.Response(http_status, json={"error": {"code": http_status, "status": status, "details": details}})


class FakeStore:
    def __init__(self, groups=None, docs=None):
        self.groups = groups or {}
        self.docs = dict(docs or {})
        self.deleted = []

    async def collection_group(self, collection_id):
        return self.groups.get(collection_id, [])

    async def get(self, path):
        return self.docs.get(path)

    async def set(self, path, data):
        self.docs[path] = data

    async def delete(self, path):
        self.deleted.append(path)
        self.docs.pop(path, None)


class FakePush:
    def __init__(self, gone=(), broken=()):
        self.sent, self.gone, self.broken = [], set(gone), set(broken)

    async def send(self, token, notification):
        if token in self.broken:
            raise PushError("FCM ha risposto con HTTP 500")
        if token in self.gone:
            return False
        self.sent.append((token, notification.title))
        return True


class FakeNtfy:
    def __init__(self):
        self.sent = []

    def __call__(self, topic):
        outer = self

        class Sender:
            async def send(self, notification):
                outer.sent.append((topic, notification.title))

        return Sender()


def release(id_, title, day="2026-11-14", kind="single"):
    return DeezerRelease(id=id_, title=title, record_type=kind, release_date=date.fromisoformat(day),
                         cover=f"https://cdn/{id_}.jpg", link=f"https://www.deezer.com/album/{id_}")


# ------------------------------------------------------------------ the message

def test_il_messaggio_ha_titolo_testo_copertina_e_apre_le_novita():
    body = fcm_message("tok", Notification(title="Nuovo singolo: Ava Max", message="Prova\nUscito il 14/11/2026",
                                           icon="https://cdn/1.jpg"))["message"]
    assert body["token"] == "tok"
    assert body["notification"] == {"title": "Nuovo singolo: Ava Max", "body": "Prova\nUscito il 14/11/2026",
                                    "image": "https://cdn/1.jpg"}
    assert body["data"] == {"link": "cns://novita"}
    assert body["android"]["notification"]["channel_id"] == CHANNEL_DEFAULT


def test_di_notte_va_sul_canale_senza_suono():
    body = fcm_message("tok", Notification(title="T", message="M", priority=PRIORITY_QUIET))["message"]
    assert body["android"]["notification"]["channel_id"] == CHANNEL_QUIET
    assert "image" not in body["notification"]


# ------------------------------------------------------------------ FCM's answers

def test_inviata():
    seen = []

    def handler(request):
        seen.append((request.url.path, request.headers["Authorization"], json.loads(request.content)))
        return httpx.Response(200, json={"name": "projects/x/messages/1"})

    async def go():
        async with fcm_answer(handler) as fcm:
            return await fcm.send("tok", Notification(title="T", message="M"))

    assert run(go()) is True
    path, auth, body = seen[0]
    assert path == "/v1/projects/cns-chi-ni-sindimu/messages:send"
    assert auth == "Bearer token-di-accesso"
    assert body["message"]["token"] == "tok"


def test_telefono_sparito_e_errore_vero():
    async def go(answer):
        async with fcm_answer(lambda request: answer) as fcm:
            return await fcm.send("tok", Notification(title="T", message="M"))

    assert run(go(error("NOT_FOUND", 404, "UNREGISTERED"))) is False
    with pytest.raises(PushError, match="HTTP 403"):
        run(go(error("PERMISSION_DENIED", 403)))
    with pytest.raises(PushError, match="INVALID_ARGUMENT"):
        run(go(error("INVALID_ARGUMENT", 400, "INVALID_ARGUMENT")))


def test_la_prova_riconosce_api_attiva_o_spenta():
    async def go(answer):
        async with fcm_answer(lambda request: answer) as fcm:
            return await check_api(fcm)

    assert run(go(error("INVALID_ARGUMENT", 400, "INVALID_ARGUMENT"))) == "ok"
    assert "HTTP 403" in run(go(error("PERMISSION_DENIED", 403)))


# ------------------------------------------------------------------ who gets what

def test_i_telefoni_di_ogni_persona():
    found = phones_by_user([
        ("utenti/a/telefoni/p1", {"token": "t1"}),
        ("utenti/a/telefoni/p2", {"token": "t2"}),
        ("utenti/b/telefoni/p3", {"token": ""}),
        ("altro/x/telefoni/p4", {"token": "t4"}),
    ])
    assert found == {"a": [("utenti/a/telefoni/p1", "t1"), ("utenti/a/telefoni/p2", "t2")]}


def test_notifiche_a_ntfy_e_ai_telefoni_e_il_telefono_sparito_va_tolto():
    db = FakeStore(docs={"utenti/a": {"ntfy": "argomento-a"}, "utenti/a/telefoni/p2": {"token": "vecchio"}})
    news = UserNews(releases=[controllo.NewRelease(controllo.FollowedArtist("1", "Ava Max", {}), release(9, "Prova"), "single")])
    ntfy, push, report = FakeNtfy(), FakePush(gone={"vecchio"}), Report()
    phones = [("utenti/a/telefoni/p1", "nuovo"), ("utenti/a/telefoni/p2", "vecchio")]
    run(tell_user(db, "a", news, DAY, ntfy, report, None, phones, push))
    assert ntfy.sent == [("argomento-a", "Nuovo singolo: Ava Max")]
    assert push.sent == [("nuovo", "Nuovo singolo: Ava Max")]
    assert db.deleted == ["utenti/a/telefoni/p2"]
    assert (report.notifications, report.push_sent, report.phones_removed, report.no_topic) == (1, 1, 1, 0)


def test_senza_argomento_ntfy_basta_il_telefono():
    db = FakeStore(docs={"utenti/a": {}})
    news = UserNews(releases=[controllo.NewRelease(controllo.FollowedArtist("1", "Ava Max", {}), release(9, "Prova"), "single")])
    push, report = FakePush(broken={"rotto"}), Report()
    run(tell_user(db, "a", news, NIGHT, FakeNtfy(), report, None,
                  [("utenti/a/telefoni/p1", "tok"), ("utenti/a/telefoni/p2", "rotto")], push))
    assert push.sent == [("tok", "Nuovo singolo: Ava Max")]
    assert (report.no_topic, report.push_sent, report.push_errors) == (0, 1, 1)


def test_senza_ntfy_e_senza_telefoni_resta_solo_in_novita():
    db = FakeStore(docs={"utenti/a": {}})
    news = UserNews(releases=[controllo.NewRelease(controllo.FollowedArtist("1", "Ava Max", {}), release(9, "Prova"), "single")])
    report = Report()
    run(tell_user(db, "a", news, DAY, FakeNtfy(), report, None, [], FakePush()))
    assert report.no_topic == 1
    assert "utenti/a/novita/9" in db.docs


def test_il_giro_completo_manda_anche_ai_telefoni():
    class Deezer:
        async def artist_releases(self, artist_id):
            return [release(1, "Vecchia", "2020-01-01"), release(2, "Nuova", "2026-11-14")]

    db = FakeStore(
        groups={
            "artisti": [("utenti/a/artisti/1", {"nome": "Ava Max", "lista": "controllare"})],
            "telefoni": [("utenti/a/telefoni/p1", {"token": "tok"})],
        },
        docs={"visti/1": {"ids": ["1"], "chiavi": ["single|vecchia"]}, "utenti/a": {}},
    )
    push = FakePush()
    lines = run(run_check(db, Deezer(), DAY, FakeNtfy(), None, push))
    assert push.sent == [("tok", "Nuovo singolo: Ava Max")]
    assert "| Telefoni con l'app Android | 1 |" in lines
    assert "| Notifiche inviate all'app | 1 |" in lines


def test_la_prova_manda_solo_ai_telefoni_dell_amministratore():
    db = FakeStore(
        groups={"telefoni": [
            ("utenti/capo/telefoni/p1", {"token": "mio"}),
            ("utenti/capo/telefoni/p2", {"token": "sparito"}),
            ("utenti/amico/telefoni/p3", {"token": "suo"}),
        ]},
        docs={"config/ammessi": {"admin": "capo", "email": []}},
    )
    push = FakePush(gone={"sparito"})
    assert run(send_test(db, push, DAY)) == (2, 1, 1)
    assert [t for t, _ in push.sent] == ["mio"]
    assert db.deleted == ["utenti/capo/telefoni/p2"]
