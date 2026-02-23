#!/usr/bin/env python3
"""Fetch package info from ggsegverse r-universe and build registry."""

import json
from pathlib import Path

import requests

R_UNIVERSE_API = "https://ggsegverse.r-universe.dev/api/packages"

ATLAS_PACKAGES = {
    "ggsegAAL",
    "ggsegAicha",
    "ggsegArslan",
    "ggsegBrainnetome",
    "ggsegBrodmann",
    "ggsegCampbell",
    "ggsegChen",
    "ggsegDKT",
    "ggsegDestrieux",
    "ggsegEconomo",
    "ggsegFlechsig",
    "ggsegGlasser",
    "ggsegGordon",
    "ggsegHO",
    "ggsegICBM",
    "ggsegIca",
    "ggsegJHU",
    "ggsegKleist",
    "ggsegPower",
    "ggsegSchaefer",
    "ggsegTracula",
    "ggsegYeo2011",
}


def fetch_packages():
    """Fetch package metadata from r-universe."""
    resp = requests.get(R_UNIVERSE_API, timeout=30)
    resp.raise_for_status()
    return resp.json()


def build_registry(packages):
    """Build registry from r-universe package data."""
    registry = {}

    for pkg in packages:
        name = pkg.get("Package", "")
        if name not in ATLAS_PACKAGES:
            continue

        registry[name] = {
            "version": pkg.get("Version", ""),
            "sha": pkg.get("RemoteSha", pkg.get("_commit", {}).get("id", "")),
            "title": pkg.get("Title", ""),
            "description": pkg.get("Description", ""),
            "exported": False,
            "release_url": None,
            "files": [],
        }

    return registry


def main():
    print("Fetching packages from r-universe...")
    packages = fetch_packages()
    print(f"Found {len(packages)} packages")

    registry = build_registry(packages)
    print(f"Filtered to {len(registry)} atlas packages")

    output = Path("registry_new.json")
    output.write_text(json.dumps(registry, indent=2))
    print(f"Wrote {output}")


if __name__ == "__main__":
    main()
