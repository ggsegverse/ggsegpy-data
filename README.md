# ggsegpy-data

Brain atlas data for [ggsegpy](https://github.com/ggsegverse/ggsegpy), auto-synced from the [ggsegverse r-universe](https://ggsegverse.r-universe.dev).

## How It Works

1. **Weekly sync** checks [ggsegverse.r-universe.dev](https://ggsegverse.r-universe.dev/api/packages) for atlas updates
2. **Changed atlases** (by SHA/version) are exported from R to compressed parquet
3. **GitHub releases** host the parquet files with checksums
4. **registry.json** tracks all available atlases and their download URLs

## Registry Format

```json
{
  "ggsegSchaefer": {
    "version": "2.0.0",
    "sha": "abc123...",
    "title": "Schaefer Atlas for the 'ggseg' Ecosystem",
    "exported": true,
    "release_tag": "ggsegSchaefer-v2.0.0",
    "files": [
      {
        "name": "schaefer_400_7n_2d.parquet",
        "url": "https://github.com/ggsegverse/ggsegpy-data/releases/download/...",
        "sha256": "...",
        "size": 12345
      }
    ]
  }
}
```

## Usage in ggsegpy

```python
from ggsegpy import fetch_atlas

# Downloads from this repo's releases, caches locally
schaefer = fetch_atlas("schaefer_400_7n")
```

## Manual Trigger

To force re-export an atlas:

```bash
gh workflow run sync-atlases.yml -f atlas=ggsegSchaefer
```

To re-export all atlases:

```bash
gh workflow run sync-atlases.yml -f force_all=true
```

## Available Atlases

See [registry.json](registry.json) for the current list.

| Source | Count |
|--------|-------|
| [ggsegverse r-universe](https://ggsegverse.r-universe.dev) | ~22 atlas packages |

## License

Atlas data is subject to the original atlas licenses. See individual R package documentation for details.
