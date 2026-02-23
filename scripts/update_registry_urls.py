#!/usr/bin/env python3
"""Update registry with release URLs and file checksums."""

import hashlib
import json
import sys
from pathlib import Path


def compute_sha256(filepath: Path) -> str:
    """Compute SHA256 hash of a file."""
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            sha256.update(chunk)
    return sha256.hexdigest()


def main():
    if len(sys.argv) < 3:
        print("Usage: update_registry_urls.py <atlas_name> <release_tag>")
        sys.exit(1)

    atlas_name = sys.argv[1]
    release_tag = sys.argv[2]

    registry_path = Path("registry_new.json")
    registry = json.loads(registry_path.read_text())

    if atlas_name not in registry:
        print(f"Atlas {atlas_name} not in registry")
        sys.exit(1)

    export_dir = Path("exports") / atlas_name
    files = []

    base_url = f"https://github.com/ggsegverse/ggsegpy-data/releases/download/{release_tag}"

    for parquet_file in export_dir.glob("*.parquet"):
        files.append({
            "name": parquet_file.name,
            "url": f"{base_url}/{parquet_file.name}",
            "sha256": compute_sha256(parquet_file),
            "size": parquet_file.stat().st_size,
        })

    registry[atlas_name]["exported"] = True
    registry[atlas_name]["release_tag"] = release_tag
    registry[atlas_name]["release_url"] = f"https://github.com/ggsegverse/ggsegpy-data/releases/tag/{release_tag}"
    registry[atlas_name]["files"] = files

    registry_path.write_text(json.dumps(registry, indent=2))
    print(f"Updated registry for {atlas_name} with {len(files)} files")


if __name__ == "__main__":
    main()
