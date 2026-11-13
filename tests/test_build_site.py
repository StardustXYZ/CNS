"""Site build: every file copied, version stamped, nothing secret published."""

from __future__ import annotations

import json
import re

import pytest

from app.build_site import WEB_DIR, build_site

BUILD = "2026-11-12T19:30+01:00"


@pytest.fixture()
def site(tmp_path):
    out = tmp_path / "site"
    build_site(out, BUILD)
    return out


def test_all_web_files_are_copied(site):
    for name in ["index.html", "app.js", "firebase.js", "deezer.js", "discografia.js", "segnalibro.js", "style.css", "sw.js", "manifest.webmanifest",
                 "icons/icon-192.png", "icons/icon-512.png", "icons/icon-maskable-512.png"]:
        assert (site / name).is_file(), name


def test_javascript_tests_are_not_published(site):
    assert not (site / "test").exists()


def test_version_is_stamped(site):
    for name in ["sw.js", "app.js"]:
        text = (site / name).read_text(encoding="utf-8")
        assert "__BUILD__" not in text
        assert BUILD in text
    # the source files keep the placeholder for the next build
    assert "__BUILD__" in (WEB_DIR / "sw.js").read_text(encoding="utf-8")


def test_old_site_is_replaced(tmp_path):
    out = tmp_path / "site"
    out.mkdir()
    (out / "vecchio.txt").write_text("x")
    build_site(out, BUILD)
    assert not (out / "vecchio.txt").exists()


def test_missing_placeholder_is_an_error(tmp_path):
    web = tmp_path / "web"
    web.mkdir()
    (web / "sw.js").write_text("const CACHE = 'cns';")
    (web / "app.js").write_text("const BUILD = '__BUILD__';")
    with pytest.raises(ValueError, match="sw.js"):
        build_site(tmp_path / "site", BUILD, web_dir=web)


def test_service_worker_caches_every_file_it_lists(site):
    sw = (site / "sw.js").read_text(encoding="utf-8")
    shell = re.search(r"const SHELL = \[(.*?)\];", sw, re.S).group(1)
    for name in re.findall(r'"([^"]+)"', shell):
        if name != "./":
            assert (site / name).is_file(), f"sw.js mette in cache {name}, che non esiste"


def test_manifest_points_to_existing_icons(site):
    manifest = json.loads((site / "manifest.webmanifest").read_text(encoding="utf-8"))
    assert manifest["short_name"] == "CNS"
    assert manifest["lang"] == "it"
    assert {i["purpose"] for i in manifest["icons"]} == {"any", "maskable"}
    for icon in manifest["icons"]:
        assert (site / icon["src"]).is_file()


def test_no_secrets_in_the_site(site):
    for path in site.rglob("*"):
        if path.suffix in {".html", ".js", ".css", ".webmanifest"}:
            text = path.read_text(encoding="utf-8")
            assert "private_key" not in text and "NTFY_TOPIC" not in text, path.name
