#!/usr/bin/env python3
"""Compress parquet files with ZSTD for smaller releases."""

import sys
from pathlib import Path

import pyarrow.parquet as pq


def compress_parquet(directory: Path):
    """Recompress all parquet files in directory with ZSTD level 19."""
    for parquet_file in directory.glob("*.parquet"):
        print(f"  Compressing {parquet_file.name}...", end=" ")

        table = pq.read_table(parquet_file)
        old_size = parquet_file.stat().st_size

        pq.write_table(table, parquet_file, compression="zstd", compression_level=19)

        new_size = parquet_file.stat().st_size
        reduction = (1 - new_size / old_size) * 100
        print(f"{old_size/1024:.0f}KB -> {new_size/1024:.0f}KB ({reduction:.1f}% smaller)")


def main():
    if len(sys.argv) < 2:
        print("Usage: compress_parquet.py <directory>")
        sys.exit(1)

    directory = Path(sys.argv[1])
    if not directory.exists():
        print(f"Directory not found: {directory}")
        sys.exit(1)

    compress_parquet(directory)


if __name__ == "__main__":
    main()
