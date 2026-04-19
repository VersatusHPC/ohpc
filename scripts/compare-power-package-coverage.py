#!/usr/bin/env python3
"""Compare public VersatusHPC POWER package coverage across repositories."""

from __future__ import annotations

import argparse
import gzip
import lzma
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from dataclasses import dataclass
from urllib.parse import urljoin

RPM_REPOS = {
    "EL_10": "https://repos.versatushpc.com.br/openhpc/versatushpc-4/EL_10/",
    "openEuler_24.03": "https://repos.versatushpc.com.br/openhpc/versatushpc-4/openEuler_24.03/",
}
DEB_REPO = "https://repos.versatushpc.com.br/openhpc/versatushpc-4/Ubuntu_24.04/"
RPM_NS = {
    "md": "http://linux.duke.edu/metadata/repo",
    "common": "http://linux.duke.edu/metadata/common",
    "rpm": "http://linux.duke.edu/metadata/rpm",
}
OPEN_EULER_SUPPORT_PREFIXES = (
    "freeipmi",
    "libedit",
    "libfabric",
    "lua",
    "lua-filesystem",
    "yaml-cpp",
    "zstd",
)
EXPECTED_POWER_LOCKED_ABSENCES = (
    "intel",
    "impi",
    "cuda",
    "arm",
    "geopm",
    "msr-safe",
    "lustre-client",
)


@dataclass(frozen=True)
class Package:
    name: str
    arch: str
    version: str
    location: str
    requires: tuple[tuple[str, ...], ...] = ()
    provides: tuple[str, ...] = ()


def curl(url: str) -> bytes:
    try:
        return subprocess.check_output(["curl", "-fsSL", url])
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"failed to fetch {url}: {exc}") from exc


def decompress(path: str, data: bytes) -> bytes:
    if path.endswith(".zst"):
        try:
            return subprocess.check_output(["zstd", "-dc"], input=data)
        except FileNotFoundError as exc:
            raise SystemExit("zstd is required to read RPM repo metadata") from exc
    if path.endswith(".gz"):
        return gzip.decompress(data)
    if path.endswith(".xz"):
        return lzma.decompress(data)
    return data


def load_rpm_repo(base_url: str) -> list[Package]:
    repomd = ET.fromstring(curl(urljoin(base_url, "repodata/repomd.xml")))
    primary_href = None
    for data in repomd.findall("md:data", RPM_NS):
        if data.attrib.get("type") == "primary":
            primary_href = data.find("md:location", RPM_NS).attrib["href"]
            break
    if primary_href is None:
        raise SystemExit(f"no primary metadata in {base_url}")

    xml_data = decompress(primary_href, curl(urljoin(base_url, primary_href)))
    root = ET.fromstring(xml_data)
    packages: list[Package] = []
    for pkg in root.findall("common:package", RPM_NS):
        name = pkg.findtext("common:name", namespaces=RPM_NS) or ""
        arch = pkg.findtext("common:arch", namespaces=RPM_NS) or ""
        version_node = pkg.find("common:version", RPM_NS)
        version = version_node.attrib.get("ver", "") if version_node is not None else ""
        location_node = pkg.find("common:location", RPM_NS)
        location = location_node.attrib.get("href", "") if location_node is not None else ""
        format_node = pkg.find("common:format", RPM_NS)
        requires: tuple[tuple[str, ...], ...] = ()
        provides: tuple[str, ...] = ()
        if format_node is not None:
            requires_node = format_node.find("rpm:requires", RPM_NS)
            if requires_node is not None:
                requires = tuple(
                    (entry.attrib["name"],)
                    for entry in requires_node.findall("rpm:entry", RPM_NS)
                    if entry.attrib.get("name")
                )
            provides_node = format_node.find("rpm:provides", RPM_NS)
            if provides_node is not None:
                provides = tuple(
                    entry.attrib["name"]
                    for entry in provides_node.findall("rpm:entry", RPM_NS)
                    if entry.attrib.get("name")
                )
        packages.append(Package(name, arch, version, location, requires, provides))
    return packages


def parse_deb_stanzas(data: bytes) -> list[dict[str, str]]:
    text = data.decode("utf-8", errors="replace")
    stanzas: list[dict[str, str]] = []
    current: dict[str, str] = {}
    last_key: str | None = None
    for line in text.splitlines():
        if not line:
            if current:
                stanzas.append(current)
                current = {}
                last_key = None
            continue
        if line.startswith(" ") and last_key:
            current[last_key] += "\n" + line
            continue
        key, _, value = line.partition(":")
        current[key] = value.strip()
        last_key = key
    if current:
        stanzas.append(current)
    return stanzas


def deb_dependency_groups(value: str) -> tuple[tuple[str, ...], ...]:
    groups: list[tuple[str, ...]] = []
    for part in value.split(","):
        names: list[str] = []
        for alternative in part.split("|"):
            name = alternative.strip().split(" ", 1)[0].strip()
            if name:
                names.append(name)
        if names:
            groups.append(tuple(names))
    return tuple(groups)


def deb_provides(value: str) -> tuple[str, ...]:
    provides: list[str] = []
    for part in value.split(","):
        name = part.strip().split(" ", 1)[0].strip()
        if name:
            provides.append(name)
    return tuple(provides)


def load_deb_repo(base_url: str) -> list[Package]:
    data = decompress("Packages.xz", curl(urljoin(base_url, "Packages.xz")))
    packages: list[Package] = []
    for stanza in parse_deb_stanzas(data):
        packages.append(
            Package(
                stanza.get("Package", ""),
                stanza.get("Architecture", ""),
                stanza.get("Version", ""),
                stanza.get("Filename", ""),
                deb_dependency_groups(stanza.get("Depends", "")),
                deb_provides(stanza.get("Provides", "")),
            )
        )
    return packages


def arch_counter(packages: list[Package]) -> str:
    counts = Counter(pkg.arch for pkg in packages)
    return ", ".join(f"{arch}={counts[arch]}" for arch in sorted(counts))


def non_source_names(packages: list[Package]) -> set[str]:
    return {pkg.name for pkg in packages if pkg.arch != "src"}


def is_openhpc_dependency_name(name: str) -> bool:
    return name.startswith("ohpc-") or name.endswith("-ohpc")


def openhpc_dependency_gaps(packages: list[Package]) -> dict[str, set[str]]:
    available = {pkg.name for pkg in packages}
    available.update(
        provide
        for pkg in packages
        for provide in pkg.provides
        if is_openhpc_dependency_name(provide)
    )

    gaps: dict[str, set[str]] = {}
    for pkg in packages:
        for group in pkg.requires:
            ohpc_names = tuple(name for name in group if is_openhpc_dependency_name(name))
            if not ohpc_names:
                continue
            if not any(name in available for name in ohpc_names):
                gaps.setdefault(pkg.name, set()).add(" | ".join(ohpc_names))
    return gaps


def print_dependency_gaps(label: str, packages: list[Package]) -> int:
    candidates = [pkg for pkg in packages if pkg.arch != "src"]
    gaps = openhpc_dependency_gaps(candidates)
    if not gaps:
        print(f"  {label}: OpenHPC dependencies resolve inside the repository view")
        return 0
    print(f"  {label}: {len(gaps)} packages have missing OpenHPC dependencies")
    for package, missing in sorted(gaps.items()):
        print(f"    {package}: {', '.join(sorted(missing))}")
    return 1


def print_presence(label: str, names: set[str], expected: list[str]) -> int:
    missing = [name for name in expected if name not in names]
    if missing:
        print(f"{label}: missing expected packages: {', '.join(missing)}")
        return 1
    print(f"{label}: expected core packages present")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fail-on-missing-core", action="store_true", help="exit non-zero when core POWER packages are absent")
    parser.add_argument("--fail-on-issues", action="store_true", help="exit non-zero when any coverage drift is detected")
    args = parser.parse_args()

    rpm_sets = {label: load_rpm_repo(url) for label, url in RPM_REPOS.items()}
    deb_packages = load_deb_repo(DEB_REPO)

    print("Repository package counts")
    for label, packages in rpm_sets.items():
        print(f"  {label}: total={len(packages)} ({arch_counter(packages)})")
    print(f"  Ubuntu_24.04: total={len(deb_packages)} ({arch_counter(deb_packages)})")

    el_names = non_source_names(rpm_sets["EL_10"])
    oe_names = non_source_names(rpm_sets["openEuler_24.03"])
    ubuntu_power = {pkg.name for pkg in deb_packages if pkg.arch in {"all", "ppc64el"}}

    print("\nEL10 vs openEuler non-source delta")
    oe_only = sorted(oe_names - el_names)
    support = [name for name in oe_only if name.startswith(OPEN_EULER_SUPPORT_PREFIXES)]
    other = [name for name in oe_only if name not in support]
    delta_status = 0
    print(f"  openEuler-only support packages: {len(support)}")
    if support:
        print("    " + ", ".join(support))
    print(f"  openEuler-only OpenHPC candidates: {len(other)}")
    if other:
        print("    " + ", ".join(other))
        delta_status = 1
    el_only = sorted(el_names - oe_names)
    print(f"  EL10-only packages: {len(el_only)}")
    if el_only:
        print("    " + ", ".join(el_only))
        delta_status = 1

    core_rpm = [
        "gnu15-compilers-ohpc",
        "openmpi5-gnu15-ohpc",
        "mpich-ofi-gnu15-ohpc",
        "mvapich2-gnu15-ohpc",
        "openblas-gnu15-ohpc",
        "likwid-gnu15-ohpc",
        "ohpc-gnu15-openmpi5-perf-tools",
    ]
    core_deb = [
        "gnu15-compilers-ohpc",
        "openmpi5-gnu15-ohpc",
        "mpich-gnu15-ohpc",
        "mvapich2-gnu15-ohpc",
        "openblas-gnu15-ohpc",
        "likwid-gnu15-ohpc",
        "ohpc-gnu15-openmpi5-perf-tools",
        "ohpc-gnu15-mpich-perf-tools",
    ]

    print("\nCore POWER package presence")
    status = 0
    status |= print_presence("  EL_10", el_names, core_rpm)
    status |= print_presence("  openEuler_24.03", oe_names, core_rpm)
    status |= print_presence("  Ubuntu_24.04 ppc64el/all", ubuntu_power, core_deb)

    print("\nOpenHPC dependency closure")
    closure_status = 0
    closure_status |= print_dependency_gaps("EL_10", rpm_sets["EL_10"])
    closure_status |= print_dependency_gaps("openEuler_24.03", rpm_sets["openEuler_24.03"])
    closure_status |= print_dependency_gaps(
        "Ubuntu_24.04 ppc64el/all",
        [pkg for pkg in deb_packages if pkg.arch in {"all", "ppc64el"}],
    )

    unexpected_ubuntu = sorted(
        name for name in ubuntu_power if any(token in name for token in EXPECTED_POWER_LOCKED_ABSENCES)
    )
    print("\nArchitecture-locked package check")
    architecture_status = 0
    if unexpected_ubuntu:
        print("  Ubuntu POWER still contains architecture-locked package names:")
        print("    " + ", ".join(unexpected_ubuntu))
        architecture_status = 1
    else:
        print("  Ubuntu POWER package names do not include the known x86/ARM-locked families")

    if args.fail_on_issues:
        return 1 if (status or delta_status or closure_status or architecture_status) else 0
    if args.fail_on_missing_core and status:
        return status
    return 0


if __name__ == "__main__":
    sys.exit(main())
