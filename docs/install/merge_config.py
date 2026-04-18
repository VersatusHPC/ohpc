#!/usr/bin/env python3
"""Merge OpenHPC install-guide YAML config fragments.

This replaces the previous Makefile dependency on the Go yq CLI. Ubuntu ships a
different Python/jq-based yq whose command line is incompatible with `yq
eval-all`, while PyYAML is already a documentation build dependency.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

import yaml


def merge(base: Any, override: Any) -> Any:
    if isinstance(base, dict) and isinstance(override, dict):
        merged = dict(base)
        for key, value in override.items():
            merged[key] = merge(merged[key], value) if key in merged else value
        return merged
    return override


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Merge YAML config fragments for install-guide generation."
    )
    parser.add_argument("--vc-revision", required=True)
    parser.add_argument("--vc-date", required=True)
    parser.add_argument("files", nargs="+")
    args = parser.parse_args()

    config: dict[str, Any] = {}
    for filename in args.files:
        with Path(filename).open("r", encoding="utf-8") as handle:
            fragment = yaml.safe_load(handle) or {}
        config = merge(config, fragment)

    config["vc_revision"] = args.vc_revision
    config["vc_date"] = args.vc_date
    yaml.safe_dump(config, sys.stdout, default_flow_style=False, sort_keys=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
