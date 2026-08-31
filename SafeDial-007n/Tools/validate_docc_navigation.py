#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
from pathlib import Path


EXPECTED_PROJECTS = ["01-Sound", "02-Haptics", "03-DepthAxis", "04-Integration"]
DOWNLOAD_URL = (
    "https://junghankang.github.io/2026TechMap_tutorial/"
    "downloads/SafeDial-Tutorial-007n.zip"
)


def fail(message: str) -> None:
    raise SystemExit(message)


def load(path: Path) -> dict:
    if not path.is_file():
        fail(f"Missing DocC render node: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: validate_docc_navigation.py <safe-dial.doccarchive>")

    archive = Path(sys.argv[1]).resolve()
    tutorial_root = archive / "data" / "tutorials" / "safe-dial"
    render_nodes = sorted(tutorial_root.glob("*.json"))
    if len(render_nodes) != len(EXPECTED_PROJECTS):
        fail(f"Expected four tutorial render nodes, found {len(render_nodes)}")

    expected_module_references: list[str] | None = None
    for index, node_path in enumerate(render_nodes):
        node = load(node_path)
        hierarchy = node.get("hierarchy", {})
        modules = hierarchy.get("modules", [])
        module_references = [module.get("reference") for module in modules]
        if len(modules) != len(EXPECTED_PROJECTS):
            fail(f"{node_path.name}: expected four chapters, found {len(modules)}")
        if len(set(module_references)) != len(module_references):
            fail(f"{node_path.name}: Chapter identifiers are not unique")

        projects: list[str] = []
        for module in modules:
            module_projects = module.get("projects", [])
            if len(module_projects) != 1:
                fail(f"{node_path.name}: each Chapter must contain exactly one tutorial")
            projects.append(module_projects[0]["reference"].rsplit("/", 1)[-1])
        if projects != EXPECTED_PROJECTS:
            fail(f"{node_path.name}: unexpected tutorial order: {projects}")

        if expected_module_references is None:
            expected_module_references = module_references
        elif module_references != expected_module_references:
            fail(f"{node_path.name}: Chapter hierarchy differs between render nodes")

        paths = hierarchy.get("paths", [])
        if not paths or paths[0][-1] != module_references[index]:
            fail(f"{node_path.name}: tutorial is attached to the wrong Chapter")

    catalog = load(archive / "data" / "tutorials" / "safedial.json")
    if DOWNLOAD_URL not in json.dumps(catalog, ensure_ascii=False):
        fail("The rendered tutorial catalog does not contain the public ZIP URL")

    print("DocC navigation passed: unique Chapters, 1→2→3→4 order, public ZIP link.")


if __name__ == "__main__":
    main()
