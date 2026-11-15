"""Test of the notifications of the Android app (Firebase Cloud Messaging).

1. Checks that the FCM API answers for the project (a message only validated, to a token
   that does not exist: FCM must say that the token is not valid, not that the API is off).
2. Sends a test notification to the phones of the administrator (config/ammessi.admin),
   registered in the app with "Notifiche su questo telefono". Nobody else gets it.

The report shows only numbers: never user codes or tokens.

Usage:
    python -m app.prova_notifiche
Exit code 1 if FCM does not answer or a notification could not be sent.
"""

from __future__ import annotations

import asyncio
from datetime import datetime
import os
import sys
from zoneinfo import ZoneInfo

from app.config import settings
from app.controllo import ALLOW_LIST_PATH, phones_by_user
from app.services.fcm import FCM_SCOPES, FcmClient, PushError, PushSender
from app.services.firestore import (
    DocumentStore, FirestoreClient, FirestoreError, service_account_info, service_account_token,
)
from app.services.ntfy import Notification

FAKE_TOKEN = "token-che-non-esiste"


async def check_api(fcm: FcmClient) -> str:
    """FCM's answer to a message for a token that does not exist, in words."""
    try:
        await fcm.send(FAKE_TOKEN, Notification(title="Prova", message="Prova"), validate_only=True)
    except PushError as err:
        text = str(err)
        if "HTTP 400" in text:
            return "ok"  # the API is on: it only refused the made-up token
        return text
    return "ok"


async def send_test(db: DocumentStore, push: PushSender, now: datetime) -> tuple[int, int, int]:
    """Sends the test to the administrator's phones: (phones, delivered, gone)."""
    allow_list = await db.get(ALLOW_LIST_PATH) or {}
    admin = allow_list.get("admin")
    phones = phones_by_user(await db.collection_group("telefoni")).get(admin, []) if admin else []
    notification = Notification(
        title="Prova di CNS",
        message=f"Le notifiche dell'app funzionano ({now:%d/%m/%Y alle %H:%M}).",
    )
    delivered = gone = 0
    for path, token in phones:
        if await push.send(token, notification):
            delivered += 1
        else:
            await db.delete(path)
            gone += 1
    return len(phones), delivered, gone


async def run() -> tuple[str, bool]:
    now = datetime.now(ZoneInfo(settings.TIMEZONE)).replace(microsecond=0)
    lines: list[str] = []
    ok = True
    try:
        info = service_account_info()
        project = info.get("project_id") or settings.FIREBASE_PROJECT_ID
        try:
            token = await asyncio.to_thread(service_account_token, info, FCM_SCOPES)
        except Exception as err:  # noqa: BLE001 - google-auth raises its own errors
            raise FirestoreError(f"accesso a FCM con l'account di servizio non riuscito: {type(err).__name__}") from err
        async with FcmClient(project, token) as fcm, FirestoreClient.from_settings() as db:
            api = await check_api(fcm)
            if api != "ok":
                lines.append(f"❌ L'API di Firebase Cloud Messaging non risponde: {api}.")
                lines.append("Va attivata nella console di Google Cloud (API Firebase Cloud Messaging).")
                ok = False
            else:
                lines.append("✅ L'API di Firebase Cloud Messaging risponde.")
                phones, delivered, gone = await send_test(db, fcm, now)
                lines += [
                    "",
                    "| | Numero |",
                    "|---|---|",
                    f"| Telefoni dell'amministratore | {phones} |",
                    f"| Notifiche di prova inviate | {delivered} |",
                    f"| Telefoni tolti (app non più presente) | {gone} |",
                ]
                if not phones:
                    lines.append("")
                    lines.append("Nessun telefono registrato: nell'app attiva «Notifiche su questo telefono».")
    except (FirestoreError, PushError) as err:
        lines, ok = [f"❌ {err}"], False
    return "\n".join(["## Prova delle notifiche dell'app", "", *lines, ""]), ok


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    report, ok = asyncio.run(run())
    print(report)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:  # shown on the run page on GitHub
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write(report)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
