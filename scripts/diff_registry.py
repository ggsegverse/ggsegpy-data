#!/usr/bin/env python3
"""Compare old and new registry to find atlases needing update."""

import argparse
import json
from pathlib import Path


def load_registry(path):
    """Load registry JSON, return empty dict if not exists."""
    if not path.exists():
        return {}
    return json.loads(path.read_text())


def find_changed_atlases(old_reg, new_reg, force_all=False, specific_atlas=None):
    """Find atlases that need re-export."""
    changed = []

    for name, new_info in new_reg.items():
        if specific_atlas and name != specific_atlas:
            continue

        old_info = old_reg.get(name, {})

        needs_update = (
            force_all
            or old_info.get("sha") != new_info.get("sha")
            or old_info.get("version") != new_info.get("version")
            or not old_info.get("exported", False)
        )

        if needs_update:
            changed.append(name)

    return changed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", type=str, default="false")
    parser.add_argument("--atlas", type=str, default="")
    args = parser.parse_args()

    force_all = args.force.lower() == "true"
    specific_atlas = args.atlas if args.atlas else None

    old_reg = load_registry(Path("registry.json"))
    new_reg = load_registry(Path("registry_new.json"))

    changed = find_changed_atlases(old_reg, new_reg, force_all, specific_atlas)

    for atlas in sorted(changed):
        print(atlas)


if __name__ == "__main__":
    main()
