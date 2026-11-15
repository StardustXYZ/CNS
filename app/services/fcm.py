"""Notifications of the Android app through Firebase Cloud Messaging (HTTP v1 API).

The same notifications sent to ntfy (title, text, cover) go to every phone the person
registered in the app (utenti/{uid}/telefoni). Android shows them by itself, with the app's
headphones icon; touching one opens the app on Novità, where Spotify is one tap away. From
23 to 8 they go to the silent channel "notte" (the app creates both channels). A phone that
no longer exists (app removed, data cleared) is reported as gone, so its document is removed.
"""

from __future__ import annotations

from typing import Protocol

import httpx

from app.services.ntfy import PRIORITY_QUIET, Notification

FCM_URL = "https://fcm.googleapis.com/v1"
FCM_SCOPES = ["https://www.googleapis.com/auth/firebase.messaging"]
CHANNEL_DEFAULT = "uscite"  # android/app/src/main/kotlin/.../MainActivity.kt creates them
CHANNEL_QUIET = "notte"
APP_LINK = "cns://novita"  # where a tap opens the app (lib/home.dart, widgetLink)
COLOR = "#008000"
GONE_CODES = {"UNREGISTERED"}  # the token belongs to an app that is not there any more


class PushError(Exception):
    """FCM refused a notification for a reason other than a phone that is gone."""


def fcm_message(token: str, notification: Notification) -> dict:
    """The body of messages:send for one phone."""
    shown: dict = {"title": notification.title, "body": notification.message}
    picture = notification.attach or notification.icon
    if picture:
        shown["image"] = picture
    return {
        "message": {
            "token": token,
            "notification": shown,
            "data": {"link": APP_LINK},
            "android": {
                "priority": "high",
                "notification": {
                    "channel_id": CHANNEL_QUIET if notification.priority == PRIORITY_QUIET else CHANNEL_DEFAULT,
                    "color": COLOR,
                },
            },
        }
    }


def _error_code(resp: httpx.Response) -> str:
    """FCM's own error code (e.g. UNREGISTERED), from the details of the answer."""
    try:
        error = resp.json()["error"]
    except (ValueError, KeyError, TypeError):
        return ""
    for detail in error.get("details", []):
        if isinstance(detail, dict) and detail.get("errorCode"):
            return str(detail["errorCode"])
    return str(error.get("status", ""))


class PushSender(Protocol):
    """Anything that can deliver a notification to one phone (the real client or a test fake)."""

    async def send(self, token: str, notification: Notification) -> bool:
        """True when delivered, False when the phone is gone (raises on other problems)."""
        ...


class FcmClient:
    """Sends to FCM. Use as ``async with FcmClient(project, access_token) as fcm: ...``."""

    def __init__(self, project_id: str, access_token: str, timeout: float = 15.0,
                 transport: httpx.AsyncBaseTransport | None = None) -> None:
        # The whole address: "messages:send" alone would be read as an address with scheme "messages"
        self._send_url = f"{FCM_URL}/projects/{project_id}/messages:send"
        self._client = httpx.AsyncClient(
            headers={"Authorization": f"Bearer {access_token}"},
            timeout=timeout,
            transport=transport,
        )

    async def __aenter__(self) -> FcmClient:
        return self

    async def __aexit__(self, *exc) -> None:
        await self._client.aclose()

    async def send(self, token: str, notification: Notification, validate_only: bool = False) -> bool:
        body = fcm_message(token, notification)
        if validate_only:
            body["validate_only"] = True
        try:
            resp = await self._client.post(self._send_url, json=body)
        except httpx.HTTPError as err:
            raise PushError(f"FCM non risponde ({type(err).__name__})") from err
        if resp.status_code == 200:
            return True
        code = _error_code(resp)
        if resp.status_code == 404 or code in GONE_CODES:
            return False
        raise PushError(f"FCM ha risposto con HTTP {resp.status_code} ({code or 'senza codice'})")
