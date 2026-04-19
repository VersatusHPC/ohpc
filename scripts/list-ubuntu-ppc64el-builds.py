#!/usr/bin/env python3
"""List Ubuntu 24.04 ppc64el Debian package builds in dependency order."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]

EXCLUDED_COMPONENTS = {
    "components/compiler-families/intel-compilers-devel",
    "components/dev-tools/cuda-devel",
    "components/fs/lustre-client",
    "components/mpi-families/impi-devel",
    "components/perf-tools/msr-safe",
}

EXCLUDED_NAME_PATTERNS = (
    "intel",
    "impi",
    "cuda",
    "lustre",
    "msr-safe",
    "geopm",
    "arm-compilers",
)


def parse_control(path: Path) -> list[dict[str, str]]:
    stanzas: list[dict[str, str]] = []
    current: dict[str, str] = {}
    last_key: str | None = None

    for raw in path.read_text(errors="ignore").splitlines():
        if not raw.strip():
            if current:
                stanzas.append(current)
                current = {}
                last_key = None
            continue
        if raw[0].isspace() and last_key:
            current[last_key] += "\n" + raw.strip()
            continue
        if ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        last_key = key
        current[key] = value.strip()

    if current:
        stanzas.append(current)
    return stanzas


def split_deps(value: str) -> list[str]:
    deps: list[str] = []
    for item in value.replace("\n", " ").split(","):
        item = item.strip()
        if not item:
            continue
        item = item.split("|", 1)[0].strip()
        item = re.sub(r"\[[^\]]*\]", "", item)
        item = re.sub(r"<[^>]*>", "", item)
        item = re.sub(r"\([^)]*\)", "", item)
        item = item.split(":", 1)[0].strip()
        if item:
            deps.append(item)
    return deps


def arch_is_ppc64el_compatible(arch_value: str) -> bool:
    for arch in arch_value.split():
        if arch in {"all", "any", "linux-any", "ppc64el"}:
            return True
        if arch.startswith("!"):
            continue
    return False


def component_for_debian_dir(debian_dir: Path) -> Path:
    return debian_dir.parent


def is_excluded(debian_dir: Path, stanzas: list[dict[str, str]]) -> bool:
    rel_component = component_for_debian_dir(debian_dir).relative_to(REPO_ROOT).as_posix()
    if rel_component in EXCLUDED_COMPONENTS:
        return True
    if debian_dir.name.startswith("debian-intel") or debian_dir.name == "debian-impi":
        return True

    source = stanzas[0].get("Source", "").lower()
    package_names = [s.get("Package", "").lower() for s in stanzas[1:]]
    names = [source, *package_names, rel_component.lower(), debian_dir.name.lower()]
    if any(pattern in name for pattern in EXCLUDED_NAME_PATTERNS for name in names):
        return True

    package_stanzas = [s for s in stanzas[1:] if "Package" in s]
    if not package_stanzas:
        return True
    if not any(arch_is_ppc64el_compatible(s.get("Architecture", "")) for s in package_stanzas):
        return True
    return False


def topological_sort(nodes: dict[str, set[str]]) -> list[str]:
    pending = {name: set(deps) for name, deps in nodes.items()}
    emitted: list[str] = []
    while pending:
        ready = sorted(name for name, deps in pending.items() if not deps)
        if not ready:
            details = ", ".join(f"{name}: {sorted(deps)}" for name, deps in sorted(pending.items()))
            raise SystemExit(f"cyclic or missing dependency detected: {details}")
        emitted.extend(ready)
        for name in ready:
            pending.pop(name)
        for deps in pending.values():
            deps.difference_update(ready)
    return emitted


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--show-excluded", action="store_true")
    args = parser.parse_args()

    entries: dict[str, dict[str, object]] = {}
    binary_to_entry: dict[str, str] = {}
    excluded: list[str] = []

    for control in sorted((REPO_ROOT / "components").glob("**/debian*/control")):
        debian_dir = control.parent
        if debian_dir.name == "DEBIAN":
            continue

        stanzas = parse_control(control)
        if not stanzas or "Source" not in stanzas[0]:
            continue
        rel_debian = debian_dir.relative_to(REPO_ROOT).as_posix()
        if is_excluded(debian_dir, stanzas):
            excluded.append(rel_debian)
            continue

        source = stanzas[0]["Source"]
        entry = rel_debian
        runtime_deps: list[str] = []
        if source == "ohpc-meta-packages":
            for stanza in stanzas[1:]:
                runtime_deps.extend(split_deps(stanza.get("Pre-Depends", "")))
                runtime_deps.extend(split_deps(stanza.get("Depends", "")))
        entries[entry] = {
            "source": source,
            "build_deps": split_deps(stanzas[0].get("Build-Depends", "")),
            "runtime_deps": runtime_deps,
            "packages": [s["Package"] for s in stanzas[1:] if "Package" in s],
        }
        for pkg in entries[entry]["packages"]:  # type: ignore[index]
            binary_to_entry[str(pkg)] = entry

    graph: dict[str, set[str]] = {}
    for entry, meta in entries.items():
        deps: set[str] = set()
        build_deps = list(meta["build_deps"])  # type: ignore[index]
        ordered_deps = build_deps + list(meta["runtime_deps"])  # type: ignore[index]
        for dep in ordered_deps:
            dep_entry = binary_to_entry.get(str(dep))
            if dep_entry and dep_entry != entry:
                deps.add(dep_entry)
        if entry == "components/admin/lmod/debian":
            deps.add("components/admin/ohpc-filesystem/debian")
        if "ohpc-buildroot" in build_deps:
            deps.add("components/admin/lmod/debian")
        deps.discard(entry)
        graph[entry] = deps

    if args.show_excluded:
        for item in excluded:
            print(f"# excluded {item}", file=sys.stderr)

    for entry in topological_sort(graph):
        print(entry)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
