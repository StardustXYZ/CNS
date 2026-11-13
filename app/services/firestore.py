"""Firestore from GitHub: a thin async client for the REST API, signed in with the service account.

The service account does not go through the security rules (they only let the owner's
Google account in from the app), so GitHub can read the lists and write what it finds.
Values are converted between Python and Firestore's typed JSON ("stringValue", …).
"""

from __future__ import annotations

import asyncio
import base64
from datetime import datetime, timezone
import json
import re
from typing import Any, Callable, Protocol

import httpx

from app.config import settings

FIRESTORE_URL = "https://firestore.googleapis.com/v1"
SCOPES = ["https://www.googleapis.com/auth/datastore"]


class FirestoreError(Exception):
    """Firestore refused the request (the message is in Italian, shown in the report)."""


# ------------------------------------------------------------------ value conversion

def encode_value(value: Any) -> dict:
    """A Python value as a Firestore REST value."""
    if value is None:
        return {"nullValue": None}
    if isinstance(value, bool):  # before int: True is an int in Python
        return {"booleanValue": value}
    if isinstance(value, int):
        return {"integerValue": str(value)}
    if isinstance(value, float):
        return {"doubleValue": value}
    if isinstance(value, str):
        return {"stringValue": value}
    if isinstance(value, bytes):
        return {"bytesValue": base64.b64encode(value).decode("ascii")}
    if isinstance(value, datetime):
        if value.tzinfo is None:
            raise ValueError("data senza fuso orario: usa datetime con tzinfo")
        utc = value.astimezone(timezone.utc)
        return {"timestampValue": utc.strftime("%Y-%m-%dT%H:%M:%S.") + f"{utc.microsecond:06d}Z"}
    if isinstance(value, (list, tuple)):
        return {"arrayValue": {"values": [encode_value(v) for v in value]}}
    if isinstance(value, dict):
        return {"mapValue": {"fields": encode_fields(value)}}
    raise TypeError(f"tipo non supportato da Firestore: {type(value).__name__}")


def encode_fields(data: dict) -> dict:
    return {str(k): encode_value(v) for k, v in data.items()}


def decode_value(value: dict) -> Any:
    """A Firestore REST value as a Python value."""
    (kind, raw), = value.items()
    if kind == "nullValue":
        return None
    if kind == "booleanValue":
        return bool(raw)
    if kind == "integerValue":
        return int(raw)
    if kind == "doubleValue":
        return float(raw)
    if kind in ("stringValue", "referenceValue"):
        return raw
    if kind == "bytesValue":
        return base64.b64decode(raw)
    if kind == "timestampValue":
        return parse_timestamp(raw)
    if kind == "arrayValue":
        return [decode_value(v) for v in raw.get("values", [])]
    if kind == "mapValue":
        return decode_fields(raw.get("fields", {}))
    if kind == "geoPointValue":
        return (raw.get("latitude", 0.0), raw.get("longitude", 0.0))
    raise ValueError(f"valore di Firestore sconosciuto: {kind}")


def parse_timestamp(raw: str) -> datetime:
    """Firestore's "2026-11-12T18:35:07.123456789Z" (up to nanoseconds) as a UTC datetime."""
    match = re.fullmatch(r"(.+?)(?:\.(\d+))?Z", raw)
    if not match:
        raise ValueError(f"data di Firestore non valida: {raw}")
    base, fraction = match.groups()
    micro = int((fraction or "0")[:6].ljust(6, "0"))
    return datetime.fromisoformat(base).replace(microsecond=micro, tzinfo=timezone.utc)


def decode_fields(fields: dict) -> dict:
    return {k: decode_value(v) for k, v in fields.items()}


# ------------------------------------------------------------------ sign-in

def service_account_info(raw: str | None = None) -> dict:
    """The service account key from the FIREBASE_SERVICE_ACCOUNT secret (the JSON file's text)."""
    raw = settings.FIREBASE_SERVICE_ACCOUNT if raw is None else raw
    if not raw:
        raise FirestoreError("manca il segreto FIREBASE_SERVICE_ACCOUNT")
    try:
        info = json.loads(raw)
    except json.JSONDecodeError as err:
        raise FirestoreError("FIREBASE_SERVICE_ACCOUNT non è il testo del file .json di Firebase") from err
    if info.get("type") != "service_account" or "private_key" not in info:
        raise FirestoreError("FIREBASE_SERVICE_ACCOUNT non è una chiave di account di servizio")
    return info


def service_account_token(info: dict) -> str:
    """An access token for Firestore, signed with the service account key (valid one hour)."""
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    credentials = service_account.Credentials.from_service_account_info(info, scopes=SCOPES)
    credentials.refresh(Request())
    return credentials.token


# ------------------------------------------------------------------ client

class DocumentStore(Protocol):
    """Anything that can read and write documents (the real client or a test fake)."""

    async def get(self, path: str) -> dict | None: ...

    async def set(self, path: str, data: dict) -> None: ...

    async def collection_group(self, collection_id: str) -> list[tuple[str, dict]]: ...

    async def delete(self, path: str) -> None: ...


class FirestoreClient:
    """Async Firestore client. Use as ``async with FirestoreClient.from_settings() as db: ...``.

    ``path`` is the document path, e.g. ``"stato/github"`` or ``"artisti/12948083"``.
    """

    def __init__(
        self,
        project_id: str,
        token: str | Callable[[], str],
        timeout: float = 15.0,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self.project_id = project_id
        self._token = token
        self._root = f"projects/{project_id}/databases/(default)/documents"
        self._client = httpx.AsyncClient(
            base_url=f"{FIRESTORE_URL}/projects/{project_id}/databases/(default)/documents/",
            timeout=timeout,
            transport=transport,
        )

    @classmethod
    def from_settings(cls, **kwargs) -> FirestoreClient:
        info = service_account_info()
        project = info.get("project_id") or settings.FIREBASE_PROJECT_ID
        return cls(project, lambda: service_account_token(info), **kwargs)

    async def __aenter__(self) -> FirestoreClient:
        if callable(self._token):  # signing in makes a network call: done once, off the event loop
            try:
                self._token = await asyncio.to_thread(self._token)
            except Exception as err:  # google-auth raises its own errors
                raise FirestoreError(f"accesso con l'account di servizio non riuscito: {err}") from err
        return self

    async def __aexit__(self, *exc) -> None:
        await self._client.aclose()

    def _headers(self) -> dict:
        if callable(self._token):
            raise FirestoreError("usa il client con 'async with'")
        return {"Authorization": f"Bearer {self._token}"}

    async def _request(self, method: str, path: str, **kwargs) -> httpx.Response:
        try:
            resp = await self._client.request(method, path.strip("/"), headers=self._headers(), **kwargs)
        except httpx.HTTPError as err:
            raise FirestoreError(f"Firestore non risponde ({type(err).__name__})") from err
        if resp.status_code >= 400 and resp.status_code != 404:
            try:
                message = resp.json()["error"]["message"]
            except (ValueError, KeyError, TypeError):
                message = resp.text[:120]
            raise FirestoreError(f"Firestore ha risposto con HTTP {resp.status_code}: {message}")
        return resp

    async def get(self, path: str) -> dict | None:
        """The document's fields, or None if it does not exist."""
        resp = await self._request("GET", path)
        if resp.status_code == 404:
            return None
        return decode_fields(resp.json().get("fields", {}))

    async def set(self, path: str, data: dict) -> None:
        """Write the whole document (created if missing, replaced if present)."""
        resp = await self._request("PATCH", path, json={"fields": encode_fields(data)})
        if resp.status_code == 404:
            raise FirestoreError(f"percorso non valido: {path}")

    async def delete(self, path: str) -> None:
        """Remove the document (nothing happens if it does not exist)."""
        await self._request("DELETE", path)

    async def collection_group(self, collection_id: str) -> list[tuple[str, dict]]:
        """Every document in every collection called ``collection_id``, wherever it is
        (e.g. "artisti" of all the users), as (path, fields) pairs; the path is like
        ``"utenti/<code>/artisti/12948083"``."""
        query = {"structuredQuery": {"from": [{"collectionId": collection_id, "allDescendants": True}]}}
        resp = await self._request("POST", f"{FIRESTORE_URL}/{self._root}:runQuery", json=query)
        if resp.status_code == 404:
            raise FirestoreError("database di Firestore non trovato")
        prefix = f"{self._root}/"
        found = []
        for item in resp.json():
            document = item.get("document")  # the answer holds only "readTime" when nothing matches
            if document:
                found.append((document["name"].removeprefix(prefix), decode_fields(document.get("fields", {}))))
        return found
