"""The scheduled check, every 3 hours on GitHub Actions (.github/workflows/controllo.yml).

For now (phase 2c) it reads the artists of every user from Firestore, groups them by Deezer
artist (an artist followed by three people will be asked to Deezer only once) and records
the run in ``stato/github``, which the app shows in Impostazioni. Comparing with the
releases already seen and sending the notifications arrive in phase 4.

The run's log is public (the repository is public): it shows only numbers, never the
names of the artists or the users' codes.

Usage:
    python -m app.controllo
Exit code 1 if Firestore could not be read or written.
"""

from __future__ import annotations

import asyncio
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime
import os
import sys
import time
from zoneinfo import ZoneInfo

from app.config import settings
from app.prova_firebase import STATUS_PATH, run_url
from app.services.firestore import DocumentStore, FirestoreClient, FirestoreError

LISTS_TO_CHECK = ("controllare", "recuperando")  # new releases matter in both; "archivio" is left alone


@dataclass
class FollowedArtist:
    """One Deezer artist and who follows it: user code -> list."""

    id: str
    name: str
    followers: dict[str, str] = field(default_factory=dict)

    @property
    def to_check(self) -> bool:
        return any(lista in LISTS_TO_CHECK for lista in self.followers.values())


def group_artists(documents: list[tuple[str, dict]]) -> dict[str, FollowedArtist]:
    """Artists from the documents ``utenti/<code>/artisti/<Deezer id>``, one entry per Deezer artist."""
    artists: dict[str, FollowedArtist] = {}
    for path, data in documents:
        parts = path.split("/")
        if len(parts) != 4 or parts[0] != "utenti" or parts[2] != "artisti" or not parts[3].isdigit():
            continue  # a collection called "artisti" somewhere else: not ours
        uid, artist_id = parts[1], parts[3]
        artist = artists.setdefault(artist_id, FollowedArtist(artist_id, str(data.get("nome") or "")))
        artist.followers[uid] = str(data.get("lista") or "")
    return artists


async def run_check(db: DocumentStore, now: datetime) -> list[str]:
    """One run: read, group, record the run; returns the lines of the report (numbers only)."""
    artists = group_artists(await db.collection_group("artisti"))
    users = {uid for a in artists.values() for uid in a.followers}
    lists = Counter(lista for a in artists.values() for lista in a.followers.values())
    to_check = [a for a in artists.values() if a.to_check]
    await db.set(STATUS_PATH, {
        "ultimo_contatto": now,
        "origine": "controllo",
        "giro": run_url(),
        "utenti": len(users),
        "artisti": len(to_check),
    })
    shared = sum(1 for a in to_check if len(a.followers) > 1)
    return [
        f"✅ Giro del {now:%d/%m/%Y alle %H:%M}.",
        "",
        "| | Numero |",
        "|---|---|",
        f"| Utenti con almeno un artista | {len(users)} |",
        f"| Artisti in Controllare (per utente) | {lists['controllare']} |",
        f"| Artisti in Recuperando (per utente) | {lists['recuperando']} |",
        f"| Artisti in Archivio (per utente) | {lists['archivio']} |",
        f"| Artisti diversi da chiedere a Deezer | {len(to_check)} |",
        f"| …di cui seguiti da più persone | {shared} |",
        "",
        "Il confronto con le uscite già viste e le notifiche arrivano nella Fase 4.",
    ]


async def run() -> tuple[str, bool]:
    now = datetime.now(ZoneInfo(settings.TIMEZONE)).replace(microsecond=0)
    start = time.perf_counter()
    try:
        async with FirestoreClient.from_settings() as db:
            lines, ok = await run_check(db, now), True
        lines.append(f"Durata: {time.perf_counter() - start:.1f} secondi.")
    except FirestoreError as err:
        lines, ok = [f"❌ {err}"], False
    return "\n".join(["## Controllo delle uscite", "", *lines, ""]), ok


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
