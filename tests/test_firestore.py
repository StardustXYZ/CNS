"""Firestore REST client with a fake server: value conversion, reads, writes, errors."""

from __future__ import annotations

from datetime import datetime, timezone
import json
from zoneinfo import ZoneInfo

import httpx
import pytest

from app.services.firestore import (
    FirestoreClient,
    FirestoreError,
    decode_fields,
    encode_fields,
    parse_timestamp,
    service_account_info,
)
from tests.conftest import json_transport

BASE = "/v1/projects/demo-cns/databases/(default)/documents"
ROME = ZoneInfo("Europe/Rome")


# ---- Values ----

def test_round_trip_of_every_type():
    data = {
        "nome": "Ava Max", "fan": 1235611, "media": 4.5, "attivo": True, "nota": None,
        "tipi": ["album", "ep"], "segnalibro": {"id": 1104755342, "titolo": "BURN"},
        "aggiunto": datetime(2026, 11, 12, 19, 30, 5, 123456, tzinfo=ROME), "dati": b"\x00\x01",
    }
    back = decode_fields(json.loads(json.dumps(encode_fields(data))))
    assert back == data  # the date comes back in UTC, the same instant
    assert back["aggiunto"].tzinfo == timezone.utc


def test_encoding_details():
    fields = encode_fields({"vero": True, "n": 7, "quando": datetime(2026, 11, 12, 18, 0, tzinfo=timezone.utc)})
    assert fields["vero"] == {"booleanValue": True}  # not an integer
    assert fields["n"] == {"integerValue": "7"}
    assert fields["quando"] == {"timestampValue": "2026-11-12T18:00:00.000000Z"}


def test_dates_without_time_zone_are_refused():
    with pytest.raises(ValueError, match="fuso"):
        encode_fields({"quando": datetime(2026, 11, 12, 18, 0)})


@pytest.mark.parametrize("raw, micro", [("2026-11-12T18:35:07Z", 0), ("2026-11-12T18:35:07.5Z", 500000),
                                        ("2026-11-12T18:35:07.123456789Z", 123456)])
def test_timestamps_from_firestore(raw, micro):
    t = parse_timestamp(raw)
    assert (t.hour, t.second, t.microsecond, t.tzinfo) == (18, 7, micro, timezone.utc)


# ---- Service account key ----

def test_service_account_key_checks():
    with pytest.raises(FirestoreError, match="manca"):
        service_account_info("")
    with pytest.raises(FirestoreError, match="non è il testo"):
        service_account_info("{non json")
    with pytest.raises(FirestoreError, match="non è una chiave"):
        service_account_info('{"type": "authorized_user"}')
    info = service_account_info('{"type": "service_account", "private_key": "x", "project_id": "demo-cns"}')
    assert info["project_id"] == "demo-cns"


# ---- HTTP client ----

def client(routes, log=None, token="token-finto") -> FirestoreClient:
    return FirestoreClient("demo-cns", token, transport=json_transport(routes, log))


async def test_get_existing_and_missing_documents():
    routes = {
        f"{BASE}/stato/github": {"name": "x", "fields": {"origine": {"stringValue": "prova"}}},
        f"{BASE}/artisti/0": httpx.Response(404, json={"error": {"message": "not found"}}),
    }
    log = []
    async with client(routes, log) as db:
        assert await db.get("stato/github") == {"origine": "prova"}
        assert await db.get("artisti/0") is None
    assert log[0].headers["Authorization"] == "Bearer token-finto"


async def test_set_sends_typed_fields():
    log = []
    async with client({f"{BASE}/stato/github": {"name": "x"}}, log) as db:
        await db.set("stato/github", {"origine": "prova", "giro": None})
    assert log[0].method == "PATCH"
    assert json.loads(log[0].content) == {"fields": {"origine": {"stringValue": "prova"}, "giro": {"nullValue": None}}}


async def test_collection_group_lists_documents_of_every_user():
    name = "projects/demo-cns/databases/(default)/documents/utenti/{}/artisti/{}"
    answer = [
        {"document": {"name": name.format("u1", "12948083"), "fields": {"nome": {"stringValue": "Ava Max"}}}, "readTime": "x"},
        {"document": {"name": name.format("u2", "1182"), "fields": {"nome": {"stringValue": "Arctic Monkeys"}}}, "readTime": "x"},
    ]
    log = []
    async with client({f"{BASE}:runQuery": httpx.Response(200, json=answer)}, log) as db:
        found = await db.collection_group("artisti")
    assert found == [("utenti/u1/artisti/12948083", {"nome": "Ava Max"}), ("utenti/u2/artisti/1182", {"nome": "Arctic Monkeys"})]
    assert log[0].method == "POST"
    assert json.loads(log[0].content) == {"structuredQuery": {"from": [{"collectionId": "artisti", "allDescendants": True}]}}


async def test_collection_group_with_no_documents():
    async with client({f"{BASE}:runQuery": httpx.Response(200, json=[{"readTime": "2026-11-13T10:00:00Z"}])}) as db:
        assert await db.collection_group("artisti") == []


async def test_errors_are_explained():
    denied = httpx.Response(403, json={"error": {"code": 403, "message": "Missing or insufficient permissions."}})
    async with client({f"{BASE}/stato/github": denied}) as db:
        with pytest.raises(FirestoreError, match="403: Missing or insufficient permissions"):
            await db.get("stato/github")


async def test_token_is_fetched_once_when_opening():
    calls = []

    def token():
        calls.append(1)
        return "token-dal-service-account"

    log = []
    async with client({f"{BASE}/a/b": {"fields": {}}}, log, token=token) as db:
        await db.get("a/b")
        await db.get("a/b")
    assert calls == [1]
    assert log[1].headers["Authorization"] == "Bearer token-dal-service-account"


async def test_sign_in_failure_is_explained():
    def token():
        raise RuntimeError("invalid_grant: Invalid JWT Signature")

    with pytest.raises(FirestoreError, match="accesso con l'account di servizio non riuscito"):
        async with client({}, token=token):
            pass
