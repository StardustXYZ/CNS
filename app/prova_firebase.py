"""Feasibility test: can GitHub write to Firestore and read it back?

Writes the document ``stato/github`` with the time of this run, then reads it back. The
app shows that time in Impostazioni ("Ultimo contatto da GitHub"), which proves the whole
chain: GitHub -> Firestore -> rules -> the owner's phone.

Usage:
    python -m app.prova_firebase
Exit code 1 if Firestore could not be written or read.
"""

from __future__ import annotations

import asyncio
from datetime import datetime
import os
import sys
from zoneinfo import ZoneInfo

from app.config import settings
from app.services.firestore import DocumentStore, FirestoreClient, FirestoreError

STATUS_PATH = "stato/github"


def run_url() -> str | None:
    """The page of this GitHub run, when running on GitHub."""
    server, repo, run = (os.getenv(k) for k in ("GITHUB_SERVER_URL", "GITHUB_REPOSITORY", "GITHUB_RUN_ID"))
    return f"{server}/{repo}/actions/runs/{run}" if server and repo and run else None


async def check(db: DocumentStore, now: datetime) -> list[str]:
    """Write the status, read it back and describe what happened (raises FirestoreError)."""
    before = await db.get(STATUS_PATH)
    status = {"ultimo_contatto": now, "origine": "prova", "giro": run_url()}
    await db.set(STATUS_PATH, status)
    after = await db.get(STATUS_PATH)
    if not after or after.get("ultimo_contatto") != now:
        raise FirestoreError("il documento riletto non è quello appena scritto")
    previous = before.get("ultimo_contatto") if before else None
    lines = [f"✅ Scritto e riletto `{STATUS_PATH}` alle {now:%H:%M:%S} del {now:%d/%m/%Y}."]
    if isinstance(previous, datetime):
        lines.append(f"Il contatto precedente era del {previous.astimezone(now.tzinfo):%d/%m/%Y alle %H:%M}.")
    else:
        lines.append("Primo contatto: il documento non esisteva ancora.")
    return lines


async def run() -> tuple[str, bool]:
    now = datetime.now(ZoneInfo(settings.TIMEZONE)).replace(microsecond=0)
    try:
        async with FirestoreClient.from_settings() as db:
            lines, ok = await check(db, now), True
    except FirestoreError as err:
        lines, ok = [f"❌ {err}"], False
    return "\n".join(["## Prova di Firebase", "", *lines, ""]), ok


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
