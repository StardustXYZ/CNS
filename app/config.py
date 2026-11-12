"""Settings read from the environment (GitHub secrets) or from the local .env file."""

from __future__ import annotations

from dataclasses import dataclass, field
import os
from pathlib import Path

from dotenv import load_dotenv

ROOT_DIR = Path(__file__).resolve().parent.parent
load_dotenv(ROOT_DIR / ".env")


@dataclass(frozen=True)
class Settings:
    # Secret: whoever knows the topic can read and send notifications
    NTFY_TOPIC: str = field(default_factory=lambda: os.getenv("NTFY_TOPIC", "").strip())
    NTFY_SERVER: str = field(default_factory=lambda: os.getenv("NTFY_SERVER", "https://ntfy.sh").rstrip("/"))
    # The phone app on GitHub Pages ("Apri l'app" button)
    APP_URL: str = "https://stardustxyz.github.io/CNS/"
    TIMEZONE: str = "Europe/Rome"
    # Notifications arrive without sound from QUIET_START to QUIET_END (Italian time)
    QUIET_START: int = 23
    QUIET_END: int = 8


settings = Settings()
