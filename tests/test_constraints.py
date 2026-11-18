"""The Python dependencies are pinned (constraints.txt) and every workflow installs with the pins:
the check that runs every 3 hours must not change behaviour because a library had a new release."""

from __future__ import annotations

from pathlib import Path
import re
import tomllib

from packaging.requirements import Requirement
from packaging.utils import canonicalize_name
from packaging.version import Version

ROOT = Path(__file__).resolve().parent.parent
PIN = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._-]*)==([A-Za-z0-9.!+_-]+)$")


def pins() -> dict[str, str]:
    found = {}
    for line in (ROOT / "constraints.txt").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = PIN.match(line)
        assert match, f"constraints.txt: la riga «{line}» non è una versione esatta (nome==versione)"
        found[canonicalize_name(match.group(1))] = match.group(2)
    return found


def declared() -> list[Requirement]:
    project = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))["project"]
    specs = list(project["dependencies"])
    for extra in project.get("optional-dependencies", {}).values():
        specs += extra
    return [Requirement(spec) for spec in specs]


def test_every_dependency_has_an_exact_version():
    found = pins()
    missing = [r.name for r in declared() if canonicalize_name(r.name) not in found]
    assert not missing, f"manca in constraints.txt: {', '.join(missing)}"


def test_the_pinned_versions_respect_what_pyproject_asks():
    found = pins()
    for requirement in declared():
        version = found.get(canonicalize_name(requirement.name))
        if version:
            assert Version(version) in requirement.specifier, f"{requirement.name}=={version} non rispetta «{requirement}»"


def test_every_workflow_installs_with_the_pins():
    for workflow in sorted((ROOT / ".github" / "workflows").glob("*.yml")):
        for line in workflow.read_text(encoding="utf-8").splitlines():
            if "pip install" in line and "-e" in line:
                assert "-c constraints.txt" in line, f"{workflow.name}: «{line.strip()}» senza -c constraints.txt"
