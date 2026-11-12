"""Build the CNS site for GitHub Pages: the files in web/ with this build's version.

The service worker caches the app under a name with the build time, so a new build makes
the phones download the new files (as in CNV's export_static).

Usage:
    python -m app.build_site --out site
"""

from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path
import shutil
from zoneinfo import ZoneInfo

from app.config import ROOT_DIR, settings

WEB_DIR = ROOT_DIR / "web"
PLACEHOLDER = "__BUILD__"
VERSIONED = ("sw.js", "app.js")  # files that carry the build version


def build_site(out_dir: Path, build: str, web_dir: Path = WEB_DIR) -> None:
    """Copy the web app into ``out_dir`` and stamp it with ``build``."""
    if out_dir.exists():
        shutil.rmtree(out_dir)
    shutil.copytree(web_dir, out_dir, ignore=shutil.ignore_patterns("test"))  # the JS tests stay out of the site
    for name in VERSIONED:
        path = out_dir / name
        text = path.read_text(encoding="utf-8")
        if PLACEHOLDER not in text:
            raise ValueError(f"{name} non contiene {PLACEHOLDER}: la versione non verrebbe aggiornata")
        path.write_text(text.replace(PLACEHOLDER, build), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Costruisce il sito di CNS per GitHub Pages")
    parser.add_argument("--out", default="site", help="cartella di destinazione (default: site)")
    out_dir = Path(parser.parse_args().out)
    build = datetime.now(ZoneInfo(settings.TIMEZONE)).isoformat(timespec="minutes")
    build_site(out_dir, build)
    print(f"Sito di CNS in {out_dir} (versione {build})")


if __name__ == "__main__":
    main()
